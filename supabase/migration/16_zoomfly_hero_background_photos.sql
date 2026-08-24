-- Replaces the homepage-only site_settings.homepage_hero_images array
-- with a proper per-page table, so every page's hero (Home, Packages,
-- Destinations, Flights, Cabs, Bus, Hotels, Trains, Vendor) can have
-- its own separate set of rotating background photos behind the
-- existing headline — not a duplicate banner stacked above it.
--
-- Safe to run on the live database — additive only, and migrates any
-- homepage photos already saved under site_settings so nothing is lost.

CREATE TABLE IF NOT EXISTS public.hero_background_photos (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  page_key    TEXT NOT NULL,          -- 'home' | 'packages' | 'destinations' |
                                       -- 'flights' | 'cabs' | 'bus' | 'hotels' |
                                       -- 'trains' | 'vendor'
  image_url   TEXT NOT NULL,
  sort_order  INT NOT NULL DEFAULT 0,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (page_key, image_url)
);

CREATE INDEX IF NOT EXISTS idx_hero_bg_page_key ON public.hero_background_photos(page_key);

ALTER TABLE public.hero_background_photos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "hero_bg_public_read" ON public.hero_background_photos;
CREATE POLICY "hero_bg_public_read" ON public.hero_background_photos
  FOR SELECT USING (is_active = true);

-- Reuses the existing public.is_admin() helper already relied on by
-- carousel_slides — never queries auth.users directly (see prior RLS
-- root-cause notes: auth.users isn't queryable by the authenticated
-- role; is_admin() already handles this correctly).
DROP POLICY IF EXISTS "hero_bg_admin_all" ON public.hero_background_photos;
CREATE POLICY "hero_bg_admin_all" ON public.hero_background_photos
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Carry over any photos already saved for the homepage under the old
-- single-row site_settings array, so re-running/adopting this doesn't
-- lose what's already configured.
INSERT INTO public.hero_background_photos (page_key, image_url, sort_order, is_active)
SELECT 'home', img, ord - 1, true
FROM public.site_settings, unnest(homepage_hero_images) WITH ORDINALITY AS t(img, ord)
WHERE id = 1 AND homepage_hero_images IS NOT NULL
ON CONFLICT (page_key, image_url) DO NOTHING;
