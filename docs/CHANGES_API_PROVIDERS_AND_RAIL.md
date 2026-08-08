# CHANGES: Pluggable API Providers + Real Rail Booking Pipeline

## What changed and why

Two things were requested together because they're the same underlying
problem: (1) trains.html was still running on entirely fake data
(hardcoded schedule, random availability, fake PNR status), the way
flights.html used to before the flight pipeline rebuild; and (2)
switching which supplier API powers flights/rail required a code
deploy (a `FLIGHT_PROVIDER` environment variable), not an admin-panel
action. This round fixes both.

---

## 1. Pluggable API Providers (admin-editable, no redeploy)

**New table: `api_providers`** (migration `17_zoomfly_api_providers.sql`)
Stores which supplier (TBO, Tripjack, Riya, railYatri, or a future
custom one) is active for each service — flight, rail, and (schema
allows, not yet wired) hotel/bus/cab — plus its credentials and
non-secret config. RLS restricts it to admins + the service-role key
edge functions already use everywhere else.

**New admin panel tab: "API Providers"**
Two tables (Flight Providers, Rail Providers), each showing every
configured provider with an Active toggle, priority, last-test result,
and Edit/Test Connection/Delete actions. Seeded with `mock` (active)
plus inactive placeholder rows for TBO, Tripjack, Riya, and railYatri
so you don't have to remember exact provider-key strings — just edit
one of these rows and fill in credentials once you have them.

**"Test Connection"** (new edge function `test-api-provider`)
Runs one canned search against a specific provider row — without
touching what's live for real traffic — and writes the result back to
that row (pass/fail + message + timestamp), shown in the admin table.

**Refactored: `_shared/flight-provider.ts`, new: `_shared/rail-provider.ts`**
`getFlightProvider()`/`getRailProvider()` now read the active provider
from `api_providers` (via `_shared/provider-config.ts`, 30s cache)
instead of a `FLIGHT_PROVIDER` env var. Activating a provider from the
admin panel takes effect within ~30 seconds — no deploy.

**New provider stub files** (`_shared/providers/*-flight.ts`,
`*-rail.ts` for TBO, Tripjack, Riya, railYatri): every method throws a
clear "not implemented yet" error. This is deliberate — if you
activate one of these in the admin panel before it's filled in,
searches fail loudly with an honest error instead of silently
continuing to show mock fares under a real provider's name. To
finish an integration: implement the methods in one of these files
against that provider's real API docs, using the `credentials` /
`config` passed into the constructor (which come from what you typed
into the admin panel, not anything hardcoded).

---

## 2. Real rail booking pipeline

**What trains.html used to do:** a hardcoded 14-train `TRAIN_DB`, a
client-side fare multiplier, `Math.random()` seat availability, and a
`Math.random()` PNR-status generator on the PNR checker — none of it
real, all of it presented as if it were.

**What it does now:**
- **Search** goes through the new `rail-search` edge function, which
  calls a pluggable `RailProvider` (mirrors the flight architecture).
  Today that's `MockRailProvider` — same seeded-deterministic approach
  as `MockFlightProvider`, every result tagged `isMock:true` and shown
  in the UI as "Indicative".
- **Booking** goes through the new `rail-create-booking` edge
  function. The fare is **recomputed server-side** from the exact
  train/class/quota/date — never trusted from the client — same
  principle the flight pipeline already followed.
- **Ticketing is always manual.** IRCTC has no open consolidator API —
  every B2B rail provider (Tripjack Rail, TBO, railYatri) ultimately
  books through an authorized-agent flow. So once payment is
  confirmed (`razorpay-webhook` / `verify-razorpay-payment`, both
  updated), the booking is queued in the new **Rail Ticketing Queue**
  admin tab. An admin books the real IRCTC ticket, enters the real
  PNR, and marks it ticketed — that's what triggers the customer
  confirmation email. Trying to mark a row "Ticketed" without a valid
  10-digit PNR is blocked in the admin UI.
- **PNR status checker** no longer fabricates a status. It checks our
  own records for a PNR we actually ticketed, and otherwise honestly
  says we don't have a live feed yet and links straight to
  IRCTC.co.in — instead of generating a random CNF/WL/RAC result.
- **Popular routes** no longer show a fabricated "N trains daily" /
  "from ₹X" — those numbers were never queried from anything. They're
  quick-search shortcuts now; real numbers only ever come from an
  actual search.
- **WhatsApp booking was NOT removed**, per explicit instruction. It's
  now an explicit secondary button ("Or Book via WhatsApp Instead")
  alongside the new "Proceed to Payment" primary flow — same WhatsApp
  message format as before, still available for customers who prefer
  it, still followed up manually by your team exactly as today.

**`payment.html`** now treats `train` bookings the same way it already
treats `flight` bookings (pre-created server-side, total_amount never
re-derived on this page) — added via a new `isPreCreatedBooking` flag
so the existing Razorpay / bank-transfer / booking-confirmation code
paths needed no further changes.

---

## Files changed / added

**New migrations**
- `supabase/migration/17_zoomfly_api_providers.sql`
- `supabase/migration/18_zoomfly_rail_booking.sql`

**New shared modules**
- `supabase/functions/_shared/provider-config.ts`
- `supabase/functions/_shared/rail-provider.ts`
- `supabase/functions/_shared/providers/tbo-flight.ts`, `tripjack-flight.ts`, `riya-flight.ts`
- `supabase/functions/_shared/providers/tbo-rail.ts`, `tripjack-rail.ts`, `railyatri-rail.ts`

**New edge functions**
- `supabase/functions/rail-search/`
- `supabase/functions/rail-create-booking/`
- `supabase/functions/test-api-provider/`

**Modified**
- `supabase/functions/_shared/flight-provider.ts` — DB-driven factory
- `supabase/functions/flight-search/index.ts` — async provider call
- `supabase/functions/flight-ticket-processor/index.ts` — async provider call
- `supabase/functions/razorpay-webhook/index.ts` — rail queue insertion
- `supabase/functions/verify-razorpay-payment/index.ts` — rail queue insertion
- `pages/admin.html` — "API Providers" + "Rail Ticketing Queue" tabs
- `pages/trains.html` — real search/booking pipeline, honest PNR checker, WhatsApp kept as secondary option
- `pages/payment.html` — `train` bookingUnit support

## Before deploying

1. Run migrations 17 and 18 (staging first, per existing convention).
2. Deploy the new edge functions: `rail-search`, `rail-create-booking`, `test-api-provider`.
3. Redeploy the modified edge functions: `flight-search`, `flight-ticket-processor`, `razorpay-webhook`, `verify-razorpay-payment`.
4. Everything defaults to the mock provider — no behavior change for real money until you fill in a real provider's credentials in the admin panel's API Providers tab and switch it Active.
5. Provider stub files (TBO/Tripjack/Riya/railYatri) will need real implementation work once you have API docs + sandbox credentials — activating them before that will fail loudly by design.
