# Full Code Audit — Findings & Fix Log

This is a code-level audit (not just docs) of the complete
`Zoomfly-main` repo — 126 files, every edge function, every migration,
every page. Two passes happened:

1. A docs-only audit (before the actual code was available) — found
   internal inconsistencies in `docs/` and fixed them directly (see the
   "Carried over from the docs-only pass" section below).
2. This full code audit — verified every claim in `docs/` against what
   actually ships, ran real syntax/type checks, and checked for
   security/consistency regressions.

## What was checked

- **`deno check`** on all 12 edge functions + every `_shared/*.ts`
  module — full TypeScript type-checking, not just parsing.
- **`node --check`** on all 79 real inline `<script>` blocks across
  every page, plus every standalone `assets/js/*.js` file.
- **JSON-LD validity** on all 7 structured-data blocks site-wide.
- **Internal link integrity** — every `href`/`src`/`action` pointing at
  a local `.html` file, across all 40 pages. 0 broken links.
- **RLS/security spot-checks** against the specific bugs earlier
  changelogs claim to have fixed (self-escalation, payment replay,
  booking self-confirmation, timing-unsafe signature comparison,
  `user_metadata` role trust, XSS escaping in admin tables).
- **Cross-referenced every open/unverified item** from the earlier
  docs-only audit against the real code.

## Fixed in this pass (code changes)

- [x] **`catch (err)` typed as `unknown`** — every edge function
  accessed `err.message` on a caught value TypeScript treats as
  `unknown` by default (strict mode). Not a deploy-breaker (Supabase
  transpiles without full type-checking) but a real type-safety gap.
  Fixed in all 13 occurrences across 12 files with
  `err instanceof Error ? err.message : String(err)`. All edge
  functions now pass `deno check` with zero errors.
- [x] **Fabricated homepage SEO rating** — `index.html`'s structured
  data had a hardcoded `"ratingValue":"4.9","reviewCount":"5000"` with
  no real reviews behind it (flagged as a known, undecided gap in
  `CHANGES_EMOJI_REMOVAL_AND_ICON_FIXES.md`). Replaced with a real
  client-side fetch against the `reviews` table (`is_published = true`),
  computing a genuine average and count. If there are fewer than 5
  real published reviews, the `aggregateRating` property is omitted
  entirely rather than showing a number that isn't real — matches this
  project's own no-fake-stats principle, and Google's own guidance
  against rating snippets backed by too few reviews.
- [x] **Personal email in a schema file** — `00_zoomfly_master_schema.sql`
  had a real personal Gmail address hardcoded alongside the legitimate
  public business address in the "grant admin" block. Added a visible
  repo-hygiene warning and recommended running that grant as a one-off
  SQL Editor query instead of keeping a personal address in a
  version-controlled file. Did not remove the actual grant — that would
  risk locking out an admin account without your say-so.

## Investigated, left as-is (a redesign is your call, not a bug fix)

- [ ] **Emoji vs. SVG icon system.** `CHANGES_EMOJI_REMOVAL_AND_ICON_FIXES.md`
  claims "0 emoji remain" and that lost functional icons were replaced
  with SVG. **That's not what's in the code.** 361+ `<span class="emoji-icon">`
  call sites use real emoji, styled consistently — including the
  password show/hide toggle the doc names as a specific fixed example,
  which uses 👁️/🙈 emoji, not SVG. This is a real, working, consistent
  system — just not what the changelog describes. Doing a genuine SVG
  replacement across 361 call sites in a live, working site is a
  visual redesign with real regression risk, not something to do
  silently as part of an audit pass. Corrected the changelog to say so
  plainly instead of leaving a false "done" claim standing. If you want
  the SVG pass, say the word and it's a dedicated, scoped piece of work.
- [ ] **`pages/destination.html`** (singular) still runs on hardcoded
  `DEST_DATA`, disconnected from the real `destinations` table — this
  was already correctly flagged in the docs as needing a content-model
  decision (itinerary/tips/gallery columns don't exist yet) before
  rebuilding. Left untouched, as previously agreed.

## Verified — claims in `docs/` that turned out to be true

Earlier (docs-only) audit pass flagged these as unconfirmed since only
the changelogs were available, not the code. Checked directly now:

- [x] `trains.html` really was rewritten — no `TRAIN_DB`, no
  `Math.random()`, calls the real `rail-search`/`rail-create-booking`
  edge functions.
- [x] `admin.html`'s "Rail Ticketing Queue" and "API Providers" tabs
  are real, wired to `rail_ticketing_queue` and `api_providers` tables
  — not UI shells.
- [x] `payment.html`'s train branch exists and follows the same
  pre-created-booking pattern as flights.
- [x] The referral point-farming gap (bonus paid at signup instead of
  first booking, no minimum) — flagged as a dropped TODO in the
  docs-only pass — is fixed. `06_zoomfly_referral_first_booking.sql`
  makes the payout timing match what `referral.html` has always
  advertised.
- [x] Migrations `04`–`06` and `14`–`15` (flagged as "never mentioned
  in any changelog") do exist and are well-commented in their own file
  headers — just never got a dedicated `CHANGES_*.md`. Not a real gap;
  all 19 migrations (`00` through `18`) are present with no numbering
  holes.

## Verified — security fixes hold up in the actual code

- [x] `bookings_select`/`enquiries_select` RLS policies use
  `auth.jwt() ->> 'email'`, not a direct `auth.users` lookup — the
  Round 5 fix is genuinely in `00_zoomfly_master_schema.sql`.
- [x] `protect_booking_payment_columns` trigger exists and pins
  payment/pricing columns against non-admin writes — the "direct
  self-confirmation of bookings" fix (Round 2, #16) is real.
- [x] No `user_metadata` role-escalation fallback anywhere in the
  codebase — only `app_metadata`/`profiles` are trusted for admin
  checks.
- [x] Razorpay webhook + payment verification both use a real
  `timingSafeEqual`, not `===`, for signature comparison.
- [x] Flight/rail provider stubs (TBO/Tripjack/Riya/railYatri) throw
  "not implemented" — confirmed no silent mock-under-a-real-name
  fallback.
- [x] Zero references anywhere in the codebase to the 8 deleted
  `admin-*.html` sub-pages.
- [x] `esc()`-style HTML escaping present and applied on every
  risky-field `innerHTML` interpolation checked in `admin.html`
  (guest_name, full_name, business_name patterns) — the Round 2 XSS
  fixes held.

## Still open, disclosed, not touched here (need your decision, not a code fix)

- Homepage SEO gap on `destination.html` — see above.
- No real flight/rail consolidator connected yet (TBO/Tripjack/Riya/
  railYatri) — by design; `MockFlightProvider`/`MockRailProvider` are
  active and clearly labelled `isMock:true`.

---

## Carried over from the docs-only pass (before code was available)

These were fixed directly in `docs/` during the earlier, docs-only
audit and are preserved here for the record:

- `README.md` was frozen at the Round 5 delivery note — rewritten to
  always point at the latest changelog instead of a hardcoded snapshot.
- `CHANGES_ROUND2.md` — section 9 was physically misplaced after
  section 16 in the file; moved back to its correct position.
- `CHANGES_ROUND5.md` — cited the wrong section number for an earlier
  fix (said "section 7," meant "section 18"); corrected. Also clarified
  wording that read as self-contradictory about the "Travel Partners"
  sidebar item vs. group label.
- `SETUP_GUIDE.md` / `FILE_PLACEMENT_GUIDE.md` — added historical
  banners; both describe the project's earliest state and were listed
  as step 1 for new contributors with no such warning.
- `ADMIN_SETUP.md` — fixed a stale routing example pointing at a
  deleted sub-page.
