# CHANGES — Flight Booking Backend

## What this delivers

A real flight booking pipeline for `pages/flights.html`, replacing the
previous behavior where "Search" generated random fake fares
client-side (`Math.random()`-based) and "Book Now" just opened a
WhatsApp message with no database write at all.

The six-stage flow now implemented end-to-end: **search → lock fare →
passenger details → pay → ticket → confirm.**

## New files

### `supabase/migration/16_zoomfly_flight_booking.sql`
- `flight_search_cache` — short-lived (2.5 min) cache of normalized
  search results, service-role only.
- `flight_fare_holds` — a server-verified, 15-minute price lock. This
  is the piece that closes a gap packages/hotels don't have: those
  can cross-check a client-supplied `total_amount` against a real
  `packages`/`hotels` catalog row at payment time; flights have no
  such catalog row, so the hold *is* that catalog row's stand-in.
  Created only by `flight-select-fare` (service role, after
  re-validating price with the provider), consumed exactly once by
  `flight-create-booking`.
- `flight_ticketing_queue` — tracks the post-payment ticketing call
  against the consolidator, with attempts/backoff/failure state, so a
  payment that succeeds but a ticketing call that fails is never
  silently lost.
- New `bookings` columns: `flight_hold_id`, `flight_provider`,
  `flight_pnr`, `flight_ticket_numbers`, `flight_ticketing_status`.
- RLS matching the existing deny-by-default posture (`payments`-style
  for the cache/queue; own-row-only for holds).
- Commented-out `pg_cron` schedules for cache cleanup and queue
  polling — uncomment once `pg_cron`/`pg_net` extensions are enabled
  on the Supabase project (Dashboard → Database → Extensions).

**Run this after 00–15, on staging first**, like every other migration
in this project.

### `supabase/functions/_shared/flight-provider.ts`
A `FlightProvider` interface (`search`, `revalidate`, `book`,
`cancel`) that every edge function below talks to — none of them know
which consolidator is in use. Currently the only implementation is
`MockFlightProvider`, which returns clearly-labelled placeholder data
(`isMock: true`, obviously-fake airline codes `ZM`/`ZT`) so the full
pipeline can be built and tested before a TBO/Tripjack/Riya/Akbar
contract exists. **No real consolidator is wired up yet** — swapping
one in later means writing one new file implementing this interface
and adding one line to `getFlightProvider()`, not touching any of the
four functions below or the frontend.

### `supabase/functions/flight-search/index.ts` (stage 1)
Validates input (IATA codes, dates, pax counts), checks the cache,
calls the provider, normalizes, caches, returns. Rate-limited
(20/min/IP) since search is the cheapest stage to abuse and — once a
real consolidator is wired in — the most expensive to us.

### `supabase/functions/flight-select-fare/index.ts` (stage 2)
Re-validates the price with the provider (fares move between search
and this moment) and writes the `flight_fare_holds` row. Returns 409
with `soldOut: true` if the fare is gone.

### `supabase/functions/flight-create-booking/index.ts` (stage 3→4 bridge)
Validates passenger data (name format, DOB-vs-fare-type sanity check),
consumes the hold, creates the `bookings` row **server-side** with
`total_amount` taken only from the hold — never from anything the
client sends. This is deliberately stricter than the existing
package/hotel path (where the browser inserts the booking row
directly and `total_amount` is only sanity-checked against a catalog
price later, at payment time) because flights have nothing to check
against later. Returns a `booking_id` the frontend hands straight to
the existing `create-razorpay-order` function.

### `supabase/functions/flight-ticket-processor/index.ts` (stage 5)
Called two ways: inline with `{ bookingId }` right after payment is
verified (most customers get a PNR within seconds), and in poll mode
with `{ source: "cron" }` for anything left in the queue (the retry
backstop). On failure: retries transient errors up to 3 times with
backoff (30s/2min/5min); on a non-retryable failure or exhausted
retries, auto-refunds via Razorpay and flags the booking; if even the
refund fails, marks `needs_review` for manual handling. Money that's
moved never ends in a "paid, nothing issued, nobody told" state.

## Modified files

### `supabase/functions/verify-razorpay-payment/index.ts`
Added: (1) a flight-specific price check — booking `total_amount` must
exactly match the locked `flight_fare_holds.fare.total` (an exact
match is correct here, unlike the 50%-tolerance catalog check used for
packages/hotels, since the hold can never be edited by a client);
(2) after a flight booking is confirmed paid, invokes
`flight-ticket-processor` inline instead of sending the generic
confirmation email (the processor sends its own, once a PNR exists or
a refund happens).

### `supabase/functions/razorpay-webhook/index.ts`
Same flight price check as above, applied per-candidate-booking.
After marking a flight booking paid, enqueues it into
`flight_ticketing_queue` rather than calling the processor inline —
this handler already does several other things per webhook event and
shouldn't gain a hard dependency on a consolidator call succeeding
within its own execution window. This is the reliable backstop; the
inline call in `verify-razorpay-payment` is what gives most customers
a fast PNR.

### `pages/flights.html`
- Removed `generateFlights()` (the `Math.random()` fare generator),
  the fake `AIRLINES` array, and the 900ms fake-searching delay.
- `searchFlights()` now calls the `flight-search` edge function and
  renders real (or real-mock, pending a consolidator) results.
- "Book Now" now calls `flight-select-fare`, opens an inline
  passenger-details form (name/DOB/gender per traveller + contact
  email/phone), then calls `flight-create-booking` and redirects to
  `payment.html` with the resulting `booking_id` — replacing the old
  behavior of opening a WhatsApp message with no booking ever saved.
- Multi-city search still opens a WhatsApp quote request (documented
  in-code): the provider adapter's `search()` is single-leg only for
  now, so this is honestly labelled as a quote request rather than
  pretending to return live multi-leg results.
- **Removed fabricated "From ₹X,XXX" prices and made-up airline
  combos** ("IndiGo · Air India" etc.) from the 8 popular-route cards
  — these were hardcoded numbers with no real pricing behind them,
  which conflicts with this project's honest-first principle (same
  category as the fake reviews/stats already removed elsewhere).
  Replaced with a plain "View live fares →" CTA that still runs the
  real search for that route.

### `pages/payment.html`
Added support for an already-created booking (the flight flow) instead
of only building a booking from `service_id`/session storage:
- New `booking_id` / `booking_ref` URL params, checked before the
  existing package/hotel logic runs.
- `calcAmounts()` and `renderSummary()` have a `bookingUnit === 'flight'`
  path that doesn't re-derive or re-tax the amount (a flight fare's
  total already includes taxes, from the fare hold) — avoids double-
  charging GST on top of an already-taxed fare in the on-screen total.
  The actual charge is unaffected either way, since `create-razorpay-order`
  always re-reads the real amount from the booking row server-side —
  this fix is about the displayed total being correct, not the security
  of the charge.
- The Razorpay button handler skips `createBooking()` and uses the
  existing `booking_id` directly when present.
- The bank-transfer/WhatsApp fallback path does the same, to avoid
  creating a duplicate booking row for a flight.

## What's still open

- **No real consolidator is connected.** Everything above works
  end-to-end against `MockFlightProvider`. Wiring in TBO/Tripjack/Riya/
  Akbar B2B means: getting sandbox credentials, writing one provider
  file implementing `FlightProvider`, and setting `FLIGHT_PROVIDER` in
  the Edge Function environment.
- **`pg_cron` schedules are commented out** in the migration — enable
  the `pg_cron`/`pg_net` extensions and uncomment once ready. Until
  then, the queue backstop only runs when something calls
  `flight-ticket-processor` with `{ source: "cron" }` manually (or you
  wire up an external scheduler).
- **The class/pax selector on `flights.html`** ("2 Adults · Economy",
  "Family (2+2) · Economy") doesn't yet break out adults/children/
  infants individually — it's parsed as an all-adult count for now. A
  dedicated stepper would be a good follow-up; a mismatch here
  surfaces as a clear validation error in `flight-create-booking`
  rather than silently booking the wrong fare, so it's not a safety
  gap, just a UX one.
- **Passenger form is a single flat modal**, not a multi-step wizard —
  fine for 1–3 travellers, would benefit from pagination for larger
  groups.
- **No cancellation/reschedule flow yet** — `FlightProvider.cancel()`
  exists in the adapter interface but nothing calls it yet.
- **Admin visibility**: `flight_ticketing_queue` rows with
  `status IN ('failed_refunding', 'needs_review')` aren't surfaced in
  `admin.html` yet — worth adding a filtered view there next.
