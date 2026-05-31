-- ============================================================
--  ZOOMFLY VENDORS SCHEMA - FIXED (No ENUM conflicts)
--  Uses TEXT columns instead of ENUM types
--  Run this in Supabase SQL Editor
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Vendors table (TEXT instead of ENUM to avoid conflicts)
CREATE TABLE IF NOT EXISTS vendors (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id             UUID UNIQUE,
  business_name       TEXT NOT NULL,
  vendor_type         TEXT NOT NULL DEFAULT 'hotel',
  description         TEXT,
  logo_url            TEXT,
  website             TEXT,
  contact_name        TEXT NOT NULL DEFAULT '',
  email               TEXT NOT NULL DEFAULT '',
  phone               TEXT NOT NULL DEFAULT '',
  whatsapp            TEXT,
  city                TEXT,
  state               TEXT,
  pincode             TEXT,
  address             TEXT,
  gstin               TEXT,
  pan                 TEXT,
  trade_license       TEXT,
  business_reg_number TEXT,
  bank_acc_name       TEXT,
  bank_acc_num        TEXT,
  bank_ifsc           TEXT,
  bank_name           TEXT,
  bank_branch         TEXT,
  commission_rate     NUMERIC(5,2) DEFAULT 10.00,
  status              TEXT NOT NULL DEFAULT 'pending',
  status_note         TEXT,
  approved_at         TIMESTAMPTZ,
  approved_by         TEXT,
  listings            JSONB DEFAULT '[]',
  total_bookings      INTEGER DEFAULT 0,
  confirmed_bookings  INTEGER DEFAULT 0,
  total_revenue       NUMERIC(12,2) DEFAULT 0,
  avg_rating          NUMERIC(3,1),
  notes               TEXT,
  tags                TEXT[],
  is_featured         BOOLEAN DEFAULT FALSE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_active_at      TIMESTAMPTZ
);

-- Add missing columns safely
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN user_id UUID UNIQUE; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN business_name TEXT NOT NULL DEFAULT ''; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN vendor_type TEXT NOT NULL DEFAULT 'hotel'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN description TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN contact_name TEXT NOT NULL DEFAULT ''; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN email TEXT NOT NULL DEFAULT ''; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN phone TEXT NOT NULL DEFAULT ''; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN whatsapp TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN city TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN gstin TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN pan TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN bank_acc_name TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN bank_acc_num TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN bank_ifsc TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN bank_name TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN commission_rate NUMERIC(5,2) DEFAULT 10.00; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN status_note TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN approved_at TIMESTAMPTZ; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN approved_by TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN listings JSONB DEFAULT '[]'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN total_bookings INTEGER DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN confirmed_bookings INTEGER DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN total_revenue NUMERIC(12,2) DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN avg_rating NUMERIC(3,1); EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN is_featured BOOLEAN DEFAULT FALSE; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN tags TEXT[]; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN notes TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(); EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vendors ADD COLUMN last_active_at TIMESTAMPTZ; EXCEPTION WHEN duplicate_column THEN NULL; END $$;

-- Auto updated_at
CREATE OR REPLACE FUNCTION vendors_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at:=NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_vendors_updated_at ON vendors;
CREATE TRIGGER trg_vendors_updated_at
  BEFORE UPDATE ON vendors
  FOR EACH ROW EXECUTE FUNCTION vendors_updated_at();

-- Set vendor role on vendor insert
CREATE OR REPLACE FUNCTION set_vendor_role()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE profiles SET role='vendor' WHERE id=NEW.user_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_set_vendor_role ON vendors;
CREATE TRIGGER trg_set_vendor_role
  AFTER INSERT ON vendors
  FOR EACH ROW EXECUTE FUNCTION set_vendor_role();

-- Indexes
CREATE INDEX IF NOT EXISTS idx_vendors_user_id  ON vendors(user_id);
CREATE INDEX IF NOT EXISTS idx_vendors_status   ON vendors(status);
CREATE INDEX IF NOT EXISTS idx_vendors_type     ON vendors(vendor_type);
CREATE INDEX IF NOT EXISTS idx_vendors_city     ON vendors(city);
CREATE INDEX IF NOT EXISTS idx_vendors_featured ON vendors(is_featured) WHERE is_featured=TRUE;
CREATE INDEX IF NOT EXISTS idx_vendors_listings ON vendors USING gin(listings);
CREATE INDEX IF NOT EXISTS idx_vendors_email    ON vendors(email);

-- RLS
ALTER TABLE vendors ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Vendor can view own profile"    ON vendors;
DROP POLICY IF EXISTS "Vendor can update own profile"  ON vendors;
DROP POLICY IF EXISTS "Vendor can insert own profile"  ON vendors;
DROP POLICY IF EXISTS "Admins can view all vendors"    ON vendors;
DROP POLICY IF EXISTS "Admins can update all vendors"  ON vendors;
DROP POLICY IF EXISTS "Service role full access"       ON vendors;
DROP POLICY IF EXISTS "Public can view active vendors" ON vendors;

CREATE POLICY "Vendor can view own profile"    ON vendors FOR SELECT USING (auth.uid()=user_id);
CREATE POLICY "Vendor can update own profile"  ON vendors FOR UPDATE USING (auth.uid()=user_id) WITH CHECK (auth.uid()=user_id);
CREATE POLICY "Vendor can insert own profile"  ON vendors FOR INSERT WITH CHECK (auth.uid()=user_id OR user_id IS NULL);
CREATE POLICY "Admins can view all vendors"    ON vendors FOR SELECT USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id=auth.uid() AND profiles.role='admin'));
CREATE POLICY "Admins can update all vendors"  ON vendors FOR UPDATE USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id=auth.uid() AND profiles.role='admin'));
CREATE POLICY "Service role full access"       ON vendors FOR ALL USING (auth.role()='service_role');
CREATE POLICY "Public can view active vendors" ON vendors FOR SELECT USING (status='active');

-- Helper functions
CREATE OR REPLACE FUNCTION approve_vendor(p_vendor_id UUID, p_note TEXT DEFAULT NULL)
RETURNS vendors AS $$
DECLARE result vendors;
BEGIN
  UPDATE vendors SET status='active', approved_at=NOW(),
    approved_by=current_setting('app.current_user',true),
    status_note=COALESCE(p_note,'Approved by admin'), updated_at=NOW()
  WHERE id=p_vendor_id RETURNING * INTO result;
  RETURN result;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION reject_vendor(p_vendor_id UUID, p_reason TEXT)
RETURNS vendors AS $$
DECLARE result vendors;
BEGIN
  UPDATE vendors SET status='rejected', status_note=p_reason, updated_at=NOW()
  WHERE id=p_vendor_id RETURNING * INTO result;
  RETURN result;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION suspend_vendor(p_vendor_id UUID, p_reason TEXT)
RETURNS vendors AS $$
DECLARE result vendors;
BEGIN
  UPDATE vendors SET status='suspended', status_note=p_reason, updated_at=NOW()
  WHERE id=p_vendor_id RETURNING * INTO result;
  RETURN result;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

-- Admin views
CREATE OR REPLACE VIEW v_vendors_overview AS
SELECT v.id, v.business_name, v.vendor_type, v.contact_name, v.email, v.phone, v.city,
  v.status, v.commission_rate, v.is_featured, v.total_bookings, v.confirmed_bookings,
  v.total_revenue,
  ROUND(v.total_revenue*(v.commission_rate/100),2) AS commission_earned,
  jsonb_array_length(COALESCE(v.listings,'[]'::jsonb)) AS listing_count,
  v.created_at, v.approved_at, v.last_active_at
FROM vendors v ORDER BY v.created_at DESC;

CREATE OR REPLACE VIEW v_vendors_pending AS
SELECT id, business_name, vendor_type, contact_name, email, phone, city, gstin, created_at
FROM vendors WHERE status='pending' ORDER BY created_at ASC;

CREATE OR REPLACE VIEW v_vendor_listings AS
SELECT v.id AS vendor_id, v.business_name, v.vendor_type, v.city AS vendor_city,
  v.status, v.commission_rate, l.value AS listing
FROM vendors v, jsonb_array_elements(COALESCE(v.listings,'[]'::jsonb)) AS l
WHERE v.status='active';

-- Grants
GRANT SELECT, INSERT, UPDATE ON vendors TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON vendors TO service_role;
GRANT SELECT ON v_vendors_overview TO authenticated;
GRANT SELECT ON v_vendors_pending TO authenticated;
GRANT SELECT ON v_vendor_listings TO authenticated, anon;
GRANT EXECUTE ON FUNCTION approve_vendor(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION reject_vendor(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION suspend_vendor(UUID,TEXT) TO authenticated;

-- DONE
