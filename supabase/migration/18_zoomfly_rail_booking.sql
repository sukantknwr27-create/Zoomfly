-- ================================================================
-- ZoomFly — 18_zoomfly_rail_booking.sql
-- Run AFTER 00–17, against STAGING first.
--
-- What this file does:
--   Replaces trains.html's entirely fake backend (hardcoded TRAIN_DB
--   schedule, Math.random() seat availability, a synthetic fare
--   multiplier, and a random PNR status generator) with a real
--   pipeline, mirroring the flight pipeline's honesty standard —
--   with one structural difference that's a hard constraint, not a
--   choice: IRCTC has no open consolidator API for direct programmatic
--   ticketing. Every B2B rail provider (Tripjack Rail, TBO Rail,
--   railYatri) ultimately books through an authorized-agent flow.
--   So unlike flights, rail ticketing (the actual PNR-issuing step)
--   is ALWAYS a manual, admin-actioned step — see rail_ticketing_queue
--   below and the "Rail Ticketing Queue" section in admin.html. Search
--   and fare display, however, run through the same pluggable
--   provider pattern as flights (see _shared/rail-provider.ts and
--   17_zoomfly_api_providers.sql).
--
--   1. rail_search_cache     — short-lived cache of search results,
--                               same purpose/shape as flight_search_cache.
--   2. rail_ticketing_queue  — the manual-ticketing work queue. A row
--                               is created once payment is confirmed
--                               (see razorpay-webhook / verify-razorpay-
--                               payment) and an admin works it: books
--                               the real IRCTC ticket through whichever
--                               agent channel is live, enters the real
--                               PNR, and marks it ticketed — which is
--                               what actually notifies the customer.
--                               An sla_due_at column exists so the
--                               admin panel can flag overdue rows.
--   3. bookings.rail_*       — mirrors bookings.flight_* from
--                               16_zoomfly_flight_booking.sql, so a
--                               train booking's PNR/provider/ticketing
--                               status is queryable directly.
-- ================================================================

-- ── 1. RAIL SEARCH CACHE ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.rail_search_cache (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  search_hash  TEXT NOT NULL,
  provider     TEXT NOT NULL DEFAULT 'mock',
  results      JSONB NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at   TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_rail_search_cache_hash
  ON public.rail_search_cache(search_hash) WHERE expires_at > NOW();
CREATE INDEX IF NOT EXISTS idx_rail_search_cache_expiry
  ON public.rail_search_cache(expires_at);

-- ── 2. RAIL TICKETING QUEUE ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.rail_ticketing_queue (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id    UUID NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  provider      TEXT NOT NULL DEFAULT 'mock',
  train_number  TEXT NOT NULL,
  train_name    TEXT,
  from_code     TEXT NOT NULL,
  to_code       TEXT NOT NULL,
  travel_date   DATE NOT NULL,
  class_code    TEXT NOT NULL,   -- SL, 3A, 2A, 1A, CC, EC, 2S
  quota         TEXT NOT NULL DEFAULT 'GN',
  passengers    JSONB NOT NULL DEFAULT '[]',
  fare          JSONB NOT NULL DEFAULT '{}',
  status        TEXT NOT NULL DEFAULT 'queued'
                   CHECK (status IN ('queued','in_progress','ticketed','failed','cancelled')),
  pnr           TEXT,
  admin_notes   TEXT,
  sla_due_at    TIMESTAMPTZ,
  assigned_to   UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ticketed_at   TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rail_ticketing_queue_status
  ON public.rail_ticketing_queue(status, sla_due_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_rail_ticketing_queue_booking
  ON public.rail_ticketing_queue(booking_id);

CREATE OR REPLACE FUNCTION public.touch_rail_ticketing_queue()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := NOW();
  IF NEW.status = 'ticketed' AND OLD.status <> 'ticketed' THEN
    NEW.ticketed_at := NOW();
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_touch_rail_ticketing_queue ON public.rail_ticketing_queue;
CREATE TRIGGER trg_touch_rail_ticketing_queue
  BEFORE UPDATE ON public.rail_ticketing_queue
  FOR EACH ROW EXECUTE FUNCTION public.touch_rail_ticketing_queue();

-- ── 3. BOOKINGS TABLE EXTENSIONS ─────────────────────────────────
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS rail_provider         TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS rail_pnr              TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS rail_ticketing_status TEXT; -- mirrors rail_ticketing_queue.status for quick admin filtering / My Bookings display

-- Keep bookings.rail_ticketing_status in sync with the queue so the
-- customer-facing my-bookings.html view doesn't need a second query.
CREATE OR REPLACE FUNCTION public.sync_rail_ticketing_status_to_booking()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.bookings
  SET rail_ticketing_status = NEW.status,
      rail_pnr = COALESCE(NEW.pnr, rail_pnr),
      rail_provider = NEW.provider,
      status = CASE WHEN NEW.status = 'ticketed' THEN 'confirmed' ELSE status END
  WHERE id = NEW.booking_id;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_rail_ticketing_status ON public.rail_ticketing_queue;
CREATE TRIGGER trg_sync_rail_ticketing_status
  AFTER INSERT OR UPDATE ON public.rail_ticketing_queue
  FOR EACH ROW EXECUTE FUNCTION public.sync_rail_ticketing_status_to_booking();

-- ── 4. HOUSEKEEPING ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cleanup_rail_ephemeral_data()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  DELETE FROM public.rail_search_cache WHERE expires_at < NOW() - INTERVAL '1 hour';
END;
$$;

-- ── 5. ROW LEVEL SECURITY ────────────────────────────────────────
ALTER TABLE public.rail_search_cache    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rail_ticketing_queue ENABLE ROW LEVEL SECURITY;

-- rail_search_cache: service-role only, same posture as flight_search_cache.
SELECT public._drop_all_policies('rail_search_cache');

-- rail_ticketing_queue: this is the one place in the rail pipeline
-- where an admin needs direct write access (entering a real PNR,
-- marking ticketed) rather than going through an edge function — the
-- same "admin writes directly, RLS-gated by is_admin()" pattern
-- already used throughout admin.html for content management. Reads
-- are also admin-only; it's an internal operational queue, not
-- customer-facing data (customers see rail_ticketing_status via their
-- booking row instead, synced by the trigger above).
SELECT public._drop_all_policies('rail_ticketing_queue');
CREATE POLICY "rail_queue_admin_all" ON public.rail_ticketing_queue FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ── 6. OPTIONAL: pg_cron cleanup schedule ────────────────────────
-- SELECT cron.schedule(
--   'rail-cleanup-ephemeral',
--   '*/15 * * * *',
--   $$ SELECT public.cleanup_rail_ephemeral_data(); $$
-- );
