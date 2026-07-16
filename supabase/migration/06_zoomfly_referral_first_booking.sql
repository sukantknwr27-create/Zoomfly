-- ============================================================
--  ZoomFly — 06: Referral bonus fires at first booking, not signup
--  Run AFTER 00-05. Safe to re-run (idempotent).
--
--  referral.html has always advertised "you get 500 points when your
--  friend makes their first booking (min ₹5,000), they get 250 points
--  off theirs" — but the only function that ever existed,
--  award_referral_bonus(), paid out both sides instantly at signup,
--  with no minimum-amount check and no "first booking" concept at
--  all. That's the referral half of the wiring bugs fixed in an
--  earlier PR (assets/js/supabase.js's signUp() was also inserting
--  into a `referrals` table that was never created — see
--  05_zoomfly_production_hardening.sql's history). This migration
--  makes the actual payout timing match what the page has always
--  promised.
--
--  New split:
--   - link_referral(p_referrer_code, p_new_user_id): called at
--     signup. Only records who referred whom (referred_by) — awards
--     nothing yet. Replaces award_referral_bonus() as what signUp()
--     calls.
--   - earn_booking_points(): unchanged for its normal per-booking
--     points, but now also checks — once per account, via the new
--     referral_bonus_awarded flag — whether this booking is the
--     first one for this user that meets the ₹5,000 minimum. If so,
--     it pays the referee their 250-point bonus and the referrer
--     their 500-point reward together, in the same call that already
--     runs right after a payment is verified
--     (verify-razorpay-payment / razorpay-webhook).
-- ============================================================

ALTER TABLE public.loyalty_accounts
  ADD COLUMN IF NOT EXISTS referral_bonus_awarded BOOLEAN NOT NULL DEFAULT FALSE;

-- ── Signup-time: link only, no payout ──────────────────────────────
SELECT public._drop_all_functions('award_referral_bonus');
SELECT public._drop_all_functions('link_referral');
CREATE OR REPLACE FUNCTION public.link_referral(p_referrer_code TEXT, p_new_user_id UUID)
RETURNS VOID AS $$
DECLARE referrer public.loyalty_accounts;
BEGIN
  IF p_new_user_id <> auth.uid() AND auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Cannot link a referral for another user''s account';
  END IF;
  SELECT * INTO referrer FROM public.loyalty_accounts WHERE referral_code = p_referrer_code;
  IF NOT FOUND THEN RETURN; END IF;
  IF referrer.user_id = p_new_user_id THEN RETURN; END IF; -- can't refer yourself
  UPDATE public.loyalty_accounts SET referred_by = referrer.id
  WHERE user_id = p_new_user_id AND referred_by IS NULL; -- first link wins, doesn't move later
END; $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
GRANT EXECUTE ON FUNCTION public.link_referral(TEXT, UUID) TO authenticated, service_role;

-- ── First-qualifying-booking payout, folded into earn_booking_points ──
SELECT public._drop_all_functions('earn_booking_points');
CREATE OR REPLACE FUNCTION public.earn_booking_points(
  p_user_id UUID, p_booking_id UUID, p_booking_ref TEXT, p_amount_paid NUMERIC
) RETURNS public.loyalty_accounts AS $$
DECLARE
  acct     public.loyalty_accounts;
  referrer public.loyalty_accounts;
  pts_rate NUMERIC; pts_earn INTEGER; new_bal INTEGER; new_tier TEXT;
  result   public.loyalty_accounts;
BEGIN
  IF p_user_id <> auth.uid() AND auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Cannot earn points on another user''s account';
  END IF;
  IF auth.role() <> 'service_role' AND NOT public.is_admin()
     AND NOT EXISTS (SELECT 1 FROM public.bookings WHERE id = p_booking_id AND user_id = p_user_id AND payment_status = 'paid') THEN
    RAISE EXCEPTION 'Booking is not a paid booking belonging to this user';
  END IF;
  INSERT INTO public.loyalty_accounts (user_id) VALUES (p_user_id) ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO acct FROM public.loyalty_accounts WHERE user_id=p_user_id;
  pts_rate := CASE acct.tier WHEN 'platinum' THEN 15 WHEN 'gold' THEN 10 WHEN 'silver' THEN 7 ELSE 5 END;
  pts_earn := GREATEST(1, FLOOR((p_amount_paid/100.0)*pts_rate));
  new_bal  := acct.points_balance + pts_earn;
  new_tier := CASE
    WHEN (acct.points_earned+pts_earn) >= 50000 THEN 'platinum'
    WHEN (acct.points_earned+pts_earn) >= 20000 THEN 'gold'
    WHEN (acct.points_earned+pts_earn) >= 5000  THEN 'silver'
    ELSE 'bronze'
  END;
  UPDATE public.loyalty_accounts SET
    points_balance=new_bal, points_earned=points_earned+pts_earn, tier=new_tier,
    tier_updated_at=CASE WHEN new_tier!=acct.tier THEN NOW() ELSE tier_updated_at END
  WHERE user_id=p_user_id RETURNING * INTO result;
  INSERT INTO public.loyalty_transactions (account_id, user_id, txn_type, points, balance_after, booking_ref, booking_id, description, expires_at)
  VALUES (acct.id, p_user_id, 'earn_booking', pts_earn, new_bal, p_booking_ref, p_booking_id,
    format('Earned %s points on booking %s', pts_earn, p_booking_ref), NOW()+INTERVAL '1 year');

  -- ── Referral payout — fires exactly once, on this user's first
  -- booking that meets the ₹5,000 minimum (referral.html's own stated
  -- terms). referral_bonus_awarded is the sole gate: it's FALSE until
  -- this fires, so an earlier non-qualifying (<₹5,000) booking simply
  -- doesn't trigger it, and a later qualifying one still can — no
  -- separate "is this booking #1" counting needed.
  IF acct.referred_by IS NOT NULL AND NOT acct.referral_bonus_awarded AND p_amount_paid >= 5000 THEN
    SELECT * INTO referrer FROM public.loyalty_accounts WHERE id = acct.referred_by;
    IF FOUND THEN
      -- Referee's own 250-point first-booking bonus
      UPDATE public.loyalty_accounts SET
        points_balance = points_balance + 250,
        points_earned  = points_earned + 250,
        referral_bonus_awarded = TRUE
      WHERE user_id = p_user_id RETURNING * INTO result;
      INSERT INTO public.loyalty_transactions (account_id, user_id, txn_type, points, balance_after, booking_ref, booking_id, description, expires_at)
      VALUES (acct.id, p_user_id, 'earn_referral_bonus', 250, result.points_balance, p_booking_ref, p_booking_id,
        'Referral bonus - your first booking', NOW()+INTERVAL '1 year');

      -- Referrer's 500-point reward
      UPDATE public.loyalty_accounts SET
        points_balance  = points_balance + 500,
        points_earned   = points_earned + 500,
        referral_count  = referral_count + 1
      WHERE id = referrer.id;
      INSERT INTO public.loyalty_transactions (account_id, user_id, txn_type, points, balance_after, description, expires_at)
      SELECT id, referrer.user_id, 'earn_referral', 500, points_balance,
        'Referral bonus - friend completed their first booking!', NOW()+INTERVAL '1 year'
      FROM public.loyalty_accounts WHERE id = referrer.id;
    END IF;
  END IF;

  RETURN result;
END; $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
GRANT EXECUTE ON FUNCTION public.earn_booking_points(UUID,UUID,TEXT,NUMERIC) TO authenticated, service_role;
