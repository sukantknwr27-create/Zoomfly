# Admin Panel — Phase 4 (Site Settings Overhaul)

This was the last item from the original audit. Two things happened here: a real bug fix, and new fields that now actually take effect on the live site (previously, Site Settings saved to a table nothing read from).

## 1. Bug fix: Site Settings was silently failing to save
`admin.html`'s `saveSettings()` has been writing to columns — `company_name`, `support_phone`, `support_email` — that **never existed** in `site_settings` (the real columns were `site_name` and `admin_email`, with no phone/email columns at all). Supabase rejects an upsert referencing unknown columns, so every "Save Company Settings" click has been silently failing and quietly falling back to a `localStorage`-only save — meaning it looked like it worked, but the data never left your browser, let alone reached the live site.

Fixed by adding the actual missing columns (migration `03_zoomfly_site_settings_fix.sql`) and correcting the error handling so a real failure now shows an honest error toast instead of a fake "saved" message.

## 2. New Site Settings fields — and they now actually work
Previously nothing on the live site read from `site_settings` at all — it was a form that saved into a void. Now:

- **Homepage Hero** (title + subtitle) — editable, applies to `index.html` on load. Leave blank to keep the designed default (with its styled "wander" emphasis); typing a custom title replaces it with plain text, so it's your call whether the trade-off is worth it.
- **SEO Defaults** (meta title + description) — updates the page title and description tag on load. Important honesty note: this is real for the browser tab and any tool that executes JS, but it is **not** a substitute for true SEO — most search engine indexing reads the static HTML directly, so if ranking really matters, the static `<title>`/`<meta>` tags in `index.html` should also be edited directly. I didn't want to oversell this as "SEO management" when it isn't full SEO control on a static site.
- **Social Links** (Instagram, Facebook, Twitter/X, YouTube) — these were previously **all `href="#"` placeholders in the footer, completely non-functional on every page of the site**. Now wired to real admin-editable URLs; any link left blank shows dimmed/inert instead of a dead `#` link.
- **Support Phone / WhatsApp Number** — now actually propagates: the footer (already JS-templated) picks it up directly, and the phone number baked into the shared `nav.html` fragment gets patched in-place after it loads, so the same number shows everywhere without having to hand-edit every page.
- **Favicon URL** — now actually applied to the page's `<link rel="icon">` on load, instead of being saved and never read.

## Files changed
- `supabase/migration/03_zoomfly_site_settings_fix.sql` (**new** — adds missing columns, backfills defaults matching what's currently live so nothing visually changes until you edit something)
- `pages/admin.html` (fixed save/load bug, added Homepage Hero / SEO / Social Links cards, consolidated to one "Save All Settings" button)
- `assets/js/main.js` (loads `site_settings` before rendering nav/footer, wires phone/WhatsApp/social/favicon everywhere those are used)
- `index.html` (hero title/subtitle now overridable; meta title/description now overridable with the above caveat)

## Known limitation
This wiring covers the shared `nav.html`/footer (used on every page) and the homepage hero/meta — the two highest-value, lowest-risk targets. It does **not** reach into the ~40 individual pages that might have their own additional hardcoded phone/email mentions in body copy (e.g. a phone number written directly into `contact.html`'s own text). Rewiring every such mention individually is a much bigger, page-by-page job — let me know if you want that as a separate pass, and I'd do it methodically rather than as a rushed find-and-replace given how much text is involved.

---

## Summary of all 4 phases this session
1. **Trains, Reviews, Vendor Payouts** — admin visibility for tables that already existed but had no UI
2. **Blog, FAQ, Careers CMS** — three fully-hardcoded content areas now have real tables + admin management + dynamic public pages
3. **Messages inbox, Broadcast history** — customer communication now visible/actionable from admin
4. **Site Settings** — fixed a silent save bug and made the settings actually affect the live site

That closes every gap identified in the original audit. If new gaps turn up as you use the site day to day, the same workflow applies: tell me what you're seeing and I'll trace + fix it.
