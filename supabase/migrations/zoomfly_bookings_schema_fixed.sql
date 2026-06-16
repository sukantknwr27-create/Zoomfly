-- ============================================================
--  ZOOMFLY BOOKINGS SCHEMA - FIXED (No ENUM type conflicts)
--  Uses TEXT columns instead of ENUM to avoid conflicts
--  Run this in Supabase SQL Editor
-- ============================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Bookings table (safe - uses TEXT not ENUM)
CREATE TABLE IF NOT EXISTS bookings (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_ref         TEXT,
  service_type        TEXT NOT NULL DEFAULT 'package',
  service_id          UUID,
  service_name        TEXT NOT NULL DEFAULT '',
  user_id             UUID,
  customer_name       TEXT NOT NULL DEFAULT '',
  customer_email      TEXT NOT NULL DEFAULT '',
  customer_phone      TEXT NOT NULL DEFAULT '',
  customer_whatsapp   TEXT,
  travel_details      JSONB NOT NULL DEFAULT '{}',
  num_adults          INTEGER NOT NULL DEFAULT 1,
  num_children        INTEGER NOT NULL DEFAULT 0,
  num_infants         INTEGER NOT NULL DEFAULT 0,
  travellers          JSONB DEFAULT '[]',
  base_amount         NUMERIC(12,2) NOT NULL DEFAULT 0,
  tax_amount          NUMERIC(12,2) NOT NULL DEFAULT 0,
  discount_amount     NUMERIC(12,2) NOT NULL DEFAULT 0,
  promo_code          TEXT,
  total_amount        NUMERIC(12,2) NOT NULL DEFAULT 0,
  currency            TEXT NOT NULL DEFAULT 'INR',
  payment_status      TEXT NOT NULL DEFAULT 'pending',
  payment_method      TEXT,
  razorpay_order_id   TEXT,
  razorpay_payment_id TEXT,
  razorpay_signature  TEXT,
  paid_at             TIMESTAMPTZ,
  refund_status       TEXT NOT NULL DEFAULT 'not_applicable',
  refund_amount       NUMERIC(12,2) DEFAULT 0,
  refund_reason       TEXT,
  refund_initiated_at TIMESTAMPTZ,
  refund_completed_at TIMESTAMPTZ,
  status              TEXT NOT NULL DEFAULT 'pending',
  status_history      JSONB DEFAULT '[]',
  confirmation_sent   BOOLEAN DEFAULT FALSE,
  whatsapp_sent       BOOLEAN DEFAULT FALSE,
  last_notified_at    TIMESTAMPTZ,
  assigned_to         TEXT,
  internal_notes      TEXT,
  vendor_id           UUID,
  vendor_confirmed    BOOLEAN DEFAULT FALSE,
  vendor_confirmed_at TIMESTAMPTZ,
  special_requests    TEXT,
  booking_source      TEXT DEFAULT 'website',
  utm_source          TEXT,
  utm_medium          TEXT,
  utm_campaign        TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  cancelled_at        TIMESTAMPTZ,
  completed_at        TIMESTAMPTZ
);

-- Add missing columns safely (in case table already exists)
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN booking_ref TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN service_type TEXT NOT NULL DEFAULT 'package'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN service_name TEXT NOT NULL DEFAULT ''; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN user_id UUID; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN customer_name TEXT NOT NULL DEFAULT ''; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN customer_email TEXT NOT NULL DEFAULT ''; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN customer_phone TEXT NOT NULL DEFAULT ''; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN customer_whatsapp TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN travel_details JSONB NOT NULL DEFAULT '{}'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN num_adults INTEGER NOT NULL DEFAULT 1; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN num_children INTEGER NOT NULL DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN num_infants INTEGER NOT NULL DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN travellers JSONB DEFAULT '[]'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN base_amount NUMERIC(12,2) NOT NULL DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN tax_amount NUMERIC(12,2) NOT NULL DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN discount_amount NUMERIC(12,2) NOT NULL DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN promo_code TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN total_amount NUMERIC(12,2) NOT NULL DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN currency TEXT NOT NULL DEFAULT 'INR'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN payment_status TEXT NOT NULL DEFAULT 'pending'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN payment_method TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN razorpay_order_id TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN razorpay_payment_id TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN razorpay_signature TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN paid_at TIMESTAMPTZ; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN refund_status TEXT NOT NULL DEFAULT 'not_applicable'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN refund_amount NUMERIC(12,2) DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN refund_reason TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN refund_initiated_at TIMESTAMPTZ; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN refund_completed_at TIMESTAMPTZ; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN status_history JSONB DEFAULT '[]'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN confirmation_sent BOOLEAN DEFAULT FALSE; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN whatsapp_sent BOOLEAN DEFAULT FALSE; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN last_notified_at TIMESTAMPTZ; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN assigned_to TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN internal_notes TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN vendor_id UUID; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN vendor_confirmed BOOLEAN DEFAULT FALSE; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN vendor_confirmed_at TIMESTAMPTZ; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN special_requests TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN booking_source TEXT DEFAULT 'website'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN utm_source TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN utm_medium TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN utm_campaign TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN cancelled_at TIMESTAMPTZ; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN completed_at TIMESTAMPTZ; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bookings ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(); EXCEPTION WHEN duplicate_column THEN NULL; END $$;

-- Add UNIQUE on booking_ref if not exists
DO $$ BEGIN
  ALTER TABLE bookings ADD CONSTRAINT bookings_booking_ref_key UNIQUE (booking_ref);
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

-- Booking ref generator
CREATE OR REPLACE FUNCTION generate_booking_ref(svc TEXT DEFAULT 'GEN')
RETURNS TEXT AS $$
DECLARE
  prefix   TEXT;
  date_str TEXT;
  seq_val  INT;
BEGIN
  prefix := CASE svc
    WHEN 'flight'  THEN 'FLT' WHEN 'hotel'   THEN 'HTL'
    WHEN 'package' THEN 'PKG' WHEN 'bus'      THEN 'BUS'
    WHEN 'cab'     THEN 'CAB' ELSE 'GEN'
  END;
  date_str := TO_CHAR(NOW(), 'YYYYMMDD');
  SELECT COUNT(*)+1 INTO seq_val FROM bookings WHERE DATE(created_at)=CURRENT_DATE;
  RETURN 'ZF-' || prefix || '-' || date_str || '-' || LPAD(seq_val::TEXT,4,'0');
END;
$$ LANGUAGE plpgsql;

-- Auto updated_at trigger
CREATE OR REPLACE FUNCTION bookings_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at:=NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_bookings_updated_at ON bookings;
CREATE TRIGGER trg_bookings_updated_at
  BEFORE UPDATE ON bookings
  FOR EACH ROW EXECUTE FUNCTION bookings_updated_at();

-- Auto booking ref on insert
CREATE OR REPLACE FUNCTION bookings_before_insert()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.booking_ref IS NULL OR NEW.booking_ref = '' THEN
    NEW.booking_ref := generate_booking_ref(NEW.service_type);
  END IF;
  IF NEW.total_amount = 0 THEN
    NEW.total_amount := NEW.base_amount + NEW.tax_amount - NEW.discount_amount;
  END IF;
  IF NEW.status_history IS NULL OR NEW.status_history = '[]'::jsonb THEN
    NEW.status_history := jsonb_build_array(jsonb_build_object(
      'status', NEW.status, 'changed_at', NOW(),
      'changed_by', 'system', 'note', 'Booking created'
    ));
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_bookings_before_insert ON bookings;
CREATE TRIGGER trg_bookings_before_insert
  BEFORE INSERT ON bookings
  FOR EACH ROW EXECUTE FUNCTION bookings_before_insert();

-- Status change tracker
CREATE OR REPLACE FUNCTION track_booking_status_change()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    NEW.status_history := COALESCE(OLD.status_history,'[]'::jsonb) || jsonb_build_object(
      'status', NEW.status, 'changed_at', NOW(),
      'changed_by', COALESCE(current_setting('app.current_user',true),'system'),
      'note', COALESCE(NEW.internal_notes,'')
    );
    IF NEW.status='cancelled' THEN NEW.cancelled_at:=NOW(); END IF;
    IF NEW.status='completed' THEN NEW.completed_at:=NOW(); END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_track_status_change ON bookings;
CREATE TRIGGER trg_track_status_change
  BEFORE UPDATE ON bookings
  FOR EACH ROW EXECUTE FUNCTION track_booking_status_change();

-- Indexes
CREATE INDEX IF NOT EXISTS idx_bookings_user_id        ON bookings(user_id);
CREATE INDEX IF NOT EXISTS idx_bookings_service_type   ON bookings(service_type);
CREATE INDEX IF NOT EXISTS idx_bookings_status         ON bookings(status);
CREATE INDEX IF NOT EXISTS idx_bookings_payment_status ON bookings(payment_status);
CREATE INDEX IF NOT EXISTS idx_bookings_created_at     ON bookings(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bookings_booking_ref    ON bookings(booking_ref);
CREATE INDEX IF NOT EXISTS idx_bookings_customer_email ON bookings(customer_email);
CREATE INDEX IF NOT EXISTS idx_bookings_customer_phone ON bookings(customer_phone);
CREATE INDEX IF NOT EXISTS idx_bookings_vendor_id      ON bookings(vendor_id);
CREATE INDEX IF NOT EXISTS idx_bookings_travel_details ON bookings USING gin(travel_details);

-- RLS
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own bookings"     ON bookings;
DROP POLICY IF EXISTS "Users can insert own bookings"   ON bookings;
DROP POLICY IF EXISTS "Users can update own bookings"   ON bookings;
DROP POLICY IF EXISTS "Admins can view all bookings"    ON bookings;
DROP POLICY IF EXISTS "Admins can update all bookings"  ON bookings;
DROP POLICY IF EXISTS "Admins can delete bookings"      ON bookings;
DROP POLICY IF EXISTS "Service role full access"        ON bookings;
DROP POLICY IF EXISTS "Guest bookings insert"           ON bookings;
DROP POLICY IF EXISTS "Guest bookings view by email"    ON bookings;

CREATE POLICY "Users can view own bookings"    ON bookings FOR SELECT USING (auth.uid()=user_id);
CREATE POLICY "Users can insert own bookings"  ON bookings FOR INSERT WITH CHECK (auth.uid()=user_id OR user_id IS NULL);
CREATE POLICY "Users can update own bookings"  ON bookings FOR UPDATE USING (auth.uid()=user_id AND status IN ('pending','confirmed')) WITH CHECK (auth.uid()=user_id);
CREATE POLICY "Admins can view all bookings"   ON bookings FOR SELECT USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id=auth.uid() AND profiles.role='admin'));
CREATE POLICY "Admins can update all bookings" ON bookings FOR UPDATE USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id=auth.uid() AND profiles.role='admin'));
CREATE POLICY "Admins can delete bookings"     ON bookings FOR DELETE USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id=auth.uid() AND profiles.role='admin'));
CREATE POLICY "Service role full access"       ON bookings FOR ALL USING (auth.role()='service_role');
CREATE POLICY "Guest bookings insert"          ON bookings FOR INSERT WITH CHECK (user_id IS NULL);
CREATE POLICY "Guest bookings view by email"   ON bookings FOR SELECT USING (user_id IS NULL);

-- Views
CREATE OR REPLACE VIEW v_bookings_daily AS
SELECT DATE(created_at) AS booking_date, service_type,
  COUNT(*) AS total_bookings,
  COUNT(*) FILTER (WHERE status='confirmed') AS confirmed,
  COUNT(*) FILTER (WHERE status='cancelled') AS cancelled,
  COUNT(*) FILTER (WHERE status='pending')   AS pending,
  SUM(total_amount) FILTER (WHERE payment_status='paid') AS revenue_inr
FROM bookings GROUP BY DATE(created_at), service_type ORDER BY booking_date DESC;

CREATE OR REPLACE VIEW v_revenue_by_service AS
SELECT service_type,
  COUNT(*) AS total_bookings,
  COUNT(*) FILTER (WHERE status='confirmed') AS confirmed_bookings,
  SUM(total_amount) AS gross_revenue,
  SUM(total_amount) FILTER (WHERE payment_status='paid') AS net_revenue,
  SUM(refund_amount) AS total_refunded,
  ROUND(AVG(total_amount),2) AS avg_booking_value
FROM bookings GROUP BY service_type ORDER BY net_revenue DESC NULLS LAST;

CREATE OR REPLACE VIEW v_bookings_recent AS
SELECT id, booking_ref, service_type, service_name,
  customer_name, customer_email, customer_phone, customer_whatsapp,
  num_adults, num_children, base_amount, tax_amount, discount_amount, total_amount,
  payment_status, payment_method, status, refund_status, refund_amount,
  confirmation_sent, whatsapp_sent, booking_source, special_requests,
  created_at, updated_at
FROM bookings WHERE created_at >= NOW() - INTERVAL '30 days' ORDER BY created_at DESC;

-- Helper functions
CREATE OR REPLACE FUNCTION confirm_payment(
  p_booking_id UUID, p_razorpay_order TEXT,
  p_razorpay_payment TEXT, p_razorpay_sig TEXT, p_method TEXT DEFAULT 'upi'
) RETURNS bookings AS $$
DECLARE result bookings;
BEGIN
  UPDATE bookings SET payment_status='paid', payment_method=p_method,
    razorpay_order_id=p_razorpay_order, razorpay_payment_id=p_razorpay_payment,
    razorpay_signature=p_razorpay_sig, paid_at=NOW(), status='confirmed', updated_at=NOW()
  WHERE id=p_booking_id RETURNING * INTO result;
  RETURN result;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION initiate_refund(p_booking_id UUID, p_refund_amount NUMERIC, p_reason TEXT)
RETURNS bookings AS $$
DECLARE result bookings;
BEGIN
  UPDATE bookings SET refund_status='requested', refund_amount=p_refund_amount,
    refund_reason=p_reason, refund_initiated_at=NOW(), status='cancelled', updated_at=NOW()
  WHERE id=p_booking_id RETURNING * INTO result;
  RETURN result;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_dashboard_stats()
RETURNS JSON AS $$
DECLARE result JSON;
BEGIN
  SELECT json_build_object(
    'total_bookings',     (SELECT COUNT(*) FROM bookings),
    'today_bookings',     (SELECT COUNT(*) FROM bookings WHERE DATE(created_at)=CURRENT_DATE),
    'pending_bookings',   (SELECT COUNT(*) FROM bookings WHERE status='pending'),
    'confirmed_bookings', (SELECT COUNT(*) FROM bookings WHERE status='confirmed'),
    'total_revenue',      (SELECT COALESCE(SUM(total_amount),0) FROM bookings WHERE payment_status='paid'),
    'today_revenue',      (SELECT COALESCE(SUM(total_amount),0) FROM bookings WHERE payment_status='paid' AND DATE(created_at)=CURRENT_DATE),
    'pending_refunds',    (SELECT COUNT(*) FROM bookings WHERE refund_status='requested')
  ) INTO result;
  RETURN result;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grants
GRANT SELECT, INSERT, UPDATE ON bookings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON bookings TO service_role;
GRANT SELECT ON v_bookings_daily TO authenticated;
GRANT SELECT ON v_revenue_by_service TO authenticated;
GRANT SELECT ON v_bookings_recent TO authenticated;
GRANT EXECUTE ON FUNCTION get_dashboard_stats() TO authenticated;
GRANT EXECUTE ON FUNCTION confirm_payment(UUID,TEXT,TEXT,TEXT,TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION initiate_refund(UUID,NUMERIC,TEXT) TO authenticated;

-- DONE
