// ============================================================
// Supabase Edge Function: flight-search
// File: supabase/functions/flight-search/index.ts
// Deploy: npx supabase functions deploy flight-search
//
// Stage 1 of the flight booking flow. Browser never talks to the
// consolidator directly — this function does, using the
// provider-agnostic adapter in _shared/flight-provider.ts.
// ============================================================

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { getFlightProvider, type FlightSearchParams } from '../_shared/flight-provider.ts';

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
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-applicatione',
    'Vary': 'Origin',
  };
}

// ── RATE LIMITER — search is the cheapest stage to abuse (scraping,
// bot traffic) and, once a real consolidator is wired in, the most
// expensive to us (paid per API call). ──
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

const IATA_RE = /^[A-Z]{3}$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const CACHE_TTL_SECONDS = 150; // 2.5 min — long enough to help back/forward nav, short enough not to serve stale prices

function validate(body: any): { params: FlightSearchParams } | { error: string } {
  const origin = String(body.origin || '').toUpperCase().trim();
  const destination = String(body.destination || '').toUpperCase().trim();
  const departDate = String(body.departDate || '').trim();
  const returnDate = body.returnDate ? String(body.returnDate).trim() : undefined;
  const tripType = ['one-way', 'round', 'multi'].includes(body.tripType) ? body.tripType : 'one-way';
  const cabinClass = ['economy', 'business', 'first'].includes(body.cabinClass) ? body.cabinClass : 'economy';
  const adults = Math.max(1, Math.min(9, parseInt(body.adults) || 1));
  const children = Math.max(0, Math.min(9, parseInt(body.children) || 0));
  const infants = Math.max(0, Math.min(adults, parseInt(body.infants) || 0));

  if (!IATA_RE.test(origin)) return { error: 'Invalid origin airport code.' };
  if (!IATA_RE.test(destination)) return { error: 'Invalid destination airport code.' };
  if (origin === destination) return { error: 'Origin and destination cannot be the same.' };
  if (!DATE_RE.test(departDate)) return { error: 'Invalid departure date.' };
  if (new Date(departDate + 'T00:00:00Z').getTime() < Date.now() - 86_400_000) {
    return { error: 'Departure date cannot be in the past.' };
  }
  if (tripType === 'round') {
    if (!returnDate || !DATE_RE.test(returnDate)) return { error: 'Invalid return date.' };
    if (returnDate < departDate) return { error: 'Return date cannot be before departure date.' };
  }

  return { params: { origin, destination, departDate, returnDate, adults, children, infants, cabinClass, tripType } };
}

async function hashParams(params: FlightSearchParams): Promise<string> {
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
    const validated = validate(body);
    if ('error' in validated) throw new Error(validated.error);
    const { params } = validated;

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    const searchHash = await hashParams(params);

    // Cache check — cuts consolidator calls on repeat searches / back-nav.
    const { data: cached } = await supabase
      .from('flight_search_cache')
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

    const provider = await getFlightProvider(supabase);
    const results = await provider.search(params);

    // Fire-and-forget cache write — a failed cache write should never
    // fail the search response itself.
    supabase.from('flight_search_cache').insert({
      search_hash: searchHash,
      provider: provider.name,
      results,
      expires_at: new Date(Date.now() + CACHE_TTL_SECONDS * 1000).toISOString(),
    }).then(({ error }) => {
      if (error) console.error('[flight-search] cache write failed:', error.message);
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
