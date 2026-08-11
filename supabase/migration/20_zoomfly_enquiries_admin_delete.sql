-- ================================================================
-- ZoomFly — 20_zoomfly_enquiries_admin_delete.sql
-- Idempotent — safe to re-run.
--
-- WHAT THIS FIXES:
-- The admin panel's Enquiries, Flight Enquiries, and Train Enquiries
-- tabs need a "Delete" action (to clear spam/duplicate/test leads),
-- but public.enquiries only ever had SELECT/UPDATE policies for
-- admins — no DELETE — so any delete button added client-side would
-- silently fail RLS with "permission denied" or return 0 rows deleted.
--
-- public.train_enquiries already has a "FOR ALL" admin policy
-- (train_enq_admin_all) covering DELETE, so no DB change is needed
-- there — only the UI button.
--
-- This adds the missing admin DELETE policy on public.enquiries,
-- which also backs the Flight Enquiries tab (flight leads are rows
-- in this same table filtered by interest @> ['flight']).
-- ================================================================

DROP POLICY IF EXISTS "enquiries_admin_delete" ON public.enquiries;
CREATE POLICY "enquiries_admin_delete" ON public.enquiries
  FOR DELETE USING (public.is_admin());
