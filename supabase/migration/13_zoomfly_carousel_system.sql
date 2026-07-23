-- ============================================================
-- Generic, admin-managed carousel system.
-- One table drives banner carousels on any number of pages —
-- Home, Destinations, Packages, Flights, Cabs, Bus, Trains, Hotels
-- — distinguished by `page_key`. Safe to run on the live database:
-- additive only, and every page that reads this table already
-- falls back to its existing static hero/banner if there are no
-- active slides for its page_key, so nothing breaks if this table
-- is empty.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.carousel_slides (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  page_key    TEXT NOT NULL,           -- 'home' | 'destinations' | 'packages' | 'flights' | 'cabs' | 'bus' | 'trains' | 'hotels'
  image_url   TEXT NOT NULL,
  title       TEXT,
  subtitle    TEXT,
  cta_text    TEXT,
  cta_link    TEXT,
  sort_order  INT NOT NULL DEFAULT 0,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_carousel_slides_page ON public.carousel_slides(page_key, sort_order);

ALTER TABLE public.carousel_slides ENABLE ROW LEVEL SECURITY;

-- Public can read active slides for any page (same shape as
-- packages/hotels: is_active=true OR admin sees everything so the
-- admin panel preview can show disabled slides too).
DROP POLICY IF EXISTS "carousel_public_read" ON public.carousel_slides;
CREATE POLICY "carousel_public_read" ON public.carousel_slides
  FOR SELECT USING (is_active = TRUE OR public.is_admin());

DROP POLICY IF EXISTS "carousel_admin_write" ON public.carousel_slides;
CREATE POLICY "carousel_admin_write" ON public.carousel_slides
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Keep updated_at current on every edit.
CREATE OR REPLACE FUNCTION public.set_carousel_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_carousel_updated_at ON public.carousel_slides;
CREATE TRIGGER trg_carousel_updated_at
  BEFORE UPDATE ON public.carousel_slides
  FOR EACH ROW EXECUTE FUNCTION public.set_carousel_updated_at();
