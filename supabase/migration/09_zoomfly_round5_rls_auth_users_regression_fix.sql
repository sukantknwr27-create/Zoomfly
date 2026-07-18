-- ================================================================
-- 09 — ROUND 5: RE-FIX "permission denied for table users"
-- ================================================================
-- SYMPTOM (reported live, July 2026): Admin panel Enquiries, Bookings,
-- Workflow, Messages, and Flight Enquiries tabs all failed to load,
-- with Messages/Flight Enquiries surfacing the raw Postgres error
-- "permission denied for table users".
--
-- ROOT CAUSE: bookings_select and enquiries_select query
-- `(SELECT email FROM auth.users WHERE id = auth.uid())` directly in
-- their USING clause. The `authenticated` role has no SELECT grant on
-- auth.users (Supabase locks this down intentionally), so evaluating
-- these policies throws "permission denied for table users" on every
-- query against bookings/enquiries, for every user, admin included.
-- This then cascades: Workflow reuses the bookings query, and
-- Messages' own policy does `EXISTS (... FROM public.bookings ...)`,
-- which re-triggers bookings' own (broken) SELECT policy — so
-- Messages fails with the exact same underlying error even though its
-- own policy never touches auth.users directly.
--
-- This exact fix already exists in 01_zoomfly_growth_features.sql
-- (section 7) — but 00_zoomfly_master_schema.sql (the "run fresh on a
-- wiped database" file) still had the old, broken version. If the
-- master schema is ever re-run by itself without 01-08 layered back
-- on top afterward, this bug silently comes back. 00 has now been
-- corrected too (so a future fresh install can't reintroduce this),
-- but run this file now to fix the *current* live database
-- immediately without needing to wipe and redo everything.
--
-- Safe to run multiple times.
-- ================================================================

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

-- Sanity check — should return zero rows. If this ever returns any
-- policy, that policy will throw "permission denied for table users"
-- for any non-admin session and needs the same auth.jwt() treatment.
-- (Run manually to verify; not part of the migration itself.)
-- SELECT schemaname, tablename, policyname, qual
-- FROM pg_policies
-- WHERE qual ILIKE '%FROM auth.users%' AND schemaname = 'public';
