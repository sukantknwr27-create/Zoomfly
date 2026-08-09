# Production Readiness Audit — Findings & Fixes

Full-repo audit of the 127-file codebase: every edge function
type-checked (`deno check`), every inline `<script>` and standalone
`.js` file syntax-checked (`node --check`), every local `href`/`src`
reference resolved against the filesystem, every `supabase.from()`
table/column reference cross-checked against the actual migration
schema, every `supabase.functions.invoke()` call cross-checked against
deployed edge functions, `vercel.json` routes cross-checked against
files on disk, and every path mentioned in `docs/` cross-checked
against what's actually shipped.

## Real bugs found and fixed

### 1. `carousel.js` import crash (your documented console error)
`index.html` imported it as a **bare module specifier**:
```js
import { initCarousel } from 'assets/js/carousel.js';
```
Browsers reject bare specifiers outright (`Failed to resolve module
specifier`) — this has been silently breaking the homepage carousel
init on every load. Fixed to an absolute path:
```js
import { initCarousel } from '/assets/js/carousel.js';
```

### 2. `promo_codes` 400 Bad Request (your other documented console error)
Root cause found: migration `07_zoomfly_round4_admin_root_cause_fix.sql`
renamed `promo_codes.valid_until` → `expires_at` project-wide, but the
homepage exit-intent popup query in `index.html` was never updated and
still filtered on the old column name, causing every page load to fire
a failing query against a nonexistent column. Fixed to `expires_at`.

### 3. Newsletter signup silently broken
The footer form (`index.html`) called `onsubmit="handleNewsletter(event)"`
— that function was never defined anywhere in the file. Every submit
threw a `ReferenceError`, which meant `preventDefault()` never ran, so
the form fell through to the browser's default GET submission:
reloading the page with the email stuffed into the URL instead of
subscribing anyone. Wrote the missing handler (same pattern as the
existing `exitPopupSubscribe`), wired to `subscribeNewsletter()` in
`assets/js/supabase.js`, with proper loading/success/error button
states.

### 4. Flight booking pipeline was broken end-to-end
`flights.html`'s "Book Now" button calls a `flight-select-fare` edge
function that **did not exist in this codebase** — only 3 of the 4
documented flight-booking stages (`flight-search`,
`flight-create-booking`, `flight-ticket-processor`) were actually
present; the fare-lock stage was missing entirely. Every flight
booking attempt would fail at the first click past search results.

`docs/CHANGES_FLIGHT_BOOKING.md` already documents this function's
exact intended behavior (revalidate price with the provider, write a
`flight_fare_holds` row, return `409` + `soldOut:true` if the fare is
gone) — it was written at some point and lost from this particular
zip, not a design gap. Rewrote it from that spec, matching the
existing `FlightProvider` interface and `flight_fare_holds` schema
exactly. Passes `deno check` with zero errors.

New file: `supabase/functions/flight-select-fare/index.ts`
**→ needs `npx supabase functions deploy flight-select-fare` before flights work.**

### 5. `vercel.json` — 9 dead routes to deleted admin pages
`docs/CHANGES_FULL_ADMIN_CONSOLIDATION.md` confirms
`admin-bookings.html`, `admin-vendors.html`, `admin-agents.html`,
`admin-workflow.html`, `admin-packages.html`, `admin-customers.html`,
`admin-reminders.html`, `admin-whatsapp-templates.html`, and
`admin-hotels.html` were intentionally deleted when everything got
merged into the single `pages/admin.html`. `vercel.json` was never
updated — anyone hitting those clean URLs (or an old bookmark/internal
link) got a raw 404. Changed all 9 to 301-redirect to
`/pages/admin.html` instead.

### 6. `vercel.json` — direct-access block had a gap
The rule blocking direct access to admin pages outside the
`admin.zoomfly.in` host only matched `^/pages/admin-(?!login)(.*)$` —
a pattern that requires a literal hyphen after "admin". It never
matched `pages/admin.html` itself (no hyphen), so that specific
defense-in-depth rule had a hole for the one admin page that still
exists. (`admin.html` has its own independent JS-level session/role
check, so this was a gap in a secondary layer, not the only guard —
still worth closing.) Added a matching rule for `^/pages/admin\.html$`.

## Verified clean (no changes needed)

- All 13 edge functions + all `_shared/*.ts` modules: zero `deno check`
  errors, including the new `flight-select-fare`.
- All 86 inline `<script>` blocks across every page + every standalone
  `assets/js/*.js` file: zero syntax errors.
- Zero broken local `href`/`src` references across all 30 pages.
- Zero other bare module specifiers anywhere in the codebase.
- Zero other stale references to the `promo_codes` column renames.
- Zero table/column name mismatches between frontend `supabase.from()`
  calls and the actual migration schema (30+ tables checked).
- Zero mismatches between frontend `supabase.functions.invoke()` calls
  and deployed edge functions (after fix #4).
- `.env.example` lists every environment variable actually read via
  `Deno.env.get()` — nothing missing, nothing stale.
- `trains.html` / `payment.html` train branch / admin "Rail Ticketing
  Queue" + "API Providers" tabs — confirmed real and fully wired, not
  UI shells (this was flagged as possibly incomplete in earlier
  session notes; it's actually done).
- Razorpay webhook + `verify-razorpay-payment`: idempotency guards
  (`payment_status === 'paid'` short-circuit) present and correct on
  both paths; flight/rail ticketing-queue `upsert(..., {onConflict:
  'booking_id'})` calls all have matching unique indexes in their
  migrations.
- Zero duplicate DOM `id` attributes anywhere (one apparent duplicate
  in `my-bookings.html` was a false positive — inside a JS template
  string for a print-invoice popup, not live page markup).
- Zero fabricated/fake data driving customer-facing UI — every
  `Math.random()` call site is either a mock-provider seed (clearly
  labeled `isMock:true`), a file-path/reference-code generator, or a
  confetti animation.

## Known, pre-existing, intentionally left as-is

These were already correctly flagged in earlier audit docs and are
design decisions, not bugs — not touched here:

- `pages/destination.html` (singular) still runs on hardcoded
  `DEST_DATA`, disconnected from the real `destinations` table —
  needs a content-model decision (itinerary/tips/gallery columns
  don't exist yet) before rebuilding.
- No real flight/rail consolidator connected — `MockFlightProvider`
  and the mock rail provider are active by design, clearly labeled
  `isMock: true` / test data, until Tripjack/TBO/Riya/railYatri
  credentials are in hand.
- Emoji-based icon system (`<span class="emoji-icon">`) is real and
  consistent, not a placeholder — a prior changelog claimed it was
  replaced with SVG; that was corrected in `docs/AUDIT_ISSUES.md`, not
  actually changed in the code.
- `assets/js/home.js` and `assets/js/booking-forms.js` are unused —
  `home.js` is dead code superseded by inline logic in `index.html`;
  `booking-forms.js` is an explicitly-labeled copy-paste template
  ("Drop-in handlers... copy the relevant section into the matching
  page's script block"), not meant to be loaded directly. Neither is
  broken, both are just unreferenced. Safe to delete for repo hygiene
  if you want, not required.

## Before this goes live

Two things I can verify statically but can't fully exercise without
your actual Supabase/Vercel/Razorpay project:

1. **Deploy the new edge function**: `npx supabase functions deploy flight-select-fare`
   — flights will fail past the search step until this is deployed.
2. **Smoke-test the full flight flow once deployed**: search → select
   → passenger form → payment → ticketing, with the mock provider
   active. The code is correct against the documented contract, but a
   live run against your real Supabase instance is the only way to
   catch anything an audit can't (RLS grants that haven't been applied
   yet, a migration that hasn't been run, etc.).
