# Admin Panel — Phase 2 (Blog / FAQ / Careers CMS)

Goal: the three fully-hardcoded content areas — Blog, FAQ, Careers — now have real database tables, admin management screens, and the public pages fetch from Supabase instead of static HTML.

## 1. New database migration: `02_zoomfly_content_cms.sql`
Run this **after** `00_zoomfly_master_schema.sql` and `01_zoomfly_growth_features.sql`, on staging first, same as before.

Creates three tables, all with the same RLS shape as everything else in the schema — public (anon + logged-in) can only read published/active rows, only `is_admin()` can write or see unpublished drafts:
- **`blog_posts`** — slug, title, excerpt, HTML body, emoji, gradient, category, badge color, author, read time, tags, featured flag, published flag.
- **`faqs`** — grouped by a `section` + `section_label` pair (e.g. `booking` / "📋 Booking Process") so the existing section-grouped layout renders dynamically, with a `sort_order` for ordering within a section.
- **`job_openings`** — title, department (+ icon), location, job type, salary range, description, active flag.

**Seed data included:** the migration also inserts everything that was already live — all 6 blog posts (with their full original article bodies pulled programmatically from `blog-post.html`, not retyped, to avoid transcription errors), all 14 FAQ question/answers across 5 sections, and all 6 job listings. **The site won't go blank** the moment you run this — it'll look identical to today, just now backed by the database. Edit or delete any of it from the admin panel afterward.

## 2. Admin panel — three new sections (`admin.html`)
Added under a new "Content" area in the sidebar:
- **📰 Blog** — add/edit/delete posts, toggle featured (gets the large card) and published state. Slug auto-fills from the title as you type (editable).
- **❓ FAQ** — add/edit/delete questions. You type a section key (e.g. `booking`) and label (e.g. "📋 Booking Process") per question — reuse the same section key across multiple questions to group them.
- **💼 Careers** — add/edit/delete job postings, toggle active/closed.

All three follow the same modal-based CRUD pattern as Testimonials/Packages elsewhere in the panel.

## 3. Public pages rewired to fetch from Supabase
- **`blog.html`** — grid now pulls all published posts (featured post gets the big card automatically), sidebar "Recent Posts" widget populated from the same data. Removed the fake "Load More" button and its hardcoded fake-article array (`MORE_ARTICLES`) — everything published now shows on one page.
- **`blog-post.html`** — fetches the specific post by slug from the URL (`?id=<slug>`), renders it into the same layout as before. "More Articles" sidebar now shows 3 other real published posts instead of 4 hardcoded links. Shows a friendly "not found" message if a slug doesn't match anything published. The BlogPosting schema.org JSON-LD is generated from the real post data.
- **`faq.html`** — questions now grouped and rendered from the `faqs` table. **Bonus fix:** the page had a broken/truncated CSS class (`.faq-` split across two lines — likely a copy-paste artifact from an earlier edit) that meant the intended left-hand section nav never existed, so the whole FAQ list was probably rendering squeezed into a 260px column. Added a working scroll-spy nav sidebar (highlights the section you're currently reading) using CSS that was already defined but unused. The FAQPage schema.org JSON-LD now reflects the real (and growing) question set instead of a fixed 5 questions.
- **`careers.html`** — job cards now pulled from `job_openings`; the "Open Roles" counter in the hero updates to the real count instead of a hardcoded "12+".

## Files changed
- `supabase/migration/02_zoomfly_content_cms.sql` (**new** — run this in Supabase SQL editor)
- `pages/admin.html`
- `pages/blog.html`
- `pages/blog-post.html`
- `pages/faq.html`
- `pages/careers.html`

## To deploy
1. Run `02_zoomfly_content_cms.sql` in the Supabase SQL editor (staging first, per usual).
2. Replace the 5 files above in your codebase.
3. Everything should look the same on first load (seed data matches what was live) — then manage it all from Admin → Content.

## Not done in this round
- No image upload yet anywhere on the site — blog posts still use an emoji + CSS gradient as their visual, same as before. If you want real photo uploads for blog posts (and eventually packages/hotels), that's a bigger separate piece of work (needs Supabase Storage bucket + upload UI) — let me know if you want that next.
- FAQ page's category sidebar widget on `blog.html` (categories, tags cloud) is still static decoration — not wired to real counts. Low priority, but flagging it since I didn't touch it.
