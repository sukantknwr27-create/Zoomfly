-- ================================================================
-- ZoomFly — 17_zoomfly_api_providers.sql
-- Run AFTER 00–16, against STAGING first.
--
-- What this file does:
--   Introduces a single, pluggable `api_providers` table that lets an
--   admin activate, deactivate, or add a supplier API (TBO, Tripjack,
--   Riya, railYatri, etc.) for any service — flight, rail, hotel, bus,
--   cab — entirely from the admin panel, with no code deploy.
--
--   Before this: the flight pipeline (see 16_zoomfly_flight_booking.sql)
--   already had a clean provider-agnostic interface
--   (_shared/flight-provider.ts), but which provider was live was
--   decided by a Deno environment variable (FLIGHT_PROVIDER) that only
--   changes on redeploy. That's fine for one hardcoded provider, but
--   doesn't match how this business actually operates: providers get
--   evaluated, swapped, or run in parallel (primary + fallback) as
--   better consolidator deals come in — this table is what makes that
--   an admin-panel action instead of a code change.
--
--   Credentials are stored server-side only. RLS restricts all access
--   to admins (via the existing is_admin() helper) plus the
--   service-role key that every edge function already uses — the same
--   trust boundary this project uses everywhere else (see
--   flight_ticketing_queue's admin-only SELECT policy for comparison).
--   Nothing here is ever exposed to anon or ordinary authenticated
--   users, and the browser (flights.html / trains.html) never reads
--   this table directly — only edge functions and admin.html do.
-- ================================================================

-- ── 1. API PROVIDERS ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.api_providers (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  service_type     TEXT NOT NULL
                      CHECK (service_type IN ('flight','rail','hotel','bus','cab')),
  provider_key     TEXT NOT NULL,       -- e.g. 'mock','tbo','tripjack','riya','railyatri','custom'
  display_name     TEXT NOT NULL,       -- shown in admin UI, e.g. "TBO (Live)"
  credentials      JSONB NOT NULL DEFAULT '{}',  -- {username, password, api_key, base_url, ...} — shape depends on provider_key. Service-role / admin-only, never sent to the browser.
  config           JSONB NOT NULL DEFAULT '{}',  -- non-secret settings: {environment: 'sandbox'|'live', markup_percent, timeout_ms}
  is_active        BOOLEAN NOT NULL DEFAULT false,
  priority         INTEGER NOT NULL DEFAULT 100, -- lower = tried first when more than one provider is active for the same service_type (primary/fallback chain)
  last_tested_at   TIMESTAMPTZ,
  last_test_status TEXT CHECK (last_test_status IN ('success','failed')),
  last_test_message TEXT,
  notes            TEXT,                -- free-text admin notes, e.g. "onboarding started 2026-08", commission terms, contact email
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (service_type, provider_key)   -- one config row per provider per service — toggle is_active / edit credentials rather than duplicate rows
);

CREATE INDEX IF NOT EXISTS idx_api_providers_active_lookup
  ON public.api_providers(service_type, is_active, priority)
  WHERE is_active = true;

-- ── 2. UPDATED_AT TRIGGER (matches existing pattern, e.g. flight_ticketing_queue) ──
CREATE OR REPLACE FUNCTION public.touch_api_providers()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_touch_api_providers ON public.api_providers;
CREATE TRIGGER trg_touch_api_providers
  BEFORE UPDATE ON public.api_providers
  FOR EACH ROW EXECUTE FUNCTION public.touch_api_providers();

-- ── 3. ROW LEVEL SECURITY ───────────────────────────────────────
ALTER TABLE public.api_providers ENABLE ROW LEVEL SECURITY;

SELECT public._drop_all_policies('api_providers');
CREATE POLICY "api_providers_admin_all" ON public.api_providers FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
-- No anon/authenticated policy is created — non-admins get zero rows,
-- and the browser never queries this table directly anyway (only
-- admin.html, running as an authenticated admin, and edge functions,
-- running as service_role which bypasses RLS entirely).

-- ── 4. SEED: mock provider active by default for every service ──
-- Keeps the app working exactly as before immediately after this
-- migration runs — flights/rail keep using their existing Mock
-- providers until an admin explicitly activates a real one. Seeded
-- as inactive placeholders for services with a mock provider isn't
-- built for rail/flight only; hotel/bus/cab remain on their existing
-- catalog-table logic and don't need a row here yet.
INSERT INTO public.api_providers (service_type, provider_key, display_name, credentials, config, is_active, priority, notes)
VALUES
  ('flight', 'mock', 'Mock Provider (placeholder data)', '{}', '{}', true, 100,
   'Built-in. Returns clearly-labelled fake fares (isMock:true) so the booking pipeline works end-to-end before a real consolidator is signed. Deactivate once a real flight provider below is verified.'),
  ('rail', 'mock', 'Mock Provider (placeholder data)', '{}', '{}', true, 100,
   'Built-in. Indicative-only availability/fares, clearly labelled. Actual ticketing is always manual via the Rail Ticketing Queue regardless of which search provider is active — IRCTC has no open consolidator API.')
ON CONFLICT (service_type, provider_key) DO NOTHING;

-- Known real-provider rows, seeded INACTIVE with empty credentials so
-- they show up in the admin panel ready to fill in — an admin never
-- has to remember the exact provider_key string to type; they just
-- edit one of these rows (or add a new one via "+ Add Provider" for
-- anything not listed here) and flip is_active on once credentials
-- are entered and "Test Connection" succeeds.
INSERT INTO public.api_providers (service_type, provider_key, display_name, credentials, config, is_active, priority, notes)
VALUES
  ('flight', 'tbo',       'TBO Tek',              '{}', '{}', false, 100, 'Contact: Railways@tbo.com / 0124-4998999. Also offers rail — see the "rail" row below.'),
  ('flight', 'tripjack',  'Tripjack',             '{}', '{}', false, 100, 'Contact: madhusudhan.p@tripjack.com. Also offers rail via "Tripjack Rail" — see the "rail" row below.'),
  ('flight', 'riya',      'Riya Travel (RLTC)',   '{}', '{}', false, 100, 'Contact: Rail.ggn@riya.travel / 011-41525188.'),
  ('rail',   'tbo',       'TBO Tek (Rail)',       '{}', '{}', false, 100, 'IRCTC B2B provider. Contact: Railways@tbo.com.'),
  ('rail',   'tripjack',  'Tripjack Rail',        '{}', '{}', false, 100, 'Dedicated rail product — "Tripjack Rail". Confirm API (not just agent-portal) access before activating.'),
  ('rail',   'railyatri', 'railYatri (Stelling)', '{}', '{}', false, 100, 'Contact: assistedbooking@railyatri.in. Rail-specialist; assisted-booking model matches our manual admin-ticketing design.')
ON CONFLICT (service_type, provider_key) DO NOTHING;
