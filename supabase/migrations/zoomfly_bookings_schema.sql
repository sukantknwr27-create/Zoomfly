-- ============================================================
--  ZOOMFLY — COMPLETE BOOKINGS INFRASTRUCTURE
--  Run this entire file in Supabase SQL Editor
--  Covers: bookings, payments, status workflow, RLS, indexes,
--          helper functions, admin views
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- 0. EXTENSIONS
-- ────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- ────────────────────────────────────────────────────────────
-- 1. ENUM TYPES
-- ────────────────────────────────────────────────────────────

-- Booking status workflow
DO $$ BEGIN
  CREATE TYPE booking_status AS ENUM (
    'pending',       -- Payment initiated, awaiting confirmation
    'confirmed',     -- Payment received, booking confirmed
    'processing',    -- Being processed with vendor/airline
    'completed',     -- Journey completed
    'cancelled',     -- Cancelled by user or admin
    'refunded',      -- Refund processed
    'failed'         -- Payment failed
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Service type
DO $$ BEGIN
  CREATE TYPE service_type AS ENUM (
    'flight',
    'hotel',
    'package',
    'bus',
    'cab',
    'destination'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Payment method
DO $$ BEGIN
  CREATE TYPE payment_method AS ENUM (
    'upi',
    'card',
    'netbanking',
    'neft',
    'emi',
    'wallet',
    'cash',
    'other'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Payment status
DO $$ BEGIN
  CREATE TYPE payment_status AS ENUM (
    'pending',
    'paid',
    'partially_paid',
    'refund_initiated',
    'refunded',
    'failed'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Refund status
DO $$ BEGIN
  CREATE TYPE refund_status AS ENUM (
    'not_applicable',
    'requested',
    'approved',
    'processing',
    'completed',
    'rejected'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ────────────────────────────────────────────────────────────
-- 2. CORE BOOKINGS TABLE
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bookings (

  -- Identity
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_ref         TEXT UNIQUE NOT NULL,   -- e.g. ZF-FLT-20260509-0001
  
  -- Service
  service_type        service_type NOT NULL,
  service_id          UUID,                   -- FK to flights/hotels/packages etc (optional)
  service_name        TEXT NOT NULL,          -- Human readable e.g. "Delhi → Mumbai"

  -- Customer info (stored directly for guests + logged-in users)
  user_id             UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  customer_name       TEXT NOT NULL,
  customer_email      TEXT NOT NULL,
  customer_phone      TEXT NOT NULL,
  customer_whatsapp   TEXT,

  -- Travel details (flexible JSONB per service type)
  travel_details      JSONB NOT NULL DEFAULT '{}',
  /*
    FLIGHT:  { from, to, date, return_date, trip_type, airline, pnr, class }
    HOTEL:   { hotel_name, city, check_in, check_out, room_type, nights }
    PACKAGE: { package_name, destination, start_date, end_date, inclusions }
    BUS:     { from, to, date, operator, seat_numbers, departure_time }
    CAB:     { from, to, pickup_date, pickup_time, cab_type, driver_name }
  */

  -- Travellers
  num_adults          INTEGER NOT NULL DEFAULT 1,
  num_children        INTEGER NOT NULL DEFAULT 0,
  num_infants         INTEGER NOT NULL DEFAULT 0,
  travellers          JSONB DEFAULT '[]',
  /*
    [{ name, age, gender, id_type, id_number }]
  */

  -- Pricing
  base_amount         NUMERIC(12,2) NOT NULL DEFAULT 0,
  tax_amount          NUMERIC(12,2) NOT NULL DEFAULT 0,
  discount_amount     NUMERIC(12,2) NOT NULL DEFAULT 0,
  promo_code          TEXT,
  total_amount        NUMERIC(12,2) NOT NULL DEFAULT 0,
  currency            TEXT NOT NULL DEFAULT 'INR',

  -- Payment
  payment_status      payment_status NOT NULL DEFAULT 'pending',
  payment_method      payment_method,
  razorpay_order_id   TEXT,
  razorpay_payment_id TEXT,
  razorpay_signature  TEXT,
  paid_at             TIMESTAMPTZ,

  -- Refund
  refund_status       refund_status NOT NULL DEFAULT 'not_applicable',
  refund_amount       NUMERIC(12,2) DEFAULT 0,
  refund_reason       TEXT,
  refund_initiated_at TIMESTAMPTZ,
  refund_completed_at TIMESTAMPTZ,

  -- Booking status
  status              booking_status NOT NULL DEFAULT 'pending',
  status_history      JSONB DEFAULT '[]',
  /*
    [{ status, changed_at, changed_by, note }]
  */

  -- Communication
  confirmation_sent   BOOLEAN DEFAULT FALSE,
  whatsapp_sent       BOOLEAN DEFAULT FALSE,
  last_notified_at    TIMESTAMPTZ,

  -- Admin
  assigned_to         TEXT,                   -- Admin/agent who handled
  internal_notes      TEXT,
  vendor_id           UUID,                   -- FK to vendors table
  vendor_confirmed    BOOLEAN DEFAULT FALSE,
  vendor_confirmed_at TIMESTAMPTZ,

  -- Special requests
  special_requests    TEXT,

  -- Source tracking
  booking_source      TEXT DEFAULT 'website', -- website / whatsapp / admin / api
  utm_source          TEXT,
  utm_medium          TEXT,
  utm_campaign        TEXT,

  -- Timestamps
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  cancelled_at        TIMESTAMPTZ,
  completed_at        TIMESTAMPTZ

);

-- ────────────────────────────────────────────────────────────
-- 3. BOOKING REFERENCE GENERATOR
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION generate_booking_ref(svc service_type)
RETURNS TEXT AS $$
DECLARE
  prefix TEXT;
  date_str TEXT;
  seq_num TEXT;
  seq_val INT;
BEGIN
  -- Service prefix
  prefix := CASE svc
    WHEN 'flight'      THEN 'FLT'
    WHEN 'hotel'       THEN 'HTL'
    WHEN 'package'     THEN 'PKG'
    WHEN 'bus'         THEN 'BUS'
    WHEN 'cab'         THEN 'CAB'
    WHEN 'destination' THEN 'DST'
    ELSE 'GEN'
  END;

  -- Date portion
  date_str := TO_CHAR(NOW(), 'YYYYMMDD');

  -- Sequential number for today + service
  SELECT COUNT(*) + 1 INTO seq_val
  FROM bookings
  WHERE service_type = svc
    AND DATE(created_at) = CURRENT_DATE;

  seq_num := LPAD(seq_val::TEXT, 4, '0');

  RETURN 'ZF-' || prefix || '-' || date_str || '-' || seq_num;
END;
$$ LANGUAGE plpgsql;


-- ────────────────────────────────────────────────────────────
-- 4. AUTO-SET BOOKING REF + UPDATED_AT TRIGGER
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION bookings_before_insert()
RETURNS TRIGGER AS $$
BEGIN
  -- Auto-generate booking_ref if not set
  IF NEW.booking_ref IS NULL OR NEW.booking_ref = '' THEN
    NEW.booking_ref := generate_booking_ref(NEW.service_type);
  END IF;

  -- Auto-calculate total if not set
  IF NEW.total_amount = 0 THEN
    NEW.total_amount := NEW.base_amount + NEW.tax_amount - NEW.discount_amount;
  END IF;

  -- Initialize status history
  NEW.status_history := jsonb_build_array(
    jsonb_build_object(
      'status',     NEW.status,
      'changed_at', NOW(),
      'changed_by', 'system',
      'note',       'Booking created'
    )
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_bookings_before_insert
  BEFORE INSERT ON bookings
  FOR EACH ROW EXECUTE FUNCTION bookings_before_insert();

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION bookings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_bookings_updated_at
  BEFORE UPDATE ON bookings
  FOR EACH ROW EXECUTE FUNCTION bookings_updated_at();


-- ────────────────────────────────────────────────────────────
-- 5. STATUS CHANGE TRACKER TRIGGER
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION track_booking_status_change()
RETURNS TRIGGER AS $$
BEGIN
  -- Only run if status actually changed
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    NEW.status_history := COALESCE(OLD.status_history, '[]'::jsonb) || jsonb_build_object(
      'status',       NEW.status,
      'changed_at',   NOW(),
      'changed_by',   COALESCE(current_setting('app.current_user', true), 'system'),
      'note',         COALESCE(NEW.internal_notes, '')
    );

    -- Auto-set timestamps
    IF NEW.status = 'cancelled' THEN
      NEW.cancelled_at := NOW();
    END IF;
    IF NEW.status = 'completed' THEN
      NEW.completed_at := NOW();
    END IF;
    IF NEW.status = 'confirmed' AND NEW.payment_status = 'paid' THEN
      NEW.paid_at := COALESCE(NEW.paid_at, NOW());
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_track_status_change
  BEFORE UPDATE ON bookings
  FOR EACH ROW EXECUTE FUNCTION track_booking_status_change();


-- ────────────────────────────────────────────────────────────
-- 6. INDEXES
-- ────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_bookings_user_id       ON bookings(user_id);
CREATE INDEX IF NOT EXISTS idx_bookings_service_type  ON bookings(service_type);
CREATE INDEX IF NOT EXISTS idx_bookings_status        ON bookings(status);
CREATE INDEX IF NOT EXISTS idx_bookings_payment_status ON bookings(payment_status);
CREATE INDEX IF NOT EXISTS idx_bookings_created_at    ON bookings(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bookings_booking_ref   ON bookings(booking_ref);
CREATE INDEX IF NOT EXISTS idx_bookings_customer_email ON bookings(customer_email);
CREATE INDEX IF NOT EXISTS idx_bookings_customer_phone ON bookings(customer_phone);
CREATE INDEX IF NOT EXISTS idx_bookings_razorpay      ON bookings(razorpay_payment_id);
CREATE INDEX IF NOT EXISTS idx_bookings_vendor_id     ON bookings(vendor_id);
CREATE INDEX IF NOT EXISTS idx_bookings_travel_details ON bookings USING gin(travel_details);


-- ────────────────────────────────────────────────────────────
-- 7. ROW LEVEL SECURITY
-- ────────────────────────────────────────────────────────────
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;

-- Drop existing policies cleanly
DROP POLICY IF EXISTS "Users can view own bookings"     ON bookings;
DROP POLICY IF EXISTS "Users can insert own bookings"   ON bookings;
DROP POLICY IF EXISTS "Users can update own bookings"   ON bookings;
DROP POLICY IF EXISTS "Admins can view all bookings"    ON bookings;
DROP POLICY IF EXISTS "Admins can update all bookings"  ON bookings;
DROP POLICY IF EXISTS "Service role full access"        ON bookings;
DROP POLICY IF EXISTS "Guest bookings insert"           ON bookings;
DROP POLICY IF EXISTS "Guest bookings view by email"    ON bookings;

-- Logged-in users: view their own bookings
CREATE POLICY "Users can view own bookings"
  ON bookings FOR SELECT
  USING (auth.uid() = user_id);

-- Logged-in users: create bookings (user_id must match)
CREATE POLICY "Users can insert own bookings"
  ON bookings FOR INSERT
  WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

-- Logged-in users: cancel their own pending/confirmed bookings only
CREATE POLICY "Users can update own bookings"
  ON bookings FOR UPDATE
  USING (
    auth.uid() = user_id
    AND status IN ('pending', 'confirmed')
  )
  WITH CHECK (
    auth.uid() = user_id
    AND status IN ('pending', 'confirmed', 'cancelled')
  );

-- Admin: full access (checks profiles table for admin role)
CREATE POLICY "Admins can view all bookings"
  ON bookings FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role = 'admin'
    )
  );

CREATE POLICY "Admins can update all bookings"
  ON bookings FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role = 'admin'
    )
  );

CREATE POLICY "Admins can delete bookings"
  ON bookings FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role = 'admin'
    )
  );

-- Service role: bypass RLS (for server-side operations)
CREATE POLICY "Service role full access"
  ON bookings FOR ALL
  USING (auth.role() = 'service_role');

-- Guest insert: allow unauthenticated bookings (user_id = NULL)
CREATE POLICY "Guest bookings insert"
  ON bookings FOR INSERT
  WITH CHECK (user_id IS NULL);

-- Guest view: allow lookup by email (for booking status check)
CREATE POLICY "Guest bookings view by email"
  ON bookings FOR SELECT
  USING (
    user_id IS NULL
    AND customer_email = current_setting('app.guest_email', true)
  );


-- ────────────────────────────────────────────────────────────
-- 8. ADMIN VIEWS
-- ────────────────────────────────────────────────────────────

-- Daily bookings summary
CREATE OR REPLACE VIEW v_bookings_daily AS
SELECT
  DATE(created_at)                        AS booking_date,
  service_type,
  COUNT(*)                                AS total_bookings,
  COUNT(*) FILTER (WHERE status = 'confirmed')  AS confirmed,
  COUNT(*) FILTER (WHERE status = 'cancelled')  AS cancelled,
  COUNT(*) FILTER (WHERE status = 'pending')    AS pending,
  SUM(total_amount) FILTER (WHERE payment_status = 'paid') AS revenue_inr
FROM bookings
GROUP BY DATE(created_at), service_type
ORDER BY booking_date DESC, service_type;

-- Revenue by service type (all time)
CREATE OR REPLACE VIEW v_revenue_by_service AS
SELECT
  service_type,
  COUNT(*)                                    AS total_bookings,
  COUNT(*) FILTER (WHERE status = 'confirmed')    AS confirmed_bookings,
  SUM(total_amount)                           AS gross_revenue,
  SUM(total_amount) FILTER (WHERE payment_status = 'paid') AS net_revenue,
  SUM(refund_amount)                          AS total_refunded,
  ROUND(AVG(total_amount), 2)                 AS avg_booking_value
FROM bookings
GROUP BY service_type
ORDER BY net_revenue DESC NULLS LAST;

-- Pending action bookings (admin dashboard)
CREATE OR REPLACE VIEW v_bookings_pending_action AS
SELECT
  id, booking_ref, service_type, service_name,
  customer_name, customer_email, customer_phone,
  total_amount, payment_status, status,
  created_at,
  EXTRACT(EPOCH FROM (NOW() - created_at))/3600 AS hours_since_created
FROM bookings
WHERE status IN ('pending', 'processing')
  OR (status = 'confirmed' AND vendor_confirmed = FALSE)
  OR (status = 'cancelled' AND refund_status = 'requested')
ORDER BY created_at ASC;

-- Recent bookings (last 30 days)
CREATE OR REPLACE VIEW v_bookings_recent AS
SELECT
  b.id, b.booking_ref, b.service_type, b.service_name,
  b.customer_name, b.customer_email, b.customer_phone, b.customer_whatsapp,
  b.num_adults, b.num_children,
  b.base_amount, b.tax_amount, b.discount_amount, b.total_amount,
  b.payment_status, b.payment_method,
  b.status, b.refund_status, b.refund_amount,
  b.confirmation_sent, b.whatsapp_sent,
  b.booking_source, b.special_requests,
  b.created_at, b.updated_at
FROM bookings b
WHERE b.created_at >= NOW() - INTERVAL '30 days'
ORDER BY b.created_at DESC;


-- ────────────────────────────────────────────────────────────
-- 9. HELPER FUNCTIONS
-- ────────────────────────────────────────────────────────────

-- Get bookings for a customer by email
CREATE OR REPLACE FUNCTION get_bookings_by_email(p_email TEXT)
RETURNS SETOF bookings AS $$
  SELECT * FROM bookings
  WHERE LOWER(customer_email) = LOWER(p_email)
  ORDER BY created_at DESC;
$$ LANGUAGE sql SECURITY DEFINER;

-- Get bookings for a customer by phone
CREATE OR REPLACE FUNCTION get_bookings_by_phone(p_phone TEXT)
RETURNS SETOF bookings AS $$
  SELECT * FROM bookings
  WHERE customer_phone = p_phone
    OR customer_whatsapp = p_phone
  ORDER BY created_at DESC;
$$ LANGUAGE sql SECURITY DEFINER;

-- Update booking status (admin use)
CREATE OR REPLACE FUNCTION update_booking_status(
  p_booking_id UUID,
  p_new_status booking_status,
  p_note TEXT DEFAULT NULL
)
RETURNS bookings AS $$
DECLARE
  result bookings;
BEGIN
  UPDATE bookings
  SET
    status = p_new_status,
    internal_notes = COALESCE(p_note, internal_notes),
    updated_at = NOW()
  WHERE id = p_booking_id
  RETURNING * INTO result;

  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Mark payment as received
CREATE OR REPLACE FUNCTION confirm_payment(
  p_booking_id       UUID,
  p_razorpay_order   TEXT,
  p_razorpay_payment TEXT,
  p_razorpay_sig     TEXT,
  p_method           payment_method DEFAULT 'upi'
)
RETURNS bookings AS $$
DECLARE
  result bookings;
BEGIN
  UPDATE bookings
  SET
    payment_status      = 'paid',
    payment_method      = p_method,
    razorpay_order_id   = p_razorpay_order,
    razorpay_payment_id = p_razorpay_payment,
    razorpay_signature  = p_razorpay_sig,
    paid_at             = NOW(),
    status              = 'confirmed',
    updated_at          = NOW()
  WHERE id = p_booking_id
  RETURNING * INTO result;

  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Initiate refund
CREATE OR REPLACE FUNCTION initiate_refund(
  p_booking_id    UUID,
  p_refund_amount NUMERIC,
  p_reason        TEXT
)
RETURNS bookings AS $$
DECLARE
  result bookings;
BEGIN
  UPDATE bookings
  SET
    refund_status       = 'requested',
    refund_amount       = p_refund_amount,
    refund_reason       = p_reason,
    refund_initiated_at = NOW(),
    status              = 'cancelled',
    updated_at          = NOW()
  WHERE id = p_booking_id
  RETURNING * INTO result;

  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Complete refund
CREATE OR REPLACE FUNCTION complete_refund(p_booking_id UUID)
RETURNS bookings AS $$
DECLARE
  result bookings;
BEGIN
  UPDATE bookings
  SET
    refund_status       = 'completed',
    refund_completed_at = NOW(),
    payment_status      = 'refunded',
    status              = 'refunded',
    updated_at          = NOW()
  WHERE id = p_booking_id
  RETURNING * INTO result;

  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Dashboard stats (for admin panel)
CREATE OR REPLACE FUNCTION get_dashboard_stats()
RETURNS JSON AS $$
DECLARE
  result JSON;
BEGIN
  SELECT json_build_object(
    'total_bookings',       (SELECT COUNT(*) FROM bookings),
    'today_bookings',       (SELECT COUNT(*) FROM bookings WHERE DATE(created_at) = CURRENT_DATE),
    'pending_bookings',     (SELECT COUNT(*) FROM bookings WHERE status = 'pending'),
    'confirmed_bookings',   (SELECT COUNT(*) FROM bookings WHERE status = 'confirmed'),
    'cancelled_bookings',   (SELECT COUNT(*) FROM bookings WHERE status = 'cancelled'),
    'total_revenue',        (SELECT COALESCE(SUM(total_amount),0) FROM bookings WHERE payment_status = 'paid'),
    'today_revenue',        (SELECT COALESCE(SUM(total_amount),0) FROM bookings WHERE payment_status = 'paid' AND DATE(created_at) = CURRENT_DATE),
    'this_month_revenue',   (SELECT COALESCE(SUM(total_amount),0) FROM bookings WHERE payment_status = 'paid' AND DATE_TRUNC('month', created_at) = DATE_TRUNC('month', NOW())),
    'pending_refunds',      (SELECT COUNT(*) FROM bookings WHERE refund_status = 'requested'),
    'refund_amount_pending',(SELECT COALESCE(SUM(refund_amount),0) FROM bookings WHERE refund_status IN ('requested','approved','processing')),
    'by_service',           (SELECT json_agg(row_to_json(v)) FROM v_revenue_by_service v)
  ) INTO result;

  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ────────────────────────────────────────────────────────────
-- 10. SAMPLE TEST DATA (comment out before production)
-- ────────────────────────────────────────────────────────────
/*
INSERT INTO bookings (
  service_type, service_name,
  customer_name, customer_email, customer_phone, customer_whatsapp,
  travel_details, num_adults,
  base_amount, tax_amount, total_amount,
  status, payment_status, payment_method,
  razorpay_payment_id, paid_at,
  booking_source
) VALUES
(
  'flight', 'Delhi (DEL) → Mumbai (BOM)',
  'Rahul Sharma', 'rahul@example.com', '9876543210', '9876543210',
  '{"from":"DEL","to":"BOM","date":"2026-06-15","trip_type":"one_way","class":"economy"}',
  2,
  8500, 765, 9265,
  'confirmed', 'paid', 'upi',
  'pay_test_001', NOW() - INTERVAL '2 hours',
  'website'
),
(
  'hotel', 'The Taj Palace, New Delhi',
  'Priya Mehta', 'priya@example.com', '9123456780', '9123456780',
  '{"hotel_name":"The Taj Palace","city":"New Delhi","check_in":"2026-06-20","check_out":"2026-06-23","room_type":"Deluxe","nights":3}',
  2,
  18000, 3240, 21240,
  'confirmed', 'paid', 'card',
  'pay_test_002', NOW() - INTERVAL '5 hours',
  'whatsapp'
),
(
  'package', 'Goa Beach Escape — 4N/5D',
  'Amit Gupta', 'amit@example.com', '9988776655', '9988776655',
  '{"package_name":"Goa Beach Escape","destination":"Goa","start_date":"2026-07-01","end_date":"2026-07-05","inclusions":["Hotel","Breakfast","Airport Transfer"]}',
  4,
  45000, 8100, 53100,
  'pending', 'pending', NULL,
  NULL, NULL,
  'website'
),
(
  'bus', 'Delhi → Manali (Volvo AC Sleeper)',
  'Sunita Rawat', 'sunita@example.com', '9871234567', '9871234567',
  '{"from":"Delhi","to":"Manali","date":"2026-06-18","operator":"HRTC Volvo","seat_numbers":["A1","A2"],"departure_time":"20:00"}',
  2,
  2800, 252, 3052,
  'confirmed', 'paid', 'upi',
  'pay_test_003', NOW() - INTERVAL '1 day',
  'website'
),
(
  'cab', 'Delhi Airport → Connaught Place',
  'Vikram Singh', 'vikram@example.com', '9765432109', '9765432109',
  '{"from":"IGI Airport Terminal 3","to":"Connaught Place","pickup_date":"2026-06-16","pickup_time":"14:30","cab_type":"Sedan"}',
  1,
  650, 117, 767,
  'confirmed', 'paid', 'upi',
  'pay_test_004', NOW() - INTERVAL '3 hours',
  'whatsapp'
);
*/


-- ────────────────────────────────────────────────────────────
-- 11. GRANT PERMISSIONS
-- ────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE ON bookings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON bookings TO service_role;
GRANT SELECT ON v_bookings_daily TO authenticated;
GRANT SELECT ON v_revenue_by_service TO authenticated;
GRANT SELECT ON v_bookings_pending_action TO authenticated;
GRANT SELECT ON v_bookings_recent TO authenticated;
GRANT EXECUTE ON FUNCTION get_dashboard_stats() TO authenticated;
GRANT EXECUTE ON FUNCTION get_bookings_by_email(TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION get_bookings_by_phone(TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION update_booking_status(UUID, booking_status, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION confirm_payment(UUID, TEXT, TEXT, TEXT, payment_method) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION initiate_refund(UUID, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION complete_refund(UUID) TO authenticated;


-- ────────────────────────────────────────────────────────────
-- DONE ✅
-- Tables:    bookings
-- Enums:     booking_status, service_type, payment_method,
--            payment_status, refund_status
-- Triggers:  auto booking_ref, updated_at, status history
-- Views:     v_bookings_daily, v_revenue_by_service,
--            v_bookings_pending_action, v_bookings_recent
-- Functions: generate_booking_ref, confirm_payment,
--            initiate_refund, complete_refund,
--            get_dashboard_stats, get_bookings_by_email,
--            get_bookings_by_phone, update_booking_status
-- RLS:       users see own, admins see all, guests by email
-- ────────────────────────────────────────────────────────────
