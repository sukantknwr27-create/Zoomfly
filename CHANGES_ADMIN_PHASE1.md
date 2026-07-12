# Admin Panel — Phase 1 (Quick Wins)

Goal: close gaps where a Supabase table already existed with proper RLS, but had **no admin UI** to manage it. No schema changes needed — both tables and their `is_admin()` RLS policies already existed correctly from prior rounds.

## 1. Trains — new admin section (`admin.html`)
- **Problem:** `trains.html` writes to a real `train_enquiries` table, but nothing in the admin panel ever showed those rows — enquiries were being collected and going completely unseen.
- **Fix:** New "Trains" nav item + section, right next to Flights. Lists from/to station, travel date, quota, passenger count, and status, with a "Mark Done" action — mirrors the existing Flight Enquiries pattern exactly.

## 2. Reviews — new moderation section (`admin.html`)
- **Problem:** The `reviews` table (separate from `testimonials` — these are customer-submitted, tied to a booking/package/hotel) had zero admin visibility or moderation.
- **Fix:** New "Reviews" nav item + section. Shows rating, title, review excerpt, which package/hotel it's attached to, verified status, and publish state. Admin can Publish/Unpublish or Delete — no "Add" button, since these should only ever come from real customers, not be authored by admin (that's what Testimonials is for).
- Sidebar badge shows count of unpublished (pending review) items, same visual pattern as the Enquiries badge.

## 3. Vendor Payouts — new tab (`admin-vendors.html`)
- **Problem:** `vendor_payouts` table existed with correct RLS (vendors see only their own rows; admin sees/manages all), but there was no way to actually create or manage a payout — unlike Agents, which already had this via `admin-agents.html`.
- **Fix:** Added a tab bar to `admin-vendors.html` ("All Vendors" / "Payouts"), matching the tab pattern already used on the Agents page. New Payouts tab has:
  - Summary cards: pending/processing amount, total paid all-time, record count
  - A payout card list (vendor name, period, booking count, UTR once paid, gross/commission/net breakdown, status)
  - "New Payout" modal — pick an active vendor, enter gross amount + commission (net auto-calculates), period dates, status, UTR, notes
  - "Mark Paid" one-click action prompts for UTR and stamps today's date
  - Edit and delete on existing records

## Files changed
- `pages/admin.html` (Trains + Reviews sections, nav items, dispatcher hooks)
- `pages/admin-vendors.html` (Payouts tab, modal, JS logic)

## Not touched (by design)
- No SQL changes — this phase only used existing tables/RLS.
- Flights intentionally still uses the `enquiries` table filter (not a separate `flights` table) — this matches your existing model where flight bookings come in as enquiries, not managed inventory. Let me know if you actually want flight inventory (routes/pricing) to become manageable like buses/cabs — that'd need a new table.

## Next up (Phase 2 — bigger lift, needs new tables)
Blog CMS, FAQ CMS, Careers/job listings CMS — all currently 100% hardcoded HTML with no table backing them at all. Ready to start on these next unless you want to reorder.
