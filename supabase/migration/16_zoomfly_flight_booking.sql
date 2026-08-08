-- ================================================================
-- ZoomFly — 16_zoomfly_flight_booking.sql
-- Run AFTER 00–15, against STAGING first.
--
-- What this file does:
--   Adds the real backend for flight bookings. Previously flights.html
--   generated fake fares client-side (Math.random()) and "Book Now"
--   just opened a WhatsApp message — nothing was ever written to the
--   database, and there was no dedicated flight schema at all (only a
--   'flight' value inside the generic bookings.booking_type CHECK).
--
--   This introduces:
--     1. flight_search_cache   — short-lived cache of normalized search
--                                 results, keyed by search params. Cuts
--                                 down repeat calls to the consolidator
--                                 API. Service-role only.
--     2. flight_fare_holds     — a server-verified, time-boxed lock on
--                                 a specific fare. This is what closes
--                                 the pricing-integrity gap flights have
--                                 that packages/hotels don't: packages
--                                 and hotels can be price-checked against
--                                 a `packages`/`hotels` catalog row at
--                                 payment time (see verify-razorpay-payment
--                                 and razorpay-webhook), but a flight
--                                 fare has no catalog row — it only
--                                 exists as whatever the consolidator
--                                 quoted a moment ago. The hold is that
--                                 catalog row's stand-in: created only
--                                 by the flight-select-fare edge function
--                                 (service role) after re-validating the
--                                 price with the provider, consumed
--                                 exactly once by flight-create-booking,
--                                 and expires after 15 minutes so a
--                                 booking can never be created against a
--                                 stale price.
--     3. flight_ticketing_queue — tracks the post-payment ticketing
--                                 step against the consolidator
--                                 (Book/Ticket API) with retry + failure
--                                 state, so a payment that succeeds but
--                                 a ticketing call that fails is never
--                                 silently lost — see flight-ticket-
--                                 processor edge function.
--     4. bookings.flight_*      — a handful of new columns so a flight
--                                 booking's PNR/ticket numbers/provider/
--                                 ticketing status are queryable directly
--                                 instead of buried in travel_details
--                                 JSONB. Existing service_type='flight'
--                                 CHECK constraint (see 00_master_schema)
--                                 already allows this without changes.
-- ================================================================

-- ── 1. FLIGHT SEARCH CACHE ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.flight_search_cache (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  search_hash  TEXT NOT NULL,          -- hash of normalized {origin,destination,date,cabin,...}
  provider     TEXT NOT NULL DEFAULT 'mock',
  results      JSONB NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at   TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_flight_search_cache_hash
  ON public.flight_search_cache(search_hash) WHERE expires_at > NOW();
CREATE INDEX IF NOT EXISTS idx_flight_search_cache_expiry
  ON public.flight_search_cache(expires_at);

-- ── 2. FLIGHT FARE HOLDS ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.flight_fare_holds (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id           UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  provider          TEXT NOT NULL,
  provider_result_ref TEXT NOT NULL,   -- consolidator's ResultIndex / fare token, needed to book later
  search_snapshot   JSONB NOT NULL DEFAULT '{}',  -- origin/destination/date/pax/cabin at search time
  itinerary         JSONB NOT NULL DEFAULT '{}',  -- normalized flight legs (airline, times, duration, stops)
  fare              JSONB NOT NULL DEFAULT '{}',  -- {base, taxes, total, currency} — the server-revalidated price
  passenger_counts  JSONB NOT NULL DEFAULT '{"adults":1,"children":0,"infants":0}',
  status            TEXT NOT NULL DEFAULT 'active'
                       CHECK (status IN ('active','consumed','expired')),
  expires_at        TIMESTAMPTZ NOT NULL,
  consumed_by_booking_id UUID,          -- set once a booking is created from this hold
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_flight_fare_holds_status
  ON public.flight_fare_holds(status, expires_at);
CREATE INDEX IF NOT EXISTS idx_flight_fare_holds_user
  ON public.flight_fare_holds(user_id);

-- ── 3. FLIGHT TICKETING QUEUE ───────────────────────────────────
CREATE TABLE IF NOT EXISTS public.flight_ticketing_queue (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id     UUID NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  status         TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','processing','ticketed','failed_refunding','refunded','needs_review')),
  attempts       INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_error     TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_flight_ticketing_queue_pending
  ON public.flight_ticketing_queue(status, next_attempt_at)
  WHERE status IN ('pending','processing');
CREATE UNIQUE INDEX IF NOT EXISTS idx_flight_ticketing_queue_booking
  ON public.flight_ticketing_queue(booking_id);

-- ── 4. BOOKINGS TABLE EXTENSIONS ────────────────────────────────
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS flight_hold_id       UUID REFERENCES public.flight_fare_holds(id);
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS flight_provider      TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS flight_pnr           TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS flight_ticket_numbers JSONB DEFAULT '[]';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS flight_ticketing_status TEXT; -- mirrors flight_ticketing_queue.status for quick admin filtering

-- ── 5. UPDATED_AT TRIGGER for the queue (matches existing pattern) ──
CREATE OR REPLACE FUNCTION public.touch_flight_ticketing_queue()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_touch_flight_ticketing_queue ON public.flight_ticketing_queue;
CREATE TRIGGER trg_touch_flight_ticketing_queue
  BEFORE UPDATE ON public.flight_ticketing_queue
  FOR EACH ROW EXECUTE FUNCTION public.touch_flight_ticketing_queue();

-- ── 6. HOUSEKEEPING: expire stale holds/cache in one call ───────
-- Call this from a pg_cron schedule (see below) or manually; cheap
-- and idempotent either way.
CREATE OR REPLACE FUNCTION public.cleanup_flight_ephemeral_data()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.flight_fare_holds SET status = 'expired'
    WHERE status = 'active' AND expires_at < NOW();
  DELETE FROM public.flight_search_cache WHERE expires_at < NOW() - INTERVAL '1 hour';
END;
$$;

-- ── 7. ROW LEVEL SECURITY ────────────────────────────────────────
ALTER TABLE public.flight_search_cache    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.flight_fare_holds      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.flight_ticketing_queue ENABLE ROW LEVEL SECURITY;

-- flight_search_cache: service-role only (read/write). The
-- flight-search edge function always uses the service-role key, so
-- the browser never touches this table directly — no anon policy
-- needed at all, same "deny-all by default" posture as `payments`.
SELECT public._drop_all_policies('flight_search_cache');

-- flight_fare_holds: a user may read their own holds (so the
-- passenger-details step can re-display the locked fare after a
-- page refresh); everything else is service-role only. Guest holds
-- (user_id NULL) are looked up by id, which only the browser that
-- just created them ever receives — same trust model as guest
-- bookings elsewhere in this project.
SELECT public._drop_all_policies('flight_fare_holds');
CREATE POLICY "flight_holds_select_own" ON public.flight_fare_holds FOR SELECT USING (
  auth.uid() = user_id OR user_id IS NULL
);

-- flight_ticketing_queue: admin-visible only (this is an internal
-- operational queue, not customer-facing data); writes are
-- service-role only via edge functions.
SELECT public._drop_all_policies('flight_ticketing_queue');
CREATE POLICY "flight_queue_admin_select" ON public.flight_ticketing_queue FOR SELECT USING (
  public.is_admin()
);

-- ── 8. OPTIONAL: pg_cron schedule ────────────────────────────────
-- Requires the pg_cron and pg_net extensions to be enabled on this
-- project (Supabase dashboard → Database → Extensions). Uncomment
-- once enabled — left commented so this migration stays runnable
-- on projects that haven't turned those extensions on yet.
--
-- SELECT cron.schedule(
--   'flight-cleanup-ephemeral',
--   '*/15 * * * *',
--   $$ SELECT public.cleanup_flight_ephemeral_data(); $$
-- );
--
-- SELECT cron.schedule(
--   'flight-ticketing-queue-poll',
--   '*/1 * * * *',
--   $$
--   SELECT net.http_post(
--     url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/flight-ticket-processor',
--     headers := jsonb_build_object(
--       'Authorization', 'Bearer ' || 'YOUR_SERVICE_ROLE_KEY',
--       'Content-Type', 'application/json'
--     ),
--     body := '{"source":"cron"}'::jsonb
--   );
--   $$
-- );
