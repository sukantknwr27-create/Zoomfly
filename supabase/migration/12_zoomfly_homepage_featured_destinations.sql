-- Lets you choose which destinations appear in the homepage's featured
-- destinations grid, instead of that grid being hardcoded separately
-- from the real Destinations data. Safe, additive-only.

ALTER TABLE public.destinations
  ADD COLUMN IF NOT EXISTS is_featured BOOLEAN NOT NULL DEFAULT FALSE;
