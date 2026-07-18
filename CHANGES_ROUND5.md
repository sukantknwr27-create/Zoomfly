# Round 5 — Fixes for issues in Zoomfly_updates.pdf

## 🔴 Root cause found: issues 1, 2, 3, 4, 6 were all ONE bug

**Run `supabase/migration/09_zoomfly_round5_rls_auth_users_regression_fix.sql`
on your live database now — this is the fix for the Enquiries, Bookings,
Workflow, Messages, and Flight Enquiries tabs all failing to load.**

### What was happening
- `bookings_select` and `enquiries_select` RLS policies queried
  `(SELECT email FROM auth.users WHERE id = auth.uid())` directly.
- Supabase does **not** grant the `authenticated` role SELECT access to
  `auth.users` (locked down by design). So every query against
  `bookings` or `enquiries` — from anyone, including you as admin —
  threw `permission denied for table users`.
- This cascades: **Workflow** reuses the same bookings query.
  **Messages** joins `bookings(booking_ref, guest_name)` in its select,
  which re-triggers bookings' own broken policy even though the
  Messages policy itself never touches `auth.users`. **Flight
  Enquiries** reads from the `enquiries` table, so it hit the same
  wall from the enquiries side.
- Interestingly, this exact bug was already diagnosed and fixed once
  before, in `01_zoomfly_growth_features.sql` (section 7) — but
  `00_zoomfly_master_schema.sql` (the "run fresh on a wiped DB" file)
  still had the old broken version. If that master file is ever
  re-run by itself without 01-08 layered back on top, the fix quietly
  disappears again. That's almost certainly what happened here.

### The fix
- Replaced the direct `auth.users` lookup with `auth.jwt() ->> 'email'`,
  which reads the email straight out of the current session's JWT —
  no table access needed at all.
- Applied in two places:
  - `supabase/migration/09_zoomfly_round5_rls_auth_users_regression_fix.sql`
    — **run this on your live DB now**, safe to run multiple times.
  - `supabase/migration/00_zoomfly_master_schema.sql` — updated so a
    future fresh install can't reintroduce this bug by itself.

No frontend changes were needed for issues 1/2/3/4/6 — the queries
were always correct, only the database policy was blocking them.

---

## 5) Destination form cutting off (`pages/admin.html`)
The Add/Edit Destination modal had no height limit, so on shorter
screens the bottom of the form (image-URL field, Cancel/Save buttons)
rendered below the visible viewport with no way to scroll to it. Added
`max-height:90vh;overflow-y:auto` to the modal panel, matching every
other modal on the page. Checked all 11 modals in admin.html — this
was the only one missing it.

## 7) Sidebar "Travel Partners" removed
The sidebar had both a dedicated **Vendors** page and **Agents** page,
*plus* a third "Travel Partners" page that just re-listed the same
vendors and agents with links back to those same two pages. Removed
the redundant nav item, its section, and its now-unused
`loadTravelPartners()`/`togglePartnerStatus()` functions. Also fixed a
related bug this touched: several sidebar shortcuts (Quick Links on
the Overview page, the "+ Add Package" button) referenced sidebar
items by a hardcoded array index (e.g.
`document.querySelectorAll('.nav-item')[13]`), which breaks every time
an item is added or removed above it. `show()` now looks up the
correct sidebar item by its page id instead, so this can't silently
point at the wrong nav item again.

## 8) Commission Management page added
There was no central place to view or edit commission rates — vendor
commission was actually hardcoded at a flat 10% in the vendor drawer
(not even reading the `commission_rate` column that already existed
in the database), and agent rates could only be seen, not edited, from
the admin side. Added:

- A new **Commission Management** page (sidebar, under "Travel
  Partners" section) with:
  - Summary cards: total agent commission earned/paid/pending, and
    total vendor commission accrued.
  - A **Commission Rates by Vendor** table — edit any vendor's rate
    inline.
  - A **Commission Rates by Agent** table — edit any agent's rate
    inline.
  - A full **Agent Commission Ledger** (all `agent_commissions`
    records, filterable by status).
- Fixed the vendor drawer's hardcoded "Commission (10%)" to use the
  vendor's real rate, and made that rate editable right from the
  drawer.
- Made agent commission rate editable from the agent drawer too
  (previously view-only there).

## Files changed
- `pages/admin.html`
- `supabase/migration/00_zoomfly_master_schema.sql` (fixed for future fresh installs)
- `supabase/migration/09_zoomfly_round5_rls_auth_users_regression_fix.sql` (**new — run this on the live DB**)

## Action needed from you
1. Run `09_zoomfly_round5_rls_auth_users_regression_fix.sql` in the
   Supabase SQL Editor on your live database.
2. Replace `pages/admin.html` with the version in this delivery and
   redeploy.
