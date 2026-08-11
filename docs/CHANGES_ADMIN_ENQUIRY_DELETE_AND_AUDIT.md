# ZoomFly Admin — Enquiry Delete + Security Audit
Round: post-login-troubleshooting audit

## Files changed
1. `pages/admin.html` (replace existing file)
2. `supabase/migration/20_zoomfly_enquiries_admin_delete.sql` (new — run this migration)

---

## 1. Delete buttons added — Enquiries, Flight Enquiries, Train Enquiries

All three enquiry tabs were missing a way to delete a lead (spam, duplicate,
test entries). Added a "Delete" button + confirm dialog to each:

- **Enquiries** tab → `deleteEnquiry(id)`
- **Flight Enquiries** tab → `deleteFlightEnquiry(id)` (same underlying
  `enquiries` table, filtered by `interest @> ['flight']`)
- **Train Enquiries** tab → `deleteTrainEnquiry(id)` (separate
  `train_enquiries` table)

**Root cause found while doing this:** `public.enquiries` had SELECT/UPDATE
admin policies but **no DELETE policy at all** — a delete button there would
have silently failed RLS. `public.train_enquiries` already had a `FOR ALL`
admin policy (covers delete), so only the enquiries table needed a DB change.

**Action required:** run `20_zoomfly_enquiries_admin_delete.sql` in the
Supabase SQL editor (or via CLI) before the new Enquiries/Flight delete
buttons will work. Train Enquiries delete works immediately since no schema
change was needed there.

Deliberately **not** added: a hard-delete for Bookings. Bookings are
financial records (payment status, revenue stats, refund tracking) — the
existing Cancel action already covers "get rid of a bad booking" without
destroying the audit trail. `bookings` and `vendors` already have admin
DELETE policies in the DB from earlier rounds if you ever want a hard-delete
button added later; just say so.

---

## 2. Security audit — findings and fixes

Did a full pass across the admin panel: RLS/CRUD coverage for every table
the panel touches (34 tables), XSS escaping on every publicly-writable data
surface, orphaned/broken `onclick` references, duplicate element IDs, and
nav-to-section-to-loader routing integrity.

### Fixed — real stored XSS
**Email Subscribers tab** (`s.email`, `s.source`) was rendered straight into
`innerHTML` with no escaping. Newsletter signup is a fully public,
unauthenticated insert (`WITH CHECK (TRUE)`, `email` is a plain TEXT column
with no server-side format validation) — anyone could POST an HTML/JS
payload as the "email" value directly to the REST API (bypassing the
client-side `type="email"` input entirely) and it would execute in the
admin's session the next time that tab was opened. Now wrapped in `esc()`.

### Fixed — defense in depth (lower real risk)
**Testimonials tab** (`t.name`, `t.city`, `t.trip`) was unescaped. Testimonials
currently have no public insert path (admin-authored only), so this wasn't
externally exploitable today, but fixed for consistency in case that ever
changes.

### Checked clean — no changes needed
- Bookings, Vendors, Reviews, Messages/chat threads, and all three Enquiries
  tabs were already properly escaped despite being public-writable surfaces.
- Every table used in admin.html has correct admin CRUD RLS policies except
  the enquiries DELETE gap above.
- No duplicate `id` attributes (502 checked, all unique).
- No `onclick` handlers pointing at undefined functions (173 checked against
  293 defined).
- Every sidebar nav item maps to a real `section-*` div, and every section
  has a corresponding load call wired into the `show()` router — no orphaned
  or dead tabs.

### Noted, not fixed (low priority)
`deletePackage(...)` / `editTestimonial(...)` build inline
`onclick="fn('...')"` strings and only escape single quotes, not double
quotes. Since package titles / testimonial text are admin-authored only (no
public insert path), this is self-XSS at worst — not exploitable by an
outside party. Worth cleaning up eventually, not urgent.

---

## Deploy steps
1. Run `20_zoomfly_enquiries_admin_delete.sql` in Supabase (SQL editor or CLI).
2. Push updated `admin.html` to Vercel via your normal deploy flow.
3. Verify: Enquiries/Flight/Train tabs each show a working Delete button;
   Email Subscribers and Testimonials tabs render normally (no visual change
   expected — this was an escaping fix, not a UI change).
