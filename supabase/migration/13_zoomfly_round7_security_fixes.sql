-- Round 7 security/correctness fixes found in a full-codebase audit.
-- All changes are additive/idempotent (CREATE OR REPLACE, DROP ... IF
-- EXISTS) and safe to run against an existing database.

-- ── 1. NULL-comparison bypass in enforce_safe_booking_insert() ─────
-- `NEW.user_id <> auth.uid()` evaluates to NULL (not TRUE) whenever
-- auth.uid() is NULL, i.e. for every unauthenticated/guest request —
-- so the "snap user_id back to the caller" correction never actually
-- ran for guest checkout, and an anonymous request could set
-- bookings.user_id to any arbitrary UUID, injecting a fake booking
-- into a victim's account history. IS DISTINCT FROM treats NULL
-- correctly (two NULLs are not "distinct", NULL vs non-NULL is).
SELECT public._drop_all_functions('enforce_safe_booking_insert');
CREATE OR REPLACE FUNCTION public.enforce_safe_booking_insert()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.role() <> 'service_role' THEN
    IF NEW.user_id IS DISTINCT FROM auth.uid() THEN
      NEW.user_id := auth.uid();
    END IF;
    NEW.status              := 'pending';
    NEW.payment_status       := 'pending';
    NEW.paid_amount          := 0;
    NEW.paid_at              := NULL;
    NEW.confirmed_at         := NULL;
    NEW.razorpay_payment_id  := NULL;
    NEW.razorpay_signature   := NULL;
    NEW.refund_status        := 'not_applicable';
    NEW.refund_amount        := 0;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_enforce_safe_booking_insert ON public.bookings;
CREATE TRIGGER trg_enforce_safe_booking_insert
  BEFORE INSERT ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.enforce_safe_booking_insert();

-- ── 2. Loyalty referral bonus could be farmed repeatedly ───────────
-- 06_zoomfly_referral_first_booking.sql added loyalty_accounts columns
-- referred_by / referral_bonus_awarded and made referral_bonus_awarded
-- the sole "only once" gate for the referral payout, but never added
-- those columns to this trigger's protected-column list. Since RLS
-- lets a user UPDATE their own loyalty_accounts row, a customer could
-- run `UPDATE loyalty_accounts SET referral_bonus_awarded = false
-- WHERE user_id = auth.uid()` themselves and re-trigger the bonus on
-- every subsequent booking.
SELECT public._drop_all_functions('protect_loyalty_privileged_columns');
CREATE OR REPLACE FUNCTION public.protect_loyalty_privileged_columns()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    NEW.points_balance          := OLD.points_balance;
    NEW.points_earned           := OLD.points_earned;
    NEW.points_redeemed         := OLD.points_redeemed;
    NEW.points_expired          := OLD.points_expired;
    NEW.tier                    := OLD.tier;
    NEW.tier_updated_at         := OLD.tier_updated_at;
    NEW.referral_count          := OLD.referral_count;
    NEW.referred_by             := OLD.referred_by;
    NEW.referral_bonus_awarded  := OLD.referral_bonus_awarded;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_protect_loyalty_privileged_columns ON public.loyalty_accounts;
CREATE TRIGGER trg_protect_loyalty_privileged_columns
  BEFORE UPDATE ON public.loyalty_accounts
  FOR EACH ROW EXECUTE FUNCTION public.protect_loyalty_privileged_columns();

-- ── 3. get_guest_booking() leaked internal fraud notes / payment IDs
-- It did `SELECT *`, returning internal_notes (which verify-razorpay-
-- payment/razorpay-webhook fill with fraud-review text such as
-- "PRICE MISMATCH ... payment_id=...") and the razorpay order/payment
-- /signature fields to anyone who supplies a valid booking_ref+email —
-- including the guest who was themselves flagged. Strip those columns.
SELECT public._drop_all_functions('get_guest_booking');
CREATE OR REPLACE FUNCTION public.get_guest_booking(p_ref TEXT, p_email TEXT)
RETURNS JSONB AS $$
  SELECT to_jsonb(b)
    - 'internal_notes'
    - 'razorpay_order_id'
    - 'razorpay_payment_id'
    - 'razorpay_signature'
  FROM public.bookings b
  WHERE booking_ref = UPPER(TRIM(p_ref))
    AND user_id IS NULL
    AND (lower(customer_email) = lower(TRIM(p_email)) OR lower(guest_email) = lower(TRIM(p_email)))
  LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public;
GRANT EXECUTE ON FUNCTION public.get_guest_booking(TEXT,TEXT) TO service_role;

-- ── 4. Avatar upload in the zoomfly-images bucket wasn't per-user ──
-- dashboard.html uploads to `avatars/<user_id>-<timestamp>.<ext>` —
-- the user id is a filename prefix, not its own subfolder, so the
-- existing check `(storage.foldername(name))[1] = 'avatars'` scoped
-- only to the bucket's top folder, not to the uploader. Any
-- authenticated user could overwrite any other user's avatar file.
DROP POLICY IF EXISTS "Users upload own avatar in zoomfly-images" ON storage.objects;
CREATE POLICY "Users upload own avatar in zoomfly-images" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'zoomfly-images'
  AND (storage.foldername(name))[1] = 'avatars'
  AND storage.filename(name) LIKE (auth.uid()::text || '-%')
);

-- ── 5. Vendor bank details/PAN/GSTIN readable by any logged-in user ─
-- vendors_select RLS is row-level only ("status IN ('active',
-- 'approved') OR own row OR admin"), and the table's blanket
-- `GRANT SELECT ... TO authenticated` covers every column — so any
-- logged-in customer (not just the vendor themselves or an admin)
-- could directly query bank_acc_num/bank_ifsc/pan/gstin for every
-- active/approved vendor via the REST API. Postgres RLS is row-level
-- only; it can't restrict this by column. Replace the blanket table
-- grant with two SECURITY DEFINER RPCs that self-check who's asking,
-- matching the pattern already used elsewhere in this schema
-- (get_guest_booking, earn_booking_points, etc).
REVOKE SELECT ON public.vendors FROM authenticated;

CREATE OR REPLACE FUNCTION public.get_own_vendor()
RETURNS SETOF public.vendors
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  SELECT * FROM public.vendors WHERE user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.get_vendors_admin()
RETURNS SETOF public.vendors
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  RETURN QUERY SELECT * FROM public.vendors ORDER BY created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_own_vendor() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_vendors_admin() TO authenticated, service_role;
