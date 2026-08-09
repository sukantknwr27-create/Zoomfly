// ============================================================
// Supabase Edge Function: rail-search
// File: supabase/functions/rail-search/index.ts
// Deploy: npx supabase functions deploy rail-search
//
// Real train search, replacing trains.html's previous client-side
// TRAIN_DB + Math.random() availability. Browser never talks to a
// rail provider directly — this function does, using the
// provider-agnostic adapter in _shared/rail-provider.ts. Mirrors
// flight-search/index.ts's structure (rate limit, cache, provider
// call) for consistency.
// ============================================================

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { getRailProvider, STATIONS, type RailSearchParams } from '../_shared/rail-provider.ts';

const ALLOWED_ORIGINS = [
  'https://www.zoomfly.in',
  'https://zoomfly.in',
  'http://localhost:3000',
  'http://127.0.0.1:5500',
];

function corsHeaders(req: Request) {
  const origin = req.headers.get('origin') || '';
  const allowed = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    'Access-Control-Allow-Origin': allowed,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-application',
    'Vary': 'Origin',
  };
}

const _rateWindows = new Map<string, number[]>();
const RATE_LIMIT_MAX = 20;
const RATE_LIMIT_WINDOW = 60_000;

function isRateLimited(ip: string): boolean {
  const now = Date.now();
  const calls = (_rateWindows.get(ip) || []).filter(t => now - t < RATE_LIMIT_WINDOW);
  calls.push(now);
  _rateWindows.set(ip, calls);
  return calls.length > RATE_LIMIT_MAX;
}

const STATION_CODE_RE = /^[A-Z]{2,5}$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const CACHE_TTL_SECONDS = 300; // rail schedules/indicative-availability move slower than flight fares

function validate(body: any): { params: RailSearchParams } | { error: string } {
  const from = String(body.from || '').toUpperCase().trim();
  const to = String(body.to || '').toUpperCase().trim();
  const date = String(body.date || '').trim();
  const quota = ['GN', 'TQ', 'PT', 'LD', 'SS'].includes(body.quota) ? body.quota : 'GN';

  if (!STATION_CODE_RE.test(from)) return { error: 'Invalid origin station code.' };
  if (!STATION_CODE_RE.test(to)) return { error: 'Invalid destination station code.' };
  if (from === to) return { error: 'Origin and destination cannot be the same.' };
  if (!DATE_RE.test(date)) return { error: 'Invalid travel date.' };
  if (new Date(date + 'T00:00:00Z').getTime() < Date.now() - 86_400_000) {
    return { error: 'Travel date cannot be in the past.' };
  }

  return { params: { from, to, date, quota } };
}

async function hashParams(params: RailSearchParams): Promise<string> {
  const normalized = JSON.stringify(params, Object.keys(params).sort());
  const data = new TextEncoder().encode(normalized);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(digest)).map(b => b.toString(16).padStart(2, '0')).join('');
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });

  const ip = req.headers.get('x-forwarded-for')?.split(',')[0].trim() || 'unknown';
  if (isRateLimited(ip)) {
    return new Response(JSON.stringify({ error: 'Too many searches. Please wait a moment and try again.' }), {
      status: 429,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json', 'Retry-After': '60' },
    });
  }

  try {
    const body = await req.json();

    // Station autocomplete is a lightweight sub-mode of this same
    // function — avoids a second edge function just to list stations.
    if (body.mode === 'stations') {
      const q = String(body.query || '').toLowerCase().trim();
      const results = !q ? [] : STATIONS
        .map(s => {
          const code = s.code.toLowerCase(), name = s.name.toLowerCase(), city = s.city.toLowerCase();
          let score = -1;
          if (code === q) score = 100;
          else if (code.startsWith(q)) score = 90;
          else if (city.startsWith(q)) score = 80;
          else if (name.startsWith(q)) score = 70;
          else if (city.includes(q)) score = 50;
          else if (name.includes(q)) score = 40;
          else if (code.includes(q)) score = 30;
          return { s, score };
        })
        .filter(x => x.score > 0)
        .sort((a, b) => b.score - a.score)
        .slice(0, 8)
        .map(x => x.s);
      return new Response(JSON.stringify({ stations: results }), {
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    const validated = validate(body);
    if ('error' in validated) throw new Error(validated.error);
    const { params } = validated;

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    const searchHash = await hashParams(params);

    const { data: cached } = await supabase
      .from('rail_search_cache')
      .select('results, provider')
      .eq('search_hash', searchHash)
      .gt('expires_at', new Date().toISOString())
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (cached) {
      return new Response(JSON.stringify({ results: cached.results, provider: cached.provider, cached: true }), {
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    const provider = await getRailProvider(supabase);
    const results = await provider.search(params);

    supabase.from('rail_search_cache').insert({
      search_hash: searchHash,
      provider: provider.name,
      results,
      expires_at: new Date(Date.now() + CACHE_TTL_SECONDS * 1000).toISOString(),
    }).then(({ error }: { error: any }) => {
      if (error) console.error('[rail-search] cache write failed:', error.message);
    });

    return new Response(JSON.stringify({ results, provider: provider.name, cached: false }), {
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });

  } catch (err) {
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }), {
      status: 400,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }
});
