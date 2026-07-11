-- ================================================================
-- ZoomFly — 01_zoomfly_growth_features.sql
-- Run AFTER 00_zoomfly_master_schema.sql, against STAGING first.
--
-- What this file does (each block is idempotent/safe to re-run):
--   1. vendor_payouts — a real payout ledger for vendors, mirroring
--      the agent_payouts table that already existed. Today vendors
--      only see a *computed* running commission total in the portal;
--      there is no record of what was actually paid, when, or how.
--      That's the #1 reason vendor/hotel partners churn off a
--      marketplace — "I can't tell if or when I'll get paid."
--   2. public_recent_activity — a SAFE, anonymized view for the
--      homepage "social proof" widget, backed by real bookings
--      instead of the hardcoded fake-name array in index.html.
--      Exposes only: first name + last-initial, service name,
--      destination-free description, and a rounded time bucket.
--      No email/phone/amount/exact-name is exposed.
--   3. Agent tier <-> commission_rate consistency fix. The DB trigger
--      (auto_upgrade_agent_tier) already sets tier to
--      associate/silver/gold/platinum based on lifetime booking
--      value, but never updates commission_rate — so an agent can be
--      promoted to "gold" in the database while still being paid the
--      5% associate rate, and the agent-portal.html frontend uses a
--      totally different tier vocabulary (associate/senior/elite)
--      that doesn't match what's actually stored. This block makes
--      the trigger update commission_rate too, and the accompanying
--      frontend change (agent-portal.html) aligns the UI to the same
--      tier names/thresholds so what an agent sees matches what
--      they're actually paid.
-- ================================================================

-- ----------------------------------------------------------------
-- 1. VENDOR PAYOUTS
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.vendor_payouts (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  vendor_id      UUID NOT NULL REFERENCES public.vendors(id),
  amount         NUMERIC(12,2) NOT NULL DEFAULT 0,   -- gross booking value covered by this payout
  commission     NUMERIC(12,2) NOT NULL DEFAULT 0,   -- ZoomFly's cut, deducted
  net_amount     NUMERIC(12,2) NOT NULL DEFAULT 0,   -- what actually gets transferred
  payout_status  TEXT NOT NULL DEFAULT 'pending' CHECK (payout_status IN ('pending','processing','paid','failed','on_hold')),
  payout_method  TEXT DEFAULT 'neft',
  utr_number     TEXT,                               -- bank reference once paid — vendor's proof
  payout_date    DATE,
  booking_ids    UUID[],                              -- which bookings this payout covers
  booking_count  INTEGER DEFAULT 0,
  period_start   DATE,
  period_end     DATE,
  processed_by   TEXT,
  notes          TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_vendor_payouts_vendor_id ON public.vendor_payouts(vendor_id);
CREATE INDEX IF NOT EXISTS idx_vendor_payouts_status    ON public.vendor_payouts(payout_status);

ALTER TABLE public.vendor_payouts ENABLE ROW LEVEL SECURITY;

-- Vendors can see only their own payout rows. Nothing else.
DROP POLICY IF EXISTS vendor_payouts_select_own ON public.vendor_payouts;
CREATE POLICY vendor_payouts_select_own ON public.vendor_payouts
  FOR SELECT USING (
    vendor_id IN (SELECT id FROM public.vendors WHERE user_id = auth.uid())
  );

-- Only admins may insert/update/delete payout records — same pattern
-- already used for agent_payouts elsewhere in the master schema.
DROP POLICY IF EXISTS vendor_payouts_admin_all ON public.vendor_payouts;
CREATE POLICY vendor_payouts_admin_all ON public.vendor_payouts
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- ----------------------------------------------------------------
-- 2. HONEST SOCIAL PROOF — real, anonymized, recent bookings
-- ----------------------------------------------------------------
-- Exposes the smallest possible slice of real data: a first name +
-- last-initial (never full name/email/phone), the service booked,
-- and a coarse "time ago" bucket computed in SQL so exact timestamps
-- (which could be used to narrow down a specific customer) never
-- leave the database. Only rows from the last 14 days, and only
-- confirmed+paid bookings, are eligible — no pending/fake rows.
CREATE OR REPLACE VIEW public.public_recent_activity AS
SELECT
  b.id,
  -- "Priya S." style — first name + last initial only
  TRIM(SPLIT_PART(b.customer_name, ' ', 1)) || CASE
    WHEN SPLIT_PART(b.customer_name, ' ', 2) <> ''
    THEN ' ' || LEFT(SPLIT_PART(b.customer_name, ' ', 2), 1) || '.'
    ELSE ''
  END AS display_name,
  b.service_name,
  b.service_type,
  CASE
    WHEN NOW() - b.created_at < INTERVAL '2 minutes'  THEN 'just now'
    WHEN NOW() - b.created_at < INTERVAL '1 hour'     THEN EXTRACT(MINUTE FROM NOW() - b.created_at)::INT || ' min ago'
    WHEN NOW() - b.created_at < INTERVAL '24 hours'    THEN EXTRACT(HOUR FROM NOW() - b.created_at)::INT || ' hr ago'
    ELSE EXTRACT(DAY FROM NOW() - b.created_at)::INT || ' days ago'
  END AS time_ago
FROM public.bookings b
WHERE b.status = 'confirmed'
  AND b.payment_status = 'paid'
  AND b.customer_name <> ''
  AND b.created_at > NOW() - INTERVAL '14 days'
ORDER BY b.created_at DESC
LIMIT 25;

-- Readable by anyone (anon key), since it's already scrubbed of PII.
GRANT SELECT ON public.public_recent_activity TO anon, authenticated;

-- ----------------------------------------------------------------
-- 3. AGENT TIER <-> COMMISSION CONSISTENCY FIX
-- ----------------------------------------------------------------
SELECT public._drop_all_functions('auto_upgrade_agent_tier');
CREATE OR REPLACE FUNCTION public.auto_upgrade_agent_tier()
RETURNS TRIGGER AS $$
BEGIN
  NEW.tier := CASE
    WHEN NEW.total_booking_value >= 2000000 THEN 'platinum'
    WHEN NEW.total_booking_value >= 500000  THEN 'gold'
    WHEN NEW.total_booking_value >= 100000  THEN 'silver'
    ELSE 'associate'
  END;
  -- Keep the paid commission rate in lockstep with the tier the
  -- database just assigned, instead of leaving commission_rate
  -- stuck at whatever it was set to at signup. If an admin has
  -- manually overridden a specific agent's rate (extra_data / notes
  -- documented), this trigger only runs on UPDATE so it will
  -- re-assert the standard tier rate on the next booking-value
  -- change — that's intentional: standard rates should come from
  -- tier, not linger from a stale manual edit.
  NEW.commission_rate := CASE NEW.tier
    WHEN 'platinum' THEN 12.00
    WHEN 'gold'      THEN 10.00
    WHEN 'silver'    THEN 7.00
    ELSE 5.00
  END;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auto_upgrade_tier ON public.agents;
CREATE TRIGGER trg_auto_upgrade_tier BEFORE UPDATE ON public.agents FOR EACH ROW EXECUTE FUNCTION public.auto_upgrade_agent_tier();

-- Backfill existing agents once, so anyone already above a threshold
-- gets their correct tier + rate immediately rather than waiting for
-- their next booking to trigger the update.
UPDATE public.agents SET updated_at = NOW() WHERE TRUE;

-- ----------------------------------------------------------------
-- 4. REVIEWS: force new reviews into a pending state server-side
-- ----------------------------------------------------------------
-- reviews.is_published defaults to TRUE, and the INSERT policy
-- (reviews_create_own) only checks `user_id = auth.uid()` — it never
-- restricts which other columns a user can set. package-detail.html's
-- submit form does send `is_published: false` intending "pending
-- admin approval", but nothing stops a user from bypassing that page
-- entirely and inserting a review with `is_published: true` directly
-- (e.g. from the browser console), publishing arbitrary text on a
-- public package page instantly, with no moderation step at all —
-- and there is currently no admin UI anywhere in this project to
-- review, approve, or unpublish a review after the fact. This trigger
-- closes that off the same way profiles.role was closed earlier: pin
-- the sensitive columns server-side on INSERT regardless of what the
-- client sends, unless the caller is admin/service_role.
--
-- NOTE: this makes every new review start unpublished, which is the
-- safe default — but since there's no moderation UI yet, reviews
-- will accumulate invisibly until one exists (or until an admin flips
-- is_published directly in the Supabase dashboard). Building that
-- moderation UI is the natural next step, not included here.
CREATE OR REPLACE FUNCTION public.pin_review_moderation_columns()
RETURNS TRIGGER AS $$
BEGIN
  IF auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    NEW.is_published := FALSE;
    NEW.is_verified   := FALSE;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_pin_review_moderation ON public.reviews;
CREATE TRIGGER trg_pin_review_moderation BEFORE INSERT ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION public.pin_review_moderation_columns();

-- ----------------------------------------------------------------
-- 5. REFERRAL BONUS: close an unlimited free-points exploit
-- ----------------------------------------------------------------
-- award_referral_bonus() had no check for whether a user had already
-- been credited for a referral before handing out +500/+250 points.
-- Since points redeem for real discounts (redeem_loyalty_points:
-- ₹0.25/point) and this RPC is granted to `authenticated` (callable
-- directly via the Supabase client SDK, independent of whether any
-- page's UI currently calls it — a repo-wide search found no current
-- caller, so this is presently reachable only by someone calling the
-- RPC directly, not through normal browsing), anyone could call it
-- in a loop with their own account and mint unlimited points for
-- themselves and an accomplice referrer account. Fixed by using the
-- existing `referred_by` column as a one-time marker: once a user
-- has been credited for a referral, calling this again for the same
-- user is a no-op.
SELECT public._drop_all_functions('award_referral_bonus');
CREATE OR REPLACE FUNCTION public.award_referral_bonus(p_referrer_code TEXT, p_new_user_id UUID)
RETURNS VOID AS $$
DECLARE referrer public.loyalty_accounts; already_credited BOOLEAN;
BEGIN
  IF p_new_user_id <> auth.uid() AND auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Cannot claim a referral bonus for another user''s account';
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.loyalty_accounts WHERE user_id = p_new_user_id AND referred_by IS NOT NULL
  ) INTO already_credited;
  IF already_credited THEN RETURN; END IF; -- one referral credit per user, ever

  SELECT * INTO referrer FROM public.loyalty_accounts WHERE referral_code=p_referrer_code;
  IF NOT FOUND THEN RETURN; END IF;
  IF referrer.user_id = p_new_user_id THEN RETURN; END IF; -- can't refer yourself

  INSERT INTO public.loyalty_accounts (user_id) VALUES (p_new_user_id) ON CONFLICT (user_id) DO NOTHING;

  UPDATE public.loyalty_accounts SET points_balance=points_balance+500, points_earned=points_earned+500, referral_count=referral_count+1 WHERE id=referrer.id;
  INSERT INTO public.loyalty_transactions (account_id, user_id, txn_type, points, balance_after, description, expires_at)
  SELECT id, referrer.user_id, 'earn_referral', 500, points_balance, 'Referral bonus - friend joined ZoomFly!', NOW()+INTERVAL '1 year'
  FROM public.loyalty_accounts WHERE id=referrer.id;
  UPDATE public.loyalty_accounts SET points_balance=points_balance+250, points_earned=points_earned+250, referred_by=referrer.id WHERE user_id=p_new_user_id;
END; $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ----------------------------------------------------------------
-- 7. THE ACTUAL 403 BUG: bookings_select / enquiries_select query auth.users
-- ----------------------------------------------------------------
-- Confirmed via a live information_schema.role_table_grants check:
-- `authenticated` already has full SELECT/INSERT/UPDATE/DELETE on
-- both bookings and enquiries — so the 403s seen in the admin
-- dashboard were never a missing-grant problem. The real cause: both
-- policies queried `(SELECT email FROM auth.users WHERE id =
-- auth.uid())` directly inside their USING clause. Supabase does not
-- grant `authenticated` SELECT on auth.users by default (it's
-- intentionally locked down), so evaluating this policy raises a
-- genuine "permission denied for table users" error on every single
-- query against these two tables, for every user — which PostgREST
-- reports as 403 Forbidden. This is different from RLS simply
-- filtering rows out (which returns 200 with an empty/partial
-- result) — the policy couldn't even finish evaluating.
--
-- Fixed with Supabase's documented pattern for exactly this
-- situation: auth.jwt() ->> 'email' reads the email straight out of
-- the current session's JWT claims, with no table access (and so no
-- extra grant) required at all.
DROP POLICY IF EXISTS "bookings_select" ON public.bookings;
CREATE POLICY "bookings_select" ON public.bookings FOR SELECT USING (
  user_id = auth.uid()
  OR guest_email    = (auth.jwt() ->> 'email')
  OR customer_email = (auth.jwt() ->> 'email')
  OR public.is_admin()
);

DROP POLICY IF EXISTS "enquiries_select" ON public.enquiries;
CREATE POLICY "enquiries_select" ON public.enquiries FOR SELECT USING (
  email          = (auth.jwt() ->> 'email')
  OR guest_email = (auth.jwt() ->> 'email')
  OR public.is_admin()
);

-- ----------------------------------------------------------------
-- 6. BOOKINGS: the real root cause behind #10/#11 — direct self-confirmation
-- ----------------------------------------------------------------
-- This is more fundamental than the payment-replay and price-mismatch
-- fixes above. "bookings_update_own_or_admin" in the master schema has
-- a USING clause (row ownership) but NO WITH CHECK clause. Per
-- Postgres RLS semantics, when an UPDATE policy has no WITH CHECK,
-- the USING expression is reused as the check on the resulting row —
-- meaning this policy only ever verifies `user_id = auth.uid()` on
-- the new row. It does not, and never did, restrict which COLUMNS a
-- user can change on their own booking. Concretely: any logged-in
-- user could call
--   supabase.from('bookings').update({status:'confirmed',
--     payment_status:'paid'}).eq('id', theirOwnBookingId)
-- directly, right now, and get any booking marked paid+confirmed for
-- free — without ever creating a Razorpay order, without a webhook
-- firing, without verify-razorpay-payment ever running. Every fix in
-- sections 7/10/11 above is still correct and still needed (they
-- close the payment-gateway side), but none of them matter if the
-- gateway can simply be skipped via a raw UPDATE. This is the same
-- shape of bug as the original profiles-role self-escalation issue,
-- on the one table where it matters most.
--
-- Fixed with a trigger, not a WITH CHECK clause, because a single
-- static WITH CHECK can't express "allow this one column to change to
-- exactly one value (cancelled) but pin everything else" — a
-- customer legitimately needs to be able to cancel their own booking
-- (see cancelBooking() in assets/js/supabase.js), so status can't
-- simply be pinned outright the way payment fields can.
CREATE OR REPLACE FUNCTION public.protect_booking_privileged_columns()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    -- Payment/confirmation state: never settable by the customer
    -- directly. Only a real Razorpay verification (service_role) or
    -- an admin override can change these.
    NEW.payment_status     := OLD.payment_status;
    NEW.paid_at            := OLD.paid_at;
    NEW.paid_amount        := OLD.paid_amount;
    NEW.razorpay_payment_id:= OLD.razorpay_payment_id;
    NEW.razorpay_signature := OLD.razorpay_signature;
    NEW.confirmed_at       := OLD.confirmed_at;
    NEW.completed_at       := OLD.completed_at;
    NEW.refund_status      := OLD.refund_status;
    NEW.refund_amount      := OLD.refund_amount;
    NEW.refund_initiated_at:= OLD.refund_initiated_at;
    -- Pricing: must never change after creation via a raw update —
    -- any legitimate repricing (promo, admin discount) should go
    -- through a proper flow, not a client-side UPDATE on the booking
    -- the price checks in section 7/10 above depend on being stable.
    NEW.base_amount     := OLD.base_amount;
    NEW.tax_amount       := OLD.tax_amount;
    NEW.discount_amount  := OLD.discount_amount;
    NEW.total_amount     := OLD.total_amount;
    NEW.service_id       := OLD.service_id;
    NEW.package_id       := OLD.package_id;
    NEW.hotel_id         := OLD.hotel_id;
    NEW.service_type     := OLD.service_type;
    -- status: allow the existing self-cancel feature (customers can
    -- legitimately cancel their own booking), but never allow a
    -- customer to move status to confirmed/processing/completed
    -- themselves — only ever to 'cancelled'.
    IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status <> 'cancelled' THEN
      NEW.status := OLD.status;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_protect_booking_privileged_columns ON public.bookings;
CREATE TRIGGER trg_protect_booking_privileged_columns
  BEFORE UPDATE ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.protect_booking_privileged_columns();
