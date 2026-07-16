-- ================================================================
-- ZoomFly — 07_zoomfly_round4_admin_root_cause_fix.sql
-- Run AFTER 00, 01, 02, 03, 04, 05, 06 (all idempotent — safe to
-- re-run any of them if you're not sure whether they've been applied).
--
-- WHAT THIS FIXES (this is the ROOT CAUSE behind almost every error
-- in the "17 issues" report — 403s on enquiries/bookings, "permission
-- denied for table users", FAQ/Careers edit-delete doing nothing,
-- promo codes refusing to save/disable, site settings RLS error, etc.):
--
-- Admin login (admin-login.html / assets/js/supabase.js) was
-- deliberately hardened in an earlier round to only trust
-- `user.app_metadata.role === 'admin'` (settable only via the
-- Supabase service_role/admin API — safe from client tampering),
-- falling back to `profiles.role === 'admin'` as a secondary check.
--
-- BUT the database-side public.is_admin() function — the one every
-- single RLS policy in the app calls — was never updated to match.
-- It ONLY checks profiles.role:
--
--     RETURN EXISTS (SELECT 1 FROM public.profiles
--                     WHERE id = auth.uid() AND role = 'admin');
--
-- So if your admin account's access was granted the secure way (via
-- Supabase Dashboard → Authentication → user → "Raw App Meta Data",
-- setting {"role":"admin"}) — which is exactly what the login page
-- expects and accepts — the admin panel logs you in successfully
-- (because the client-side check passes), but every table's RLS
-- policy then rejects you, because is_admin() only ever looks at
-- profiles.role, which was never touched. That mismatch is what
-- produces the "logged in but nothing works" pattern: reads that
-- depend solely on is_admin() come back empty/403, and every write
-- (FAQ, careers, promo codes, destinations, site_settings, etc.)
-- fails RLS with "new row violates row-level security policy" or
-- "permission denied".
--
-- FIX: make is_admin() accept EITHER signal, exactly mirroring the
-- app's own client-side logic. app_metadata is read straight from the
-- JWT (auth.jwt()), so this requires no extra table access/grants.
-- ================================================================

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
BEGIN
  -- 1. Trust app_metadata.role straight from the JWT — this is the
  --    path used when an admin account is provisioned the secure way
  --    (Supabase Dashboard / service_role), and it's what
  --    admin-login.html checks first.
  IF (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin' THEN
    RETURN TRUE;
  END IF;

  -- 2. Fall back to profiles.role — this path is safe again (unlike
  --    the original self-escalation bug) because profiles.role can
  --    no longer be set at signup or edited by the user themselves;
  --    only an admin/service_role can change it (see 00_master_schema).
  RETURN EXISTS (
    SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'
  );
END;
$$;

-- ----------------------------------------------------------------
-- PROMO CODES — real schema-drift bug, independent of the RLS issue
-- above. admin.html (add/edit/list) and the live checkout validator
-- (assets/js/supabase.js: validatePromoCode) both read/write columns
-- named min_order_amount, max_uses, times_used, expires_at — but
-- 00_master_schema.sql actually created min_order, usage_limit,
-- used_count, valid_until. Every promo code create/update from the
-- admin panel AND every promo code applied at checkout has been
-- failing (unknown column) or silently no-op'ing since day one; this
-- was never just an admin-panel bug. Renaming the real columns to
-- match every place in the codebase that already reads/writes them.
-- ----------------------------------------------------------------
ALTER TABLE public.promo_codes RENAME COLUMN min_order TO min_order_amount;
ALTER TABLE public.promo_codes RENAME COLUMN usage_limit TO max_uses;
ALTER TABLE public.promo_codes RENAME COLUMN used_count TO times_used;
ALTER TABLE public.promo_codes RENAME COLUMN valid_until TO expires_at;

-- expires_at was DATE (valid_until), the app writes/reads a full
-- timestamp-comparable value; widen it so `new Date(p.expires_at)`
-- and date-only <input type="date"> values both work correctly.
ALTER TABLE public.promo_codes ALTER COLUMN expires_at TYPE TIMESTAMPTZ USING expires_at::timestamptz;

-- ----------------------------------------------------------------
-- 3. REMINDERS — real, shared history instead of per-browser localStorage
-- ----------------------------------------------------------------
-- admin-reminders.html's "Run Reminder Engine" logic (buildQueue, due-
-- date detection) already queries real bookings — that part was never
-- fake. What WAS fake: sent-reminder history only ever lived in
-- localStorage on whichever single browser clicked "Send," so History
-- was empty for any other admin/device, and "already sent" checks
-- couldn't see reminders another admin had just sent. This table makes
-- that record real and shared. (Note: sending itself still opens a
-- WhatsApp chat window for a human to hit send — there's no WhatsApp
-- Business API integration in this codebase to dispatch automatically
-- without one; that would be a separate integration project requiring
-- WhatsApp Business API credentials.)
CREATE TABLE IF NOT EXISTS public.reminder_log (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id   UUID REFERENCES public.bookings(id) ON DELETE CASCADE,
  reminder_type TEXT NOT NULL,
  status       TEXT NOT NULL DEFAULT 'sent',
  sent_by      UUID REFERENCES auth.users(id),
  sent_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.reminder_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "reminder_log_admin_all" ON public.reminder_log;
CREATE POLICY "reminder_log_admin_all" ON public.reminder_log FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
-- ----------------------------------------------------------------
-- 4. VENDOR PAYOUTS — table never existed
-- ----------------------------------------------------------------
-- admin-vendors.html's Payouts tab (now merged into admin.html) reads
-- and writes a `vendor_payouts` table that was never created anywhere
-- in any migration — only `agent_payouts` existed. Every payout
-- create/update/delete would have failed with "relation vendor_payouts
-- does not exist". Adding it now, mirroring the agent_payouts shape.
CREATE TABLE IF NOT EXISTS public.vendor_payouts (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  vendor_id      UUID REFERENCES public.vendors(id) ON DELETE CASCADE,
  amount         NUMERIC(10,2) NOT NULL DEFAULT 0,
  commission     NUMERIC(10,2) NOT NULL DEFAULT 0,
  net_amount     NUMERIC(10,2) NOT NULL DEFAULT 0,
  booking_count  INT DEFAULT 1,
  period_start   DATE,
  period_end     DATE,
  payout_status  TEXT NOT NULL DEFAULT 'pending' CHECK (payout_status IN ('pending','processing','paid','failed','on_hold')),
  payout_date    DATE,
  utr_number     TEXT,
  notes          TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.vendor_payouts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "vendor_payouts_admin_all" ON public.vendor_payouts;
CREATE POLICY "vendor_payouts_admin_all" ON public.vendor_payouts FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "vendor_payouts_view_own" ON public.vendor_payouts;
CREATE POLICY "vendor_payouts_view_own" ON public.vendor_payouts FOR SELECT USING (
  vendor_id IN (SELECT id FROM public.vendors WHERE user_id = auth.uid()) OR public.is_admin()
);

-- ================================================================
-- DIAGNOSTIC — run this SEPARATELY (as yourself, logged into the
-- app, via the Supabase SQL Editor "Run as authenticated user" /or/
-- just check directly) to confirm your admin account is now
-- recognized. Replace the email below with your actual admin login
-- email, then run:
--
--   SELECT u.email, u.raw_app_meta_data->>'role' AS app_metadata_role,
--          p.role AS profile_role
--   FROM auth.users u
--   LEFT JOIN public.profiles p ON p.id = u.id
--   WHERE u.email = 'YOUR_ADMIN_EMAIL_HERE';
--
-- You want to see 'admin' in AT LEAST ONE of app_metadata_role or
-- profile_role. If BOTH are null/blank, that's a separate problem —
-- your account was never actually granted admin rights, and no RLS
-- fix can help; you'd need to run (once, as postgres/service role):
--
--   UPDATE public.profiles SET role = 'admin' WHERE id =
--     (SELECT id FROM auth.users WHERE email = 'YOUR_ADMIN_EMAIL_HERE');
-- ================================================================
