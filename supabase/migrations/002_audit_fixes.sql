-- ============================================================
-- ZoomFly — AUDIT FIX MIGRATION (July 2026)
-- Run this whole file once in Supabase → SQL Editor → New Query.
-- It is safe to re-run (uses IF NOT EXISTS / DROP-then-CREATE).
--
-- Fixes, in order:
--   1. vendors.status CHECK constraint didn't allow 'active',
--      so every "Activate" click in the admin panel failed with
--      a 400 error (constraint violation).
--   2. bookings.booking_type CHECK constraint didn't allow 'cab',
--      and the agent-portal booking form never sent booking_type
--      at all (see code fix), causing a "null value in column
--      booking_type" error on every agent booking.
--   3. destinations, bus_routes, cab_services and page_contents
--      tables were referenced everywhere in admin.html but were
--      never created by ANY migration — every add/edit there was
--      silently failing (the UI reported success because the code
--      never checked the returned error).
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. VENDORS — allow 'active' status (admin "Activate" button)
-- ────────────────────────────────────────────────────────────
ALTER TABLE public.vendors DROP CONSTRAINT IF EXISTS vendors_status_check;
ALTER TABLE public.vendors
  ADD CONSTRAINT vendors_status_check
  CHECK (status IN ('pending','approved','active','rejected','suspended'));

-- ────────────────────────────────────────────────────────────
-- 2. BOOKINGS — allow 'cab' as a booking_type (agent portal offers it)
-- ────────────────────────────────────────────────────────────
ALTER TABLE public.bookings DROP CONSTRAINT IF EXISTS bookings_booking_type_check;
ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_booking_type_check
  CHECK (booking_type IN ('package','hotel','flight','bus','cab'));

-- ────────────────────────────────────────────────────────────
-- 3. DESTINATIONS (used by admin.html "Destinations" tab)
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.destinations (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name         TEXT NOT NULL,
  country      TEXT DEFAULT 'India',
  emoji        TEXT DEFAULT '🏖️',
  image_url    TEXT,
  bg_gradient  TEXT,
  is_active    BOOLEAN NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_destinations_active ON public.destinations(is_active);

ALTER TABLE public.destinations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "destinations_public_read"  ON public.destinations;
DROP POLICY IF EXISTS "destinations_admin_write"  ON public.destinations;
CREATE POLICY "destinations_public_read" ON public.destinations
  FOR SELECT USING (is_active = TRUE);
CREATE POLICY "destinations_admin_write" ON public.destinations
  FOR ALL USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));
GRANT SELECT ON public.destinations TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.destinations TO authenticated;

-- ────────────────────────────────────────────────────────────
-- 4. BUS ROUTES (used by admin.html "Buses" tab + pages/bus.html)
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.bus_routes (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  from_city       TEXT NOT NULL,
  to_city         TEXT NOT NULL,
  operator        TEXT DEFAULT 'Private',
  bus_type        TEXT DEFAULT 'AC Sleeper',
  price           NUMERIC(10,2) NOT NULL DEFAULT 0,
  departure_time  TEXT,
  duration        TEXT,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_bus_routes_active ON public.bus_routes(is_active);
CREATE INDEX IF NOT EXISTS idx_bus_routes_cities  ON public.bus_routes(from_city, to_city);

ALTER TABLE public.bus_routes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "bus_routes_public_read" ON public.bus_routes;
DROP POLICY IF EXISTS "bus_routes_admin_write" ON public.bus_routes;
CREATE POLICY "bus_routes_public_read" ON public.bus_routes
  FOR SELECT USING (is_active = TRUE);
CREATE POLICY "bus_routes_admin_write" ON public.bus_routes
  FOR ALL USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));
GRANT SELECT ON public.bus_routes TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.bus_routes TO authenticated;

-- ────────────────────────────────────────────────────────────
-- 5. CAB SERVICES (used by admin.html "Cabs" tab + pages/cabs.html)
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.cab_services (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  from_location   TEXT NOT NULL,
  to_location     TEXT NOT NULL,
  cab_type        TEXT DEFAULT 'Sedan',
  price           NUMERIC(10,2) NOT NULL DEFAULT 0,
  duration_hours  NUMERIC(5,2),
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_cab_services_active ON public.cab_services(is_active);

ALTER TABLE public.cab_services ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "cab_services_public_read" ON public.cab_services;
DROP POLICY IF EXISTS "cab_services_admin_write" ON public.cab_services;
CREATE POLICY "cab_services_public_read" ON public.cab_services
  FOR SELECT USING (is_active = TRUE);
CREATE POLICY "cab_services_admin_write" ON public.cab_services
  FOR ALL USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));
GRANT SELECT ON public.cab_services TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.cab_services TO authenticated;

-- ────────────────────────────────────────────────────────────
-- 6. PAGE CONTENTS (used by admin.html "Page Content" editor)
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.page_contents (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  page_slug   TEXT UNIQUE NOT NULL,
  content     TEXT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.page_contents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "page_contents_public_read" ON public.page_contents;
DROP POLICY IF EXISTS "page_contents_admin_write" ON public.page_contents;
CREATE POLICY "page_contents_public_read" ON public.page_contents
  FOR SELECT USING (TRUE);
CREATE POLICY "page_contents_admin_write" ON public.page_contents
  FOR ALL USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));
GRANT SELECT ON public.page_contents TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.page_contents TO authenticated;

-- ────────────────────────────────────────────────────────────
-- 7. Make sure the auto-updated_at trigger fn exists for the
--    tables above (001_schema.sql defines update_updated_at()).
-- ────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'update_updated_at') THEN
    DROP TRIGGER IF EXISTS trg_destinations_updated ON public.destinations;
    CREATE TRIGGER trg_destinations_updated BEFORE UPDATE ON public.destinations FOR EACH ROW EXECUTE FUNCTION update_updated_at();
    DROP TRIGGER IF EXISTS trg_bus_routes_updated ON public.bus_routes;
    CREATE TRIGGER trg_bus_routes_updated BEFORE UPDATE ON public.bus_routes FOR EACH ROW EXECUTE FUNCTION update_updated_at();
    DROP TRIGGER IF EXISTS trg_cab_services_updated ON public.cab_services;
    CREATE TRIGGER trg_cab_services_updated BEFORE UPDATE ON public.cab_services FOR EACH ROW EXECUTE FUNCTION update_updated_at();
  END IF;
END $$;

-- DONE. After running this, re-deploy the updated frontend code
-- (agent-portal.html, vendor-portal.html, admin.html) that
-- accompanies this migration — the schema fix alone does not fix
-- the "silent success toast on failed write" bugs in the JS.
