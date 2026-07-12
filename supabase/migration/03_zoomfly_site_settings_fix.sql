-- ================================================================
-- ZoomFly — 03_zoomfly_site_settings_fix.sql
-- Run AFTER 00, 01, and 02, against STAGING first.
--
-- What this file does:
--   1. Fixes a real, silent bug: admin.html's "Save Company Settings"
--      button has been writing to columns (company_name, support_phone,
--      support_email) that were NEVER created by the master schema —
--      the real columns are site_name and admin_email, with no
--      support_phone/support_email column at all. Supabase/PostgREST
--      rejects an upsert referencing unknown columns, so every save
--      has been silently failing and falling back to a localStorage-only
--      save (see the try/catch in admin.html's saveSettings()) — meaning
--      settings saved from one browser were invisible everywhere else,
--      including the live site. This adds the missing columns so the
--      save actually reaches the database.
--   2. Adds new columns for the fields the Site Settings overhaul adds:
--      homepage hero text, SEO defaults, and social links.
--   3. No RLS changes needed — site_settings already has the correct
--      policy shape (public SELECT, admin-only write).
-- ================================================================

ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS company_name       TEXT DEFAULT 'ZoomFly Travel Services';
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS support_phone      TEXT DEFAULT '+91 80761 36300';
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS support_email      TEXT DEFAULT 'hello@zoomfly.in';

ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS homepage_hero_title    TEXT;
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS homepage_hero_subtitle TEXT;

ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS meta_title         TEXT;
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS meta_description   TEXT;

ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS social_instagram   TEXT;
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS social_facebook    TEXT;
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS social_twitter     TEXT;
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS social_youtube     TEXT;

-- Backfill sensible defaults matching what's currently hardcoded across
-- the site, so turning on the new dynamic reads (nav phone/WhatsApp,
-- favicon, homepage hero) doesn't change anything visually until you
-- actually edit these in the admin panel.
UPDATE public.site_settings SET
  company_name  = COALESCE(company_name, 'ZoomFly Travel Services'),
  support_phone = COALESCE(support_phone, '+91 80761 36300'),
  support_email = COALESCE(support_email, 'hello@zoomfly.in'),
  whatsapp_number = COALESCE(whatsapp_number, '918076136300'),
  homepage_hero_title    = COALESCE(homepage_hero_title, 'Where will you wander next?'),
  homepage_hero_subtitle = COALESCE(homepage_hero_subtitle, 'Curated tours, seamless flights, handpicked hotels — crafted for travellers who expect more than ordinary.'),
  meta_title       = COALESCE(meta_title, 'ZoomFly — Book Flights, Hotels, Packages, Buses & Cabs'),
  meta_description = COALESCE(meta_description, 'India''s all-in-one travel booking platform. Curated tour packages, flights, hotels, buses and cabs at the best prices.'),
  social_instagram = COALESCE(social_instagram, 'https://www.instagram.com/zoomfly.in')
WHERE id = 1;
