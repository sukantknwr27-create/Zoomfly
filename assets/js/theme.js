// ============================================================
// ZoomFly — Site Theme Loader
// ============================================================
// Applies the brand colors chosen in Admin → Site Settings →
// Theme & Colors to this page, by overriding CSS custom
// properties (--primary, --accent, --bg, --text and their
// derived shades) at runtime.
//
// This deliberately does NOT edit or override each page's own
// stylesheet — every page already reads its colors through
// var(--primary) etc, so setting the variable once here cascades
// everywhere those variables are used, with zero risk to layout
// or markup. Fixed semantic colors (success green, error red,
// warning yellow, loyalty tier metals, etc.) are left alone on
// purpose — only the four brand-identity roles are themeable.
//
// Include with: <script type="module" src="/assets/js/theme.js"></script>
// as early as practical in <head>.
// ============================================================
import { supabase } from './supabase.js';

const CACHE_KEY = 'zf_theme_v1';
const DEFAULTS = {
  theme_primary: '#C9922A',
  theme_accent:  '#E8B84B',
  theme_bg:      '#F3F2EE',
  theme_text:    '#1C2340',
};

function clamp255(n) { return Math.max(0, Math.min(255, n)); }

function hexToRgb(hex) {
  const h = (hex || '').toString().trim().replace('#', '');
  const full = h.length === 3 ? h.split('').map(c => c + c).join('') : h;
  if (!/^[0-9a-fA-F]{6}$/.test(full)) return null;
  const n = parseInt(full, 16);
  return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
}

function rgbToHex(r, g, b) {
  return '#' + [r, g, b].map(v => clamp255(Math.round(v)).toString(16).padStart(2, '0')).join('');
}

// Mixes a hex color toward white (percent > 0) or black (percent < 0).
// Used to derive hover/light shades from a single picked brand color,
// since most pages reference --primary-dark / --primary-light too.
function shade(hex, percent) {
  const c = hexToRgb(hex);
  if (!c) return hex;
  const target = percent < 0 ? 0 : 255;
  const p = Math.abs(percent);
  return rgbToHex(c.r + (target - c.r) * p, c.g + (target - c.g) * p, c.b + (target - c.b) * p);
}

function applyTheme(d) {
  const root = document.documentElement.style;
  const primary = (d && d.theme_primary) || DEFAULTS.theme_primary;
  const accent  = (d && d.theme_accent)  || DEFAULTS.theme_accent;
  const bg      = (d && d.theme_bg)      || DEFAULTS.theme_bg;
  const text    = (d && d.theme_text)    || DEFAULTS.theme_text;

  root.setProperty('--primary', primary);
  root.setProperty('--primary-dark', shade(primary, -0.18));
  root.setProperty('--primary-light', shade(primary, 0.75));

  root.setProperty('--accent', accent);
  root.setProperty('--accent-dark', shade(accent, -0.18));

  root.setProperty('--bg', bg);
  root.setProperty('--bg2', shade(bg, -0.03));

  root.setProperty('--text', text);
  // Several pages use different names for the same "secondary text" role —
  // set every alias seen across the codebase so this covers all of them.
  const mutedTone = shade(text, 0.42);
  const lightTone = shade(text, 0.55);
  root.setProperty('--text-muted', mutedTone);
  root.setProperty('--text-light', mutedTone);
  root.setProperty('--muted', mutedTone);
  root.setProperty('--light', lightTone);
}

// 1. Apply the last-known theme instantly from cache, so returning
//    visitors don't see a flash of the old/default colors while the
//    network request below is in flight.
try {
  const cached = localStorage.getItem(CACHE_KEY);
  if (cached) applyTheme(JSON.parse(cached));
} catch (e) { /* ignore corrupt cache */ }

// 2. Fetch the live theme and refresh the page + cache.
(async () => {
  try {
    const { data, error } = await supabase
      .from('site_settings')
      .select('theme_primary, theme_accent, theme_bg, theme_text')
      .eq('id', 1)
      .maybeSingle();
    if (!error && data) {
      applyTheme(data);
      localStorage.setItem(CACHE_KEY, JSON.stringify(data));
    }
  } catch (e) {
    // Network hiccup or table not migrated yet — keep cached/default
    // colors and never block the page on this.
  }
})();
