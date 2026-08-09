// ============================================================
// Supabase Edge Function: generate-sitemap
// File: supabase/functions/generate-sitemap/index.ts
// Deploy: npx supabase functions deploy generate-sitemap --no-verify-jwt
//
// The static /sitemap.xml only ever listed 30 fixed marketing pages
// (homepage, /packages, /flights, ...) — it had ZERO individual
// package or blog post URLs, because those are dynamic DB content a
// static file can't represent. That's a real gap: individual package
// pages are exactly the long-tail, specific-keyword pages ZoomFly has
// a realistic shot at ranking for ("Manali Snow Escape 6 days from
// Delhi"), and a page Google doesn't know exists from a sitemap has
// to be found purely through internal links, which is slower and
// less reliable.
//
// This function generates a real sitemap for every *active/published*
// package and blog post directly from the database, so it's always
// in sync with what's actually live — no manual sitemap editing
// whenever a package is added, removed, or deactivated.
//
// Destinations are deliberately NOT included here: pages/destination.html
// still runs on a small hardcoded DEST_DATA object (4 entries), not
// the real `destinations` table — a known, already-flagged gap.
// Generating sitemap URLs against the real destinations table would
// produce links to destination pages that don't actually render
// correctly yet. Add destinations here once that page is rebuilt to
// read from the DB.
//
// Wire-up: vercel.json should rewrite /sitemap-packages.xml to this
// function's URL, and the static /sitemap.xml should link to it via
// a <sitemapindex> (see docs/CHANGES_SEO_IMPROVEMENTS.md for the
// exact steps — this function alone doesn't change what's served at
// the existing /sitemap.xml path).
// ============================================================

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

function escapeXml(s: string): string {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

serve(async (_req) => {
  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    const [{ data: packages, error: pkgErr }, { data: posts, error: postErr }] = await Promise.all([
      supabase.from('packages')
        .select('id, updated_at')
        .eq('is_active', true),
      supabase.from('blog_posts')
        .select('slug, published_at')
        .eq('is_published', true),
    ]);

    if (pkgErr) throw new Error('Could not load packages: ' + pkgErr.message);
    if (postErr) throw new Error('Could not load blog posts: ' + postErr.message);

    const urls: string[] = [];

    for (const p of packages || []) {
      const lastmod = (p.updated_at || new Date().toISOString()).slice(0, 10);
      urls.push(
        `  <url>\n` +
        `    <loc>https://www.zoomfly.in/pages/package-detail.html?id=${escapeXml(p.id)}</loc>\n` +
        `    <lastmod>${lastmod}</lastmod>\n` +
        `    <changefreq>weekly</changefreq>\n` +
        `    <priority>0.7</priority>\n` +
        `  </url>`
      );
    }

    for (const post of posts || []) {
      const lastmod = (post.published_at || new Date().toISOString()).slice(0, 10);
      urls.push(
        `  <url>\n` +
        `    <loc>https://www.zoomfly.in/pages/blog-post.html?id=${escapeXml(post.slug)}</loc>\n` +
        `    <lastmod>${lastmod}</lastmod>\n` +
        `    <changefreq>monthly</changefreq>\n` +
        `    <priority>0.6</priority>\n` +
        `  </url>`
      );
    }

    const xml =
      `<?xml version="1.0" encoding="UTF-8"?>\n` +
      `<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n` +
      urls.join('\n') +
      `\n</urlset>\n`;

    return new Response(xml, {
      headers: {
        'Content-Type': 'application/xml; charset=utf-8',
        'Cache-Control': 'public, max-age=3600', // 1hr — packages/posts don't change minute to minute
      },
    });

  } catch (err) {
    // A broken sitemap is worse than no sitemap for crawlers — fail
    // with a plain-text error rather than emitting malformed XML.
    return new Response('Sitemap generation failed: ' + (err instanceof Error ? err.message : String(err)), {
      status: 500,
      headers: { 'Content-Type': 'text/plain' },
    });
  }
});
