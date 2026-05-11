-- ============================================================
--  ZOOMFLY — VENDORS TABLE & PORTAL SQL
--  Run in Supabase SQL Editor
--
--  Covers:
--    1. vendors table (full schema)
--    2. listings JSONB column
--    3. RLS policies (vendor sees own, admin sees all)
--    4. Indexes
--    5. Auto updated_at trigger
--    6. Helper views
--    7. Sample data
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- 0. EXTENSIONS
-- ────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- ────────────────────────────────────────────────────────────
-- 1. ENUM: VENDOR STATUS & TYPE
-- ────────────────────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE vendor_status AS ENUM (
    'pending',    -- Registered, awaiting admin approval
    'active',     -- Approved and live
    'suspended',  -- Temporarily disabled
    'rejected'    -- Registration rejected
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE vendor_type AS ENUM (
    'hotel',
    'bus',
    'cab',
    'tour_operator',
    'airline',
    'other'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ────────────────────────────────────────────────────────────
-- 2. VENDORS TABLE
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS vendors (

  -- Identity
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id             UUID UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Business info
  business_name       TEXT NOT NULL,
  vendor_type         vendor_type NOT NULL DEFAULT 'hotel',
  description         TEXT,
  logo_url            TEXT,
  website             TEXT,

  -- Contact
  contact_name        TEXT NOT NULL,
  email               TEXT NOT NULL,
  phone               TEXT NOT NULL,
  whatsapp            TEXT,
  city                TEXT,
  state               TEXT,
  pincode             TEXT,
  address             TEXT,

  -- Legal
  gstin               TEXT,
  pan                 TEXT,
  trade_license       TEXT,
  business_reg_number TEXT,

  -- Bank / Payout
  bank_acc_name       TEXT,
  bank_acc_num        TEXT,
  bank_ifsc           TEXT,
  bank_name           TEXT,
  bank_branch         TEXT,

  -- Commission (override per vendor, default 10%)
  commission_rate     NUMERIC(5,2) DEFAULT 10.00,

  -- Status
  status              vendor_status NOT NULL DEFAULT 'pending',
  status_note         TEXT,         -- Admin note on approval/rejection
  approved_at         TIMESTAMPTZ,
  approved_by         TEXT,

  -- Listings (JSONB array of service listings)
  listings            JSONB DEFAULT '[]'::jsonb,
  /*
    Each listing object:
    {
      id:            uuid,
      name:          text,
      type:          'hotel'|'bus'|'cab'|'package',
      city:          text,
      price:         number,
      per:           'night'|'person'|'trip'|'seat',
      capacity:      text,
      description:   text,
      amenities:     string[],
      images:        string[],
      available_from: date,
      available_until: date,
      is_active:     boolean,
      created_at:    timestamp
    }
  */

  -- Stats (denormalised for performance)
  total_bookings      INTEGER DEFAULT 0,
  confirmed_bookings  INTEGER DEFAULT 0,
  total_revenue       NUMERIC(12,2) DEFAULT 0,
  avg_rating          NUMERIC(3,1),

  -- Metadata
  notes               TEXT,         -- Internal admin notes
  tags                TEXT[],       -- e.g. ['premium', 'featured']
  is_featured         BOOLEAN DEFAULT FALSE,

  -- Timestamps
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_active_at      TIMESTAMPTZ

);


-- ────────────────────────────────────────────────────────────
-- 3. AUTO updated_at TRIGGER
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION vendors_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_vendors_updated_at
  BEFORE UPDATE ON vendors
  FOR EACH ROW EXECUTE FUNCTION vendors_updated_at();


-- ────────────────────────────────────────────────────────────
-- 4. AUTO-APPROVE TRIGGER (optional — set to manual by default)
--    Uncomment to auto-activate vendors on signup
-- ────────────────────────────────────────────────────────────
/*
CREATE OR REPLACE FUNCTION auto_approve_vendor()
RETURNS TRIGGER AS $$
BEGIN
  NEW.status      := 'active';
  NEW.approved_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_auto_approve_vendor
  BEFORE INSERT ON vendors
  FOR EACH ROW EXECUTE FUNCTION auto_approve_vendor();
*/


-- ────────────────────────────────────────────────────────────
-- 5. SYNC VENDOR STATS FROM BOOKINGS
--    Call this after a booking is confirmed
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION sync_vendor_stats(p_vendor_id UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE vendors
  SET
    total_bookings     = (SELECT COUNT(*)                            FROM bookings WHERE vendor_id = p_vendor_id),
    confirmed_bookings = (SELECT COUNT(*) FILTER (WHERE status = 'confirmed' OR status = 'completed') FROM bookings WHERE vendor_id = p_vendor_id),
    total_revenue      = (SELECT COALESCE(SUM(total_amount),0)       FROM bookings WHERE vendor_id = p_vendor_id AND payment_status = 'paid'),
    last_active_at     = NOW()
  WHERE id = p_vendor_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ────────────────────────────────────────────────────────────
-- 6. INDEXES
-- ────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_vendors_user_id      ON vendors(user_id);
CREATE INDEX IF NOT EXISTS idx_vendors_status       ON vendors(status);
CREATE INDEX IF NOT EXISTS idx_vendors_type         ON vendors(vendor_type);
CREATE INDEX IF NOT EXISTS idx_vendors_city         ON vendors(city);
CREATE INDEX IF NOT EXISTS idx_vendors_featured     ON vendors(is_featured) WHERE is_featured = TRUE;
CREATE INDEX IF NOT EXISTS idx_vendors_listings     ON vendors USING gin(listings);
CREATE INDEX IF NOT EXISTS idx_vendors_email        ON vendors(email);


-- ────────────────────────────────────────────────────────────
-- 7. ROW LEVEL SECURITY
-- ────────────────────────────────────────────────────────────
ALTER TABLE vendors ENABLE ROW LEVEL SECURITY;

-- Drop existing policies cleanly
DROP POLICY IF EXISTS "Vendor can view own profile"   ON vendors;
DROP POLICY IF EXISTS "Vendor can update own profile" ON vendors;
DROP POLICY IF EXISTS "Vendor can insert own profile" ON vendors;
DROP POLICY IF EXISTS "Admins can view all vendors"   ON vendors;
DROP POLICY IF EXISTS "Admins can update all vendors" ON vendors;
DROP POLICY IF EXISTS "Service role full access"      ON vendors;
DROP POLICY IF EXISTS "Public can view active vendors" ON vendors;

-- Vendors: see and edit only their own row
CREATE POLICY "Vendor can view own profile"
  ON vendors FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Vendor can update own profile"
  ON vendors FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Vendor can insert own profile"
  ON vendors FOR INSERT
  WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

-- Admins: full access
CREATE POLICY "Admins can view all vendors"
  ON vendors FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role = 'admin'
    )
  );

CREATE POLICY "Admins can update all vendors"
  ON vendors FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role = 'admin'
    )
  );

-- Service role: bypass all
CREATE POLICY "Service role full access"
  ON vendors FOR ALL
  USING (auth.role() = 'service_role');

-- Public: view only active vendors (for hotel/package pages)
CREATE POLICY "Public can view active vendors"
  ON vendors FOR SELECT
  USING (status = 'active');


-- ────────────────────────────────────────────────────────────
-- 8. ADMIN VIEWS
-- ────────────────────────────────────────────────────────────

-- All vendors with booking counts
CREATE OR REPLACE VIEW v_vendors_overview AS
SELECT
  v.id,
  v.business_name,
  v.vendor_type,
  v.contact_name,
  v.email,
  v.phone,
  v.city,
  v.status,
  v.commission_rate,
  v.is_featured,
  v.total_bookings,
  v.confirmed_bookings,
  v.total_revenue,
  ROUND(v.total_revenue * (v.commission_rate / 100), 2)   AS commission_earned,
  ROUND(v.total_revenue * (1 - v.commission_rate / 100), 2) AS net_payout,
  jsonb_array_length(COALESCE(v.listings,'[]'::jsonb))    AS listing_count,
  v.created_at,
  v.approved_at,
  v.last_active_at
FROM vendors v
ORDER BY v.created_at DESC;

-- Pending approval vendors
CREATE OR REPLACE VIEW v_vendors_pending AS
SELECT
  id, business_name, vendor_type, contact_name,
  email, phone, city, gstin,
  created_at,
  EXTRACT(EPOCH FROM (NOW() - created_at))/3600 AS hours_since_registered
FROM vendors
WHERE status = 'pending'
ORDER BY created_at ASC;

-- Active vendors with their listings
CREATE OR REPLACE VIEW v_vendor_listings AS
SELECT
  v.id          AS vendor_id,
  v.business_name,
  v.vendor_type,
  v.city        AS vendor_city,
  v.status,
  v.commission_rate,
  l.value       AS listing
FROM vendors v,
  jsonb_array_elements(COALESCE(v.listings, '[]'::jsonb)) AS l
WHERE v.status = 'active';


-- ────────────────────────────────────────────────────────────
-- 9. HELPER FUNCTIONS
-- ────────────────────────────────────────────────────────────

-- Approve a vendor (admin use)
CREATE OR REPLACE FUNCTION approve_vendor(
  p_vendor_id UUID,
  p_note      TEXT DEFAULT NULL
)
RETURNS vendors AS $$
DECLARE result vendors;
BEGIN
  UPDATE vendors
  SET
    status      = 'active',
    approved_at = NOW(),
    approved_by = current_setting('app.current_user', true),
    status_note = COALESCE(p_note, 'Approved by admin'),
    updated_at  = NOW()
  WHERE id = p_vendor_id
  RETURNING * INTO result;
  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Reject a vendor (admin use)
CREATE OR REPLACE FUNCTION reject_vendor(
  p_vendor_id UUID,
  p_reason    TEXT
)
RETURNS vendors AS $$
DECLARE result vendors;
BEGIN
  UPDATE vendors
  SET
    status      = 'rejected',
    status_note = p_reason,
    updated_at  = NOW()
  WHERE id = p_vendor_id
  RETURNING * INTO result;
  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Suspend a vendor
CREATE OR REPLACE FUNCTION suspend_vendor(
  p_vendor_id UUID,
  p_reason    TEXT
)
RETURNS vendors AS $$
DECLARE result vendors;
BEGIN
  UPDATE vendors
  SET
    status      = 'suspended',
    status_note = p_reason,
    updated_at  = NOW()
  WHERE id = p_vendor_id
  RETURNING * INTO result;
  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add a listing to vendor (upsert by listing name)
CREATE OR REPLACE FUNCTION add_vendor_listing(
  p_vendor_id UUID,
  p_listing   JSONB
)
RETURNS vendors AS $$
DECLARE result vendors;
BEGIN
  -- Add uuid to listing if not present
  IF p_listing->>'id' IS NULL THEN
    p_listing := p_listing || jsonb_build_object('id', uuid_generate_v4()::text);
  END IF;
  -- Append to listings array
  UPDATE vendors
  SET listings   = COALESCE(listings, '[]'::jsonb) || jsonb_build_array(p_listing),
      updated_at = NOW()
  WHERE id = p_vendor_id
  RETURNING * INTO result;
  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Remove a listing by index
CREATE OR REPLACE FUNCTION remove_vendor_listing(
  p_vendor_id   UUID,
  p_listing_idx INTEGER
)
RETURNS vendors AS $$
DECLARE
  current_listings JSONB;
  new_listings     JSONB := '[]'::jsonb;
  i                INTEGER;
  result           vendors;
BEGIN
  SELECT listings INTO current_listings FROM vendors WHERE id = p_vendor_id;
  FOR i IN 0..jsonb_array_length(current_listings)-1 LOOP
    IF i != p_listing_idx THEN
      new_listings := new_listings || jsonb_build_array(current_listings->i);
    END IF;
  END LOOP;
  UPDATE vendors SET listings = new_listings, updated_at = NOW()
  WHERE id = p_vendor_id RETURNING * INTO result;
  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get vendor dashboard stats
CREATE OR REPLACE FUNCTION get_vendor_stats(p_user_id UUID)
RETURNS JSON AS $$
DECLARE
  v_id    UUID;
  result  JSON;
BEGIN
  SELECT id INTO v_id FROM vendors WHERE user_id = p_user_id;
  IF v_id IS NULL THEN RETURN '{"error":"Vendor not found"}'::JSON; END IF;

  SELECT json_build_object(
    'total_bookings',     (SELECT COUNT(*) FROM bookings WHERE vendor_id = v_id),
    'pending_bookings',   (SELECT COUNT(*) FROM bookings WHERE vendor_id = v_id AND status = 'pending'),
    'confirmed_bookings', (SELECT COUNT(*) FROM bookings WHERE vendor_id = v_id AND status IN ('confirmed','completed')),
    'total_revenue',      (SELECT COALESCE(SUM(total_amount),0) FROM bookings WHERE vendor_id = v_id AND payment_status = 'paid'),
    'month_revenue',      (SELECT COALESCE(SUM(total_amount),0) FROM bookings WHERE vendor_id = v_id AND payment_status = 'paid' AND DATE_TRUNC('month',created_at)=DATE_TRUNC('month',NOW())),
    'listing_count',      (SELECT jsonb_array_length(COALESCE(listings,'[]'::jsonb)) FROM vendors WHERE id = v_id)
  ) INTO result;
  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ────────────────────────────────────────────────────────────
-- 10. PROFILES TABLE UPDATE
--     Add vendor role to profiles if not already there
-- ────────────────────────────────────────────────────────────
-- Add 'vendor' to role enum if it doesn't exist
DO $$
BEGIN
  ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'vendor';
EXCEPTION WHEN others THEN NULL;
END $$;

-- If profiles table uses a TEXT role column instead:
-- ALTER TABLE profiles ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'customer';

-- Update profile role to vendor on vendor registration
CREATE OR REPLACE FUNCTION set_vendor_role()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE profiles SET role = 'vendor' WHERE id = NEW.user_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER trg_set_vendor_role
  AFTER INSERT ON vendors
  FOR EACH ROW EXECUTE FUNCTION set_vendor_role();


-- ────────────────────────────────────────────────────────────
-- 11. GRANTS
-- ────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE ON vendors TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON vendors TO service_role;
GRANT SELECT ON v_vendors_overview   TO authenticated;
GRANT SELECT ON v_vendors_pending    TO authenticated;
GRANT SELECT ON v_vendor_listings    TO authenticated, anon;
GRANT EXECUTE ON FUNCTION approve_vendor(UUID, TEXT)            TO authenticated;
GRANT EXECUTE ON FUNCTION reject_vendor(UUID, TEXT)             TO authenticated;
GRANT EXECUTE ON FUNCTION suspend_vendor(UUID, TEXT)            TO authenticated;
GRANT EXECUTE ON FUNCTION add_vendor_listing(UUID, JSONB)       TO authenticated;
GRANT EXECUTE ON FUNCTION remove_vendor_listing(UUID, INTEGER)  TO authenticated;
GRANT EXECUTE ON FUNCTION get_vendor_stats(UUID)                TO authenticated;
GRANT EXECUTE ON FUNCTION sync_vendor_stats(UUID)               TO authenticated, service_role;


-- ────────────────────────────────────────────────────────────
-- 12. SAMPLE VENDOR DATA (comment out before production)
-- ────────────────────────────────────────────────────────────
/*
INSERT INTO vendors (
  business_name, vendor_type, contact_name, email, phone,
  city, gstin, status, commission_rate, is_featured,
  description, listings
) VALUES
(
  'Hotel Grand Palace', 'hotel', 'Rajesh Kumar',
  'hotel@grandpalace.in', '9876543210', 'New Delhi',
  '07AABCU9603R1ZX', 'active', 10.00, true,
  'Luxury 4-star hotel in the heart of New Delhi with modern amenities.',
  '[
    {"id":"lst-001","name":"Deluxe Room","type":"hotel","city":"New Delhi","price":4500,"per":"night","capacity":"2 guests","description":"Spacious deluxe room with city view","amenities":["AC","WiFi","TV","Mini Bar","Breakfast"],"is_active":true,"created_at":"2026-01-01"},
    {"id":"lst-002","name":"Suite Room","type":"hotel","city":"New Delhi","price":8000,"per":"night","capacity":"4 guests","description":"Premium suite with living area","amenities":["AC","WiFi","TV","Jacuzzi","Breakfast","Airport Transfer"],"is_active":true,"created_at":"2026-01-01"}
  ]'::jsonb
),
(
  'Himachal Travels', 'bus', 'Suresh Thakur',
  'himachal@travels.in', '9812345678', 'Manali',
  '02AABCU9603R1ZX', 'active', 10.00, false,
  'Premium Volvo AC bus services on Delhi-Manali and Delhi-Shimla routes.',
  '[
    {"id":"lst-003","name":"Delhi → Manali (Volvo AC Sleeper)","type":"bus","city":"Delhi","price":1400,"per":"seat","capacity":"40 seats","description":"Overnight Volvo AC sleeper bus","amenities":["AC","Blanket","Charging Point","Water Bottle"],"is_active":true,"created_at":"2026-01-01"}
  ]'::jsonb
),
(
  'QuickCab Delhi', 'cab', 'Mohit Sharma',
  'quickcab@delhi.in', '9899887766', 'New Delhi',
  NULL, 'active', 10.00, false,
  'Reliable airport transfers and outstation cab services across Delhi NCR.',
  '[
    {"id":"lst-004","name":"Airport Transfer (Sedan)","type":"cab","city":"New Delhi","price":650,"per":"trip","capacity":"4 passengers","description":"AC sedan for airport pickup and drop","amenities":["AC","GPS","Driver Assistance"],"is_active":true,"created_at":"2026-01-01"},
    {"id":"lst-005","name":"Outstation SUV","type":"cab","city":"New Delhi","price":4500,"per":"trip","capacity":"6 passengers","description":"Comfortable SUV for outstation travel","amenities":["AC","GPS","Extra Luggage Space"],"is_active":true,"created_at":"2026-01-01"}
  ]'::jsonb
);
*/


-- ────────────────────────────────────────────────────────────
-- DONE ✅
--
-- Tables:    vendors
-- Enums:     vendor_status, vendor_type
-- Triggers:  auto updated_at, set_vendor_role, (optional auto_approve)
-- Views:     v_vendors_overview, v_vendors_pending, v_vendor_listings
-- Functions: approve_vendor, reject_vendor, suspend_vendor,
--            add_vendor_listing, remove_vendor_listing,
--            get_vendor_stats, sync_vendor_stats
-- RLS:       vendor sees own, admin sees all, public sees active
-- ────────────────────────────────────────────────────────────
