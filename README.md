# ZoomFly — Delivery

## Files included
- `admin.html` → replace `pages/admin.html`
- `supabase/migration/09_zoomfly_round5_rls_auth_users_regression_fix.sql` → **run on your live DB now**
- `supabase/migration/00_zoomfly_master_schema.sql` → updated reference copy (only needed if you ever rebuild a database from scratch)
- `CHANGES_ROUND5.md` → full write-up of the 8 issues from your PDF and what fixed each one

## Note on image uploads
Image uploads stay on **Supabase Storage** as they were before — the
GitHub-based upload approach discussed earlier was reverted at your
request. No setup changes needed here; uploads work the same way they
always did.

## Action items, in order

1. **Run the SQL migration** — Supabase Dashboard → SQL Editor → paste and
   run `09_zoomfly_round5_rls_auth_users_regression_fix.sql`. This is what
   fixes Enquiries, Bookings, Workflow, Messages, and Flight Enquiries all
   failing to load.
2. **Replace `pages/admin.html`** with the one in this delivery and redeploy.
   This includes: the destination-form scroll fix, the sidebar cleanup
   (Travel Partners removed), and the new Commission Management page.

That's it — no other code changes needed.
