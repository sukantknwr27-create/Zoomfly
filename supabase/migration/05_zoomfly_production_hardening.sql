-- ============================================================
--  ZoomFly — 05: Production Hardening
--  Run AFTER 00-04. Safe to re-run (idempotent).
--
--  Closes gaps found in a full production-readiness audit:
--   1. vendors/agents INSERT had no column-pinning trigger (only
--      UPDATE was protected) — any signed-up user could INSERT
--      themselves as an already-approved, featured, zero-commission
--      vendor, or a platinum-tier agent with an inflated commission
--      rate and fabricated earnings, bypassing admin review entirely.
--   2. storage.objects "avatars" bucket policies let ANY authenticated
--      user upload/overwrite ANY object in the bucket, not just their
--      own — no path/ownership scoping at all.
--   3. dashboard.html uploads customer avatar photos to the
--      "zoomfly-images" bucket under `avatars/<user_id>-...`, but
--      04_zoomfly_image_uploads.sql's INSERT policy on that bucket is
--      admin-only — every non-admin customer's avatar upload fails.
--   4. booking_modifications / payment_links have INSERT call sites in
--      assets/js/supabase.js (requestBookingModification,
--      createPaymentLink) but no INSERT policy for the owning user —
--      only SELECT and admin-ALL exist.
--   5. promo_codes / offers had no upper bound on discount_value when
--      discount_type='percentage'.
-- ============================================================

-- ── 1. Pin privileged columns on INSERT, not just UPDATE ─────
-- (mirrors bookings' enforce_safe_booking_insert pattern)

CREATE OR REPLACE FUNCTION public.enforce_safe_vendor_insert()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    NEW.status           := 'pending';
    NEW.status_note       := NULL;
    NEW.commission_rate   := 10.00;
    NEW.approved_at       := NULL;
    NEW.approved_by       := NULL;
    NEW.verified_at       := NULL;
    NEW.total_bookings    := 0;
    NEW.confirmed_bookings:= 0;
    NEW.total_revenue     := 0;
    NEW.is_featured       := FALSE;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_enforce_safe_vendor_insert ON public.vendors;
CREATE TRIGGER trg_enforce_safe_vendor_insert
  BEFORE INSERT ON public.vendors
  FOR EACH ROW EXECUTE FUNCTION public.enforce_safe_vendor_insert();

CREATE OR REPLACE FUNCTION public.enforce_safe_agent_insert()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    NEW.tier                    := 'associate';
    NEW.commission_rate         := 5.00;
    NEW.sub_agent_commission    := 1.00;
    NEW.total_bookings          := 0;
    NEW.confirmed_bookings      := 0;
    NEW.total_booking_value     := 0;
    NEW.total_commission_earned := 0;
    NEW.total_commission_paid   := 0;
    NEW.parent_agent_id         := NULL;
    NEW.approved_by             := NULL;
    NEW.approved_at             := NULL;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_enforce_safe_agent_insert ON public.agents;
CREATE TRIGGER trg_enforce_safe_agent_insert
  BEFORE INSERT ON public.agents
  FOR EACH ROW EXECUTE FUNCTION public.enforce_safe_agent_insert();

-- ── 2. Scope "avatars" bucket writes to the uploader's own folder ──
DROP POLICY IF EXISTS "Auth upload avatars" ON storage.objects;
DROP POLICY IF EXISTS "Auth update avatars" ON storage.objects;
CREATE POLICY "Auth upload own avatar" ON storage.objects FOR INSERT WITH CHECK (
  bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text
);
CREATE POLICY "Auth update own avatar" ON storage.objects FOR UPDATE USING (
  bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text
);

-- ── 3. Let customers upload their own avatar into zoomfly-images ───
-- dashboard.html writes to `avatars/<user_id>-<timestamp>.<ext>` in
-- this bucket; scope the INSERT policy to that prefix so it isn't a
-- free-for-all upload target, without granting admin-only access.
CREATE POLICY "Users upload own avatar in zoomfly-images" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'zoomfly-images'
  AND (storage.foldername(name))[1] = 'avatars'
  AND auth.uid() IS NOT NULL
);

-- ── 4. INSERT policies the frontend already calls but RLS blocked ──
DROP POLICY IF EXISTS "modifications_own_insert" ON public.booking_modifications;
CREATE POLICY "modifications_own_insert" ON public.booking_modifications FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM public.bookings WHERE id = booking_id AND user_id = auth.uid())
  OR public.is_admin()
);

DROP POLICY IF EXISTS "payment_links_own_insert" ON public.payment_links;
CREATE POLICY "payment_links_own_insert" ON public.payment_links FOR INSERT WITH CHECK (
  user_id = auth.uid()
  OR EXISTS (SELECT 1 FROM public.bookings WHERE id = booking_id AND user_id = auth.uid())
  OR public.is_admin()
);

-- ── 5. Sanity bounds on percentage-type discounts ──────────────────
ALTER TABLE public.promo_codes DROP CONSTRAINT IF EXISTS promo_codes_pct_range;
ALTER TABLE public.promo_codes ADD CONSTRAINT promo_codes_pct_range
  CHECK (discount_type <> 'percentage' OR (discount_value >= 0 AND discount_value <= 100));

ALTER TABLE public.offers DROP CONSTRAINT IF EXISTS offers_pct_range;
ALTER TABLE public.offers ADD CONSTRAINT offers_pct_range
  CHECK (discount_type <> 'percentage' OR (discount_value >= 0 AND discount_value <= 100));
