# ZoomFly — Round 6 Fixes

Fixes for the 7 issues reported (screenshot list). 6 files changed + 1 new
migration. Frontend fixes are drop-in; the migration must be run once in
Supabase SQL Editor (it's fully idempotent — safe even if some of it
already exists).

---

## 1) Reminders tab — "400 Bad Request" errors

**Root cause:** `loadReminderBookings()` selected a column called
`return_date` from `public.bookings` — that column doesn't exist (the
table only has `travel_date` / `checkin_date` / `checkout_date`).
PostgREST rejects the whole query when you ask for a non-existent
column, which is exactly the two red "Bad Request" lines in your
screenshot.

**Fix (`pages/admin.html`):** query now selects `checkout_date` (which
does exist) and maps it to `return_date` in JS, so the rest of the
reminder logic (which already had a fallback for when it's empty)
doesn't need to change. Also added proper error handling so a failed
query no longer silently breaks the tab.

**Also worth doing:** run the attached migration — it re-creates
`public.reminder_log` (`IF NOT EXISTS`, so harmless if it's already
there). If that table was missing on the live DB, the History/"already
sent" tracking silently had nowhere to write to, which would also show
as failed requests here.

---

## 2) Settings saved, but changes didn't show on the main website

Two separate things going on here:

- **Company Name, Logo, and GSTIN were saved to the database but nothing
  on the public site ever read them back.** Phone/WhatsApp/social
  links/favicon were already wired up correctly, but company name,
  logo, and GSTIN were dead fields. Fixed in `assets/js/main.js`:
  - Logo: if you set a **Logo URL** in Site Settings, it now replaces
    the "ZoomFly" text logo in both the nav bar and the footer,
    site-wide.
  - Company Name: now used in the footer copyright line ("© 2026
    **[Company Name]**. All rights reserved.").
  - GSTIN: now shown in the footer contact column when set.
  - Hero title/subtitle, meta title/description, phone, email,
    WhatsApp, social links were already working correctly — no changes
    needed there.

- **If you're still not seeing changes after this**, it's almost
  certainly that `03_zoomfly_site_settings_fix.sql` (the migration that
  added the `company_name`/`homepage_hero_title`/`social_*` etc.
  columns) was never actually run against the live database — likely
  from the same DB-wipe-and-refresh-master-schema step that also
  explains issue #1. The new migration re-runs those same
  `ADD COLUMN IF NOT EXISTS` statements as a safety net. **Please run
  `10_zoomfly_round6_fixes.sql` in the Supabase SQL Editor** — if those
  columns were already there, it's a no-op; if they weren't, this adds
  them and settings will start actually persisting on save (right now
  it's possible saves are failing over to the localStorage-only
  fallback with an error you may not have noticed, since the toast
  text differs from a hard failure only in wording).

---

## 3 & 7) No way to manually add a Vendor or Agent — and it should use the same data the public forms use

Added **"+ Add Vendor"** (Admin → Vendors) and **"+ Add Agent"** (Admin
→ Agents) buttons that open a form and write directly into
`public.vendors` / `public.agents`.

Fixing this surfaced a real bug worth knowing about: the **public**
"Partner With Us" form (`pages/vendor.html`) was saving vendor
type/owner name into legacy columns (`business_type`, `owner_name`)
that the admin panel's table, filters, and stats don't read — admin
reads `vendor_type` / `contact_name`. So every vendor who applied
through the public form was showing up in Admin → Vendors with the
wrong type (always defaulting to "Hotel") and a blank contact name.

**Fixed in `assets/js/supabase.js`** (`registerVendor()`): now writes
both the new and legacy column names consistently, so public
applications and the new manual admin form produce identical,
correctly-filtered records. The manual "Add Vendor"/"Add Agent" forms
use this exact same field set and table, so a vendor/agent you add by
hand behaves identically to one who applied themselves — same status
values, same commission-rate field, same `agent_code` format
(`ZFA######`) — and if you later give them a portal login and set
their `user_id` to match, their vendor-portal/agent-portal view will
show this same record.

---

## 4) Send Broadcast — "Cannot coerce the result to a single JSON object"

**Root cause:** this is a standard Supabase/PostgREST error thrown by
`.single()` when a query matches **zero** rows. `sendBroadcast()` calls
`getProfile()` first (to log who sent the broadcast), and `getProfile()`
was doing `.select('*').eq('id', user.id).single()` against
`public.profiles`. If the logged-in admin account doesn't have a
matching row in `profiles` — which happens for any account created
directly through the Supabase Auth dashboard/API rather than through
the app's own sign-up flow, since only the sign-up flow triggers the
row-creation trigger — this throws immediately, before the broadcast
insert ever runs.

**Fix (`assets/js/supabase.js`):** `getProfile()` now uses
`.maybeSingle()` (returns `null` on zero rows instead of throwing) and
self-heals by creating the missing profile row on the spot. This fixes
broadcast sending, and likely fixes similar-looking errors anywhere
else `getProfile()` is used (e.g. `requireAdmin()`), since it was the
same underlying cause everywhere.

---

## 5) Deactivated promo code still shown on the homepage popup

**Root cause:** the exit-intent popup on `index.html` had the code
`FIRST10` and "10% OFF" hardcoded directly into the HTML — it never
looked at `promo_codes` at all, so deactivating every code in Admin →
Offers & Promos had zero effect on it.

**Fix (`index.html`):** popup now fetches the best currently **active**
promo code from `public.promo_codes` (respecting `is_active` and
`valid_until`) and displays that code and its real discount value. If
no promo code is active, the popup simply doesn't appear at all instead
of advertising a dead code.

---

## 6) Commission structure not manageable from admin

Added a new **"Commission Structure"** tab under Admin → Vendors, backed
by a new `public.commission_rates` table (see migration). You can edit
the commission range, payout frequency, method, and minimum payout per
partner type and save — changes go live immediately.

**Fix (`pages/vendor.html`):** the public "Transparent Commission
Structure" table and the 4 small commission badges above it
(Hotels/Bus/Tour/Cab cards) now fetch from `commission_rates` instead of
being hardcoded, falling back to the current static numbers only if
that table is empty/not yet migrated.

---

## Migration to run

**`supabase/migration/10_zoomfly_round6_fixes.sql`** — run this once in
the Supabase SQL Editor. It's fully idempotent (every statement is
`IF NOT EXISTS` or an `INSERT ... WHERE NOT EXISTS`), so it's safe to
run even if parts of it turn out to already exist:

1. Re-creates `reminder_log` if missing (issue #1 root cause check)
2. Re-affirms all `site_settings` columns from the 03 migration (issue
   #2 root cause check)
3. Creates `commission_rates` + seeds it with your current 4 default
   rates (issue #6)
4. Confirms `agents.experience` column exists (used by the new manual
   Add Agent form)

## Files changed

- `assets/js/main.js` — logo/company-name/GSTIN wiring
- `assets/js/supabase.js` — `getProfile()` self-heal, `registerVendor()`
  column-mapping fix
- `index.html` — dynamic exit-popup promo code
- `pages/admin.html` — Reminders query fix, Add Vendor/Add Agent
  modals, Commission Structure tab
- `pages/vendor.html` — dynamic commission table
- `supabase/migration/10_zoomfly_round6_fixes.sql` — new
