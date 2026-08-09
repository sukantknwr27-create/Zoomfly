// ============================================================
// Supabase Edge Function: flight-select-fare
// File: supabase/functions/flight-select-fare/index.ts
// Deploy: npx supabase functions deploy flight-select-fare
//
// Stage 2 of the flight booking flow, called when a customer clicks
// "Book Now" on a search result. This is what closes the pricing-
// integrity gap flights have that packages/hotels don't: a flight
// fare has no catalog row to check a client-supplied amount against
// at payment time, so instead this function re-validates the price
// with the provider (provider.revalidate — the fare quoted at search
// time may already be stale) and writes the *revalidated* price into
// a time-boxed flight_fare_holds row. flight-create-booking then
// reads total_amount only from that hold, never from the client.
//
// Input:  { resultId, itinerary, searchSnapshot, passengerCounts }
// Output: { holdId, fare }               on success
//         { error, soldOut?: true }      if the fare is no longer available
// ============================================================

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { getFlightProvider } from '../_shared/flight-provider.ts';

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

const HOLD_TTL_MS = 15 * 60_000; // 15 minutes — matches the copy shown in the passenger-details modal

function validCounts(c: any): c is { adults: number; children: number; infants: number } {
  return c && Number.isInteger(c.adults) && c.adults >= 1 && c.adults <= 9 &&
    Number.isInteger(c.children) && c.children >= 0 && c.children <= 9 &&
    Number.isInteger(c.infants) && c.infants >= 0 && c.infants <= c.adults;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });

  try {
    const { resultId, itinerary, searchSnapshot, passengerCounts } = await req.json();
    if (!resultId || typeof resultId !== 'string') throw new Error('resultId is required.');
    if (!itinerary || !Array.isArray(itinerary.segments) || itinerary.segments.length === 0) {
      throw new Error('A valid itinerary is required.');
    }
    if (!validCounts(passengerCounts)) throw new Error('Invalid passenger counts.');

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    const authHeader = req.headers.get('Authorization');
    const { data: { user } } = await supabase.auth
      .getUser(authHeader?.replace('Bearer ', '') || '')
      .catch(() => ({ data: { user: null } }));

    const provider = await getFlightProvider(supabase);

    // Always trust the provider's revalidated price over whatever was
    // shown at search time — search results can be a couple of
    // minutes old by the time a customer clicks "Book Now".
    const revalidation = await provider.revalidate(resultId);
    if (!revalidation.stillAvailable) {
      return new Response(JSON.stringify({ error: 'This fare is no longer available.', soldOut: true }), {
        status: 409,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    const expiresAt = new Date(Date.now() + HOLD_TTL_MS).toISOString();

    const { data: hold, error: holdError } = await supabase
      .from('flight_fare_holds')
      .insert({
        user_id: user?.id || null,
        provider: provider.name,
        provider_result_ref: revalidation.resultId,
        search_snapshot: searchSnapshot || {},
        itinerary,
        fare: revalidation.fare,
        passenger_counts: passengerCounts,
        status: 'active',
        expires_at: expiresAt,
      })
      .select('id, fare')
      .single();

    if (holdError || !hold) throw new Error('Could not lock this fare: ' + (holdError?.message || 'unknown error'));

    return new Response(JSON.stringify({ holdId: hold.id, fare: hold.fare }), {
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });

  } catch (err) {
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }), {
      status: 400,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }
});
