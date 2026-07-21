-- Adds a column to store multiple homepage hero background photos for
-- the carousel. Safe to run on the live database — additive only.
--
-- homepage_hero_images: an array of image URLs. When empty/null, the
-- homepage falls back to the existing gradient + mountain illustration
-- (nothing breaks if you don't set this).

ALTER TABLE public.site_settings
  ADD COLUMN IF NOT EXISTS homepage_hero_images TEXT[] DEFAULT '{}';
