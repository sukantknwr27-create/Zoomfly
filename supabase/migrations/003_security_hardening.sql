-- ============================================================
--  ZOOMFLY — SECURITY HARDENING (Pre-Production Audit Fixes)
--  Run this AFTER zoomfly_bookings_schema_fixed.sql
--
--  Fixes 3 critical issues found in production audit (July 2026):
--
--  1) "Guest bookings view by email" policy used `user_id IS NULL`
--     as its ONLY condition. Since the anon key is public (it ships
--     in the JS bundle), anyone could call the Supabase REST API
--     directly and read EVERY guest booking ever made — names,
--     emails, phone numbers, travel details, and payment status —
--     with zero authentication. This migration removes public read
--     access to guest bookings entirely; guest lookups now go
--     through the `get-guest-booking` edge function, which checks
--     that the requester actually knows the booking_ref + the
--     email/phone on file before returning anything.
--
--  2) "Users can update own bookings" only checked row ownership,
--     not which columns were being changed. A signed-in customer
--     could open devtools and run:
--       supabase.from('bookings').update({status:'confirmed',
--         payment_status:'paid', total_amount:1}).eq('id', myId)
--     and get themselves a free / underpriced trip. This migration
--     adds a trigger that blocks customers (non-admin, non-service-
--     role) from touching pricing, payment, or status fields —
--     they may still update contact/traveller details and request
--     a cancellation, nothing else.
--
--  3) (Companion fix, done in edge functions, not SQL): the
--     create-razorpay-order function trusted a client-supplied
--     `amount` instead of pricing the order from the booking row
--     itself, and verify-razorpay-payment never cross-checked the
--     amount actually captured by Razorpay. See the patched .ts
--     files — a user could otherwise request an order for ₹1 and
--     have the booking marked "paid" at full price anyway.
-- ============================================================

-- ── 1. LOCK DOWN GUEST BOOKING READS ─────────────────────────
DROP POLICY IF EXISTS "Guest bookings view by email" ON bookings;
-- No replacement SELECT policy for anon/guest rows: guest bookings
-- are now only readable via the get-guest-booking edge function
-- (service-role) or by admins. Logged-in users still see their own
-- bookings via the existing "Users can view own bookings" policy.

-- ── 2. LOCK DOWN WHICH COLUMNS A CUSTOMER CAN CHANGE ─────────
CREATE OR REPLACE FUNCTION prevent_customer_field_tampering()
RETURNS TRIGGER AS $$
DECLARE
  is_privileged BOOLEAN;
BEGIN
  -- Service role and admins can change anything.
  is_privileged := (auth.role() = 'service_role') OR EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
  );

  IF is_privileged THEN
    RETURN NEW;
  END IF;

  -- A plain customer may only ever move status -> 'cancelled'.
  -- Everything else protected below must stay exactly as it was.
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status <> 'cancelled' THEN
    RAISE EXCEPTION 'Not allowed to change booking status to %', NEW.status;
  END IF;

  IF NEW.base_amount        IS DISTINCT FROM OLD.base_amount
  OR NEW.tax_amount          IS DISTINCT FROM OLD.tax_amount
  OR NEW.discount_amount     IS DISTINCT FROM OLD.discount_amount
  OR NEW.total_amount        IS DISTINCT FROM OLD.total_amount
  OR NEW.payment_status      IS DISTINCT FROM OLD.payment_status
  OR NEW.payment_method      IS DISTINCT FROM OLD.payment_method
  OR NEW.razorpay_order_id   IS DISTINCT FROM OLD.razorpay_order_id
  OR NEW.razorpay_payment_id IS DISTINCT FROM OLD.razorpay_payment_id
  OR NEW.razorpay_signature  IS DISTINCT FROM OLD.razorpay_signature
  OR NEW.paid_at             IS DISTINCT FROM OLD.paid_at
  OR NEW.refund_status       IS DISTINCT FROM OLD.refund_status
  OR NEW.refund_amount       IS DISTINCT FROM OLD.refund_amount
  OR NEW.assigned_to         IS DISTINCT FROM OLD.assigned_to
  OR NEW.internal_notes      IS DISTINCT FROM OLD.internal_notes
  THEN
    RAISE EXCEPTION 'Customers cannot modify pricing, payment, or internal fields directly';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_prevent_customer_field_tampering ON bookings;
CREATE TRIGGER trg_prevent_customer_field_tampering
  BEFORE UPDATE ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION prevent_customer_field_tampering();

-- ── 3. HELPER RPC FOR GUEST BOOKING LOOKUP (used by edge fn) ─
-- Kept as SECURITY DEFINER so the edge function's service-role
-- call can look up a single booking without a broad table grant.
CREATE OR REPLACE FUNCTION get_guest_booking(p_ref TEXT, p_email TEXT)
RETURNS SETOF bookings AS $$
  SELECT * FROM bookings
  WHERE booking_ref = UPPER(TRIM(p_ref))
    AND user_id IS NULL
    AND lower(customer_email) = lower(TRIM(p_email))
  LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public;
