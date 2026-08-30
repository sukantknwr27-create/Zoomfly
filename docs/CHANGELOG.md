# ZoomFly — Session Changelog (Full Bundle)

Everything built and fixed this session, consolidated into one package.
17 files total. No DB migrations required for any of it.

---

## 1. Hero Background photo rotator — expanded to 10 more pages
**Files:** `pages/about.html`, `blog.html`, `faq.html`, `contact.html`,
`careers.html`, `loyalty.html`, `referral.html`, `group-booking.html`,
`co-travellers.html`, `trip-tracker.html`, `pages/admin.html`

Added the `heroBg` photo-rotator container + `initHeroBackground('<key>', 'heroBg')`
call to each page (same system already live on Home/Destinations/
Packages/Flights/Cabs/Bus/Trains/Hotels/Vendor). Added all 10 new page
keys to the Hero Backgrounds dropdown in Admin so you can upload photos
immediately. Skipped Search Results/Tour Category/Customize per your
scope choice; `destination.html` untouched (has its own per-destination
photo already).

---

## 2. Admin — Delete actions added to 6 sections that lacked one
**File:** `pages/admin.html`

- **Bookings / Booking Workflow** — `deleteBooking()`. DB refuses the
  delete if a commission/loyalty record already exists against it
  (protects payout history). Flight/rail ticketing-queue rows do
  cascade with the booking — don't delete one with a real ticket
  already issued.
- **Vendors** — `deleteVendor()`. Checks `vendor_payouts` first and
  warns in the confirm dialog if deleting will also wipe payout
  history (that FK cascades).
- **Agents** — `deleteAgent()`. DB blocks delete if commission/payout
  history exists (FK restricts, surfaced as a friendly error).
- **Customers** — `deleteCustomer()` now offers **two** options (see
  #3 below for the full version).
- **Subscribers** — new Actions column + `deleteSubscriber()`.

---

## 3. Full customer account deletion (right-to-erasure)
**Files:** `supabase/functions/delete-customer-account/index.ts` (new),
`pages/admin.html`, `.github/workflows/deploy-supabase-functions.yml`

Client-side admin.html only ever holds the anon key, so it could only
delete the `profiles` row, not the actual Supabase Auth login. This new
Edge Function uses the service_role key server-side to properly delete
`auth.users`, which cascades the profile and everything else linked to
it (co-travellers, price alerts, loyalty data, etc.) — bookings are
kept on purpose (`user_id` set to NULL, not deleted), same as before.

It also pre-emptively detaches a few older foreign keys that reference
`auth.users` without cascade (`payment_links.user_id`,
`messages.sender_id`, `train_enquiries.user_id`, `reminder_log.sent_by`)
so one old chat message can't block a real erasure request with a raw
Postgres error.

`deleteCustomer()` in admin.html now asks which kind you want:
**Full account deletion** (calls the new function) vs.
**Profile only** (the old anon-key delete, login stays active).

Added `delete-customer-account` to the GitHub Actions deploy list —
it'll deploy automatically on next push to `main`.

---

## 4. "View Website" admin link — fixed
**File:** `pages/admin.html`

Was `window.open('/index.html', ...)` — a relative path. Admin only
runs on `admin.zoomfly.in`, which has a catch-all Vercel rewrite that
silently redirects any non-`/pages/`/`/assets/`/`/api/` path to
`admin-login.html`. Changed to an absolute URL
(`https://www.zoomfly.in/`), which isn't subject to that subdomain's
routing at all.

---

## 5. Booking Workflow — page-wide horizontal scroll fixed
**File:** `pages/admin.html`

Not really Workflow-specific — a flexbox `min-width:auto` default
meant `.main`/`.content` couldn't shrink below the kanban board's
~1,630px minimum width, so the **entire admin page** (not just the
board) blew out sideways on any screen under ~1,870px. Added
`min-width:0` to both containers — the board's own `overflow-x:auto`
now works as intended, scrolling just the columns.

*Heads-up, not changed:* `.table-card` uses `overflow:hidden` rather
than `overflow-x:auto` — an unusually wide table could hit the same
class of issue later; easy follow-up if you ever see one clipped.

---

## 6. Footer & login page — 3 navigation bugs fixed
**Files:** `assets/js/main.js`, `pages/login.html`, `pages/packages.html`,
`pages/tour-category.html`

- **"Group Tours"** footer link now points to `group-booking.html`
  (was pointing to a filtered packages list instead).
- **Packages not grouping by category** — admin's package editor lets
  you tag a package `category = 'family'`, but neither
  `packages.html`'s filter pills nor `tour-category.html`'s counting
  logic recognized it as a real category — it silently fell back to a
  text search that rarely matched. Added the missing "Family" pill and
  fixed both pages to match on the real `category` column.
- **"Create Account"** footer link — real JS bug: `switchTab()` was
  called before it was defined (`window.switchTab = ...` is an
  assignment, not hoisted), throwing an error that killed the rest of
  the page's script — so none of Sign In/Sign Up/Google worked when
  arriving via that link. Moved the call to after the definition.

---

## 7. Removed "International" from package Category dropdown
**File:** `pages/admin.html`

It was redundant with the existing Type field (Domestic/International)
— which is the field the site actually checks everywhere for
international filtering. Having it in both places meant a package
could be picked as Category=International and be invisible to every
category filter on the site, since nothing checks category for that
value.

**Safeguard included:** since I have no live DB access to check for
existing `category='international'` packages, editing any package
with that legacy value now shows it flagged as
`"international (legacy — pick a real category)"` in the dropdown
instead of silently resetting to `'adventure'` on save. That flag also
gets cleared before starting a fresh "Add Package" so it can't
accidentally carry over. Next time you're in Admin → Packages, opening
each one for edit will tell you if any are affected.

---

## Verification done on this final pass
- `node --check` on `assets/js/main.js` — clean
- Extracted and `node --check`'d all inline `<script>` blocks (JS only,
  correctly excluding the `application/ld+json` structured-data block
  in `faq.html`) across all 14 changed HTML pages — clean
- `tsc --noResolve --skipLibCheck` on the new Edge Function — same
  class of expected Deno-runtime-only diagnostics as an identical
  check against your existing, working `test-api-provider` function
- Balanced `<div>`/`<section>`/`<table>`/`<tr>`/`<td>` tag counts
  across all 14 changed HTML pages — all matched

## Deploy
Copy all 17 files into their matching repo paths and push. The GitHub
Action will deploy the new Edge Function automatically. No Supabase
migration needed for anything in this bundle.
