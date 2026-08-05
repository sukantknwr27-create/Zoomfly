-- ================================================================
-- ZoomFly — 15_zoomfly_theme_colors.sql
-- Run after 00–14, against STAGING first.
--
-- What this does:
--   Adds four color columns to the existing site_settings singleton row
--   (id = 1) so the whole public site's color scheme can be changed from
--   the admin panel — no code deploy needed.
--
--   theme_primary — brand/button/link color
--   theme_accent  — secondary highlight color
--   theme_bg      — page background color
--   theme_text    — main body text color
--
--   Defaults match the colors already hardcoded across the site today,
--   so running this migration changes nothing visually until someone
--   actually edits these in Site Settings → Theme & Colors.
--
--   How it's applied: assets/js/theme.js reads these four columns and
--   overrides the corresponding CSS custom properties (--primary,
--   --accent, --bg, --text, plus their derived shades) at runtime on
--   every public page. It deliberately does NOT touch each page's own
--   stylesheet — every page already reads its colors via var(--primary)
--   etc, so overriding the variable once cascades everywhere.
-- ================================================================

ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS theme_primary TEXT DEFAULT '#C9922A';
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS theme_accent  TEXT DEFAULT '#E8B84B';
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS theme_bg      TEXT DEFAULT '#F3F2EE';
ALTER TABLE public.site_settings ADD COLUMN IF NOT EXISTS theme_text    TEXT DEFAULT '#1C2340';

UPDATE public.site_settings SET
  theme_primary = COALESCE(theme_primary, '#C9922A'),
  theme_accent  = COALESCE(theme_accent,  '#E8B84B'),
  theme_bg      = COALESCE(theme_bg,      '#F3F2EE'),
  theme_text    = COALESCE(theme_text,    '#1C2340')
WHERE id = 1;
