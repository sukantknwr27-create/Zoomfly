-- ============================================================
-- ZoomFly — 10_zoomfly_round6_fixes.sql
-- Safe to run multiple times (everything is IF NOT EXISTS / upsert).
-- Companion to CHANGES_ROUND6.md.
-- ============================================================

-- ----------------------------------------------------------------
-- 1. reminder_log — re-affirmed here in case 07_zoomfly_round4_admin_
--    root_cause_fix.sql was never actually run against this database
--    (e.g. if the DB was wiped and only 00_zoomfly_master_schema.sql
--    was re-applied). Its absence is what caused the "400 Bad Request"
--    errors on Admin → Reminders — the Reminders tab tries to read/
--    write this table on load and had nowhere to write to.
--    IF NOT EXISTS makes this a no-op if 07 already created it.
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.reminder_log (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id    UUID REFERENCES public.bookings(id) ON DELETE CASCADE,
  reminder_type TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'sent',
  sent_by       UUID REFERENCES auth.users(id),
  sent_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.reminder_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "reminder_log_admin_all" ON public.reminder_log;
CREATE POLICY "reminder_log_admin_all" ON public.reminder_log FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.reminder_log TO authenticated;

-- ----------------------------------------------------------------
-- 2. site_settings columns — re-affirmed here in case
--    03_zoomfly_site_settings_fix.sql was never run for the same
--    reason as above. If it was already run, every ADD COLUMN IF NOT
--    EXISTS below is a no-op.
-- ----------------------------------------------------------------
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS company_name       TEXT DEFAULT 'ZoomFly Travel Services';
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS support_phone      TEXT DEFAULT '+91 80761 36300';
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS support_email      TEXT DEFAULT 'hello@zoomfly.in';
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS homepage_hero_title    TEXT;
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS homepage_hero_subtitle TEXT;
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS meta_title         TEXT;
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS meta_description   TEXT;
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS social_instagram   TEXT;
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS social_facebook    TEXT;
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS social_twitter     TEXT;
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS social_youtube     TEXT;

-- ----------------------------------------------------------------
-- 3. commission_rates — new table. Admin → Vendors → Commission
--    Structure now writes here; pages/vendor.html's public
--    "Transparent Commission Structure" table and the 4 teaser badges
--    above it now read from here instead of hardcoded HTML, so
--    changing a rate in admin actually changes what partners see.
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.commission_rates (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  partner_type     TEXT NOT NULL,           -- display label, e.g. "🏨 Hotels & Resorts"
  commission_min   NUMERIC(5,2) NOT NULL DEFAULT 10,
  commission_max   NUMERIC(5,2) NOT NULL DEFAULT 15,
  payout_frequency TEXT DEFAULT 'Weekly',
  payout_method    TEXT DEFAULT 'NEFT / UPI',
  min_payout       NUMERIC(10,2) DEFAULT 500,
  sort_order       INTEGER DEFAULT 0,
  updated_at       TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.commission_rates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "commission_rates_public_read" ON public.commission_rates;
DROP POLICY IF EXISTS "commission_rates_admin_write" ON public.commission_rates;
CREATE POLICY "commission_rates_public_read" ON public.commission_rates FOR SELECT USING (TRUE);
CREATE POLICY "commission_rates_admin_write" ON public.commission_rates FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT ON public.commission_rates TO anon, authenticated;
GRANT ALL ON public.commission_rates TO service_role, authenticated;

INSERT INTO public.commission_rates (partner_type, commission_min, commission_max, payout_frequency, payout_method, min_payout, sort_order)
SELECT * FROM (VALUES
  ('🏨 Hotels & Resorts', 12, 15, 'Weekly', 'NEFT / UPI', 1000, 1),
  ('🚌 Bus Operators',     8, 10, 'Weekly', 'NEFT / UPI',  500, 2),
  ('🗺 Tour Operators',   15, 20, 'Weekly', 'NEFT / UPI', 1500, 3),
  ('🚗 Cab & Transfers',  10, 12, 'Weekly', 'NEFT / UPI',  500, 4)
) AS seed(partner_type, commission_min, commission_max, payout_frequency, payout_method, min_payout, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM public.commission_rates);

-- ----------------------------------------------------------------
-- 4. agents table — added `experience` column used by the manual
--    "Add Agent" admin form and agent-portal.html's self-registration,
--    in case an older version of the agents table predates it.
-- ----------------------------------------------------------------
ALTER TABLE public.agents ADD COLUMN IF NOT EXISTS experience TEXT;
