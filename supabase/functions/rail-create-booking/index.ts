// ============================================================
// Supabase Edge Function: rail-create-booking
// File: supabase/functions/rail-create-booking/index.ts
// Deploy: npx supabase functions deploy rail-create-booking
//
// Creates a real bookings row for a train, with total_amount taken
// ONLY from a server-side fare recomputation — never from anything
// the client sends. Rail fares don't fluctuate the way live flight
// inventory does, so unlike flights this doesn't need a separate
// fare_hold table: the same deterministic calcMockFare() (or a real
// provider's equivalent) used at search time is re-run here against
// the exact train/class/quota/date, and that recomputed value is
// what gets charged. If a real provider's fare can drift between
// search and booking, its provider class should expose a revalidate-
// style method and this function should call it instead — the mock
// path below is what's wired in today.
//
// Actual ticketing (getting a real IRCTC PNR) never happens here or
// automatically anywhere — see rail_ticketing_queue. This function's
// job ends at creating a 'pending' booking; the queue row is created
// once payment is confirmed (razorpay-webhook / verify-razorpay-
// payment), matching how flight-create-booking hands off to
// flight_ticketing_queue.
// ============================================================

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { getRailProvider, calcMockFare } from '../_shared/rail-provider.ts';

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
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Vary': 'Origin',
  };
}

const NAME_RE = /^[A-Za-z][A-Za-z\s'-]{0,49}$/;
const AGE_RE = /^\d{1,3}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_RE = /^\d{10,15}$/;
const STATION_CODE_RE = /^[A-Z]{2,5}$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const CLASS_CODES = ['1A', '2A', '3A', 'SL', 'CC', 'EC', '2S'];
const QUOTA_CODES = ['GN', 'TQ', 'PT', 'LD', 'SS'];

function validatePassenger(p: any, index: number): string | null {
  if (!NAME_RE.test(String(p.name || ''))) return `Passenger ${index + 1}: invalid name.`;
  if (!AGE_RE.test(String(p.age || ''))) return `Passenger ${index + 1}: invalid age.`;
  if (!['M', 'F', 'T'].includes(p.gender)) return `Passenger ${index + 1}: invalid gender.`;
  return null;
}

function hashSeed(str: string): number {
  let h = 0;
  for (let i = 0; i < str.length; i++) h = (h * 31 + str.charCodeAt(i)) >>> 0;
  return h;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });

  try {
    const {
      trainNumber, trainName, trainType, from, to, travelDate, classCode, quota,
      passengers, contactEmail, contactPhone,
    } = await req.json();

    if (!trainNumber) throw new Error('trainNumber is required.');
    if (!STATION_CODE_RE.test(String(from || ''))) throw new Error('Invalid origin station.');
    if (!STATION_CODE_RE.test(String(to || ''))) throw new Error('Invalid destination station.');
    if (!DATE_RE.test(String(travelDate || ''))) throw new Error('Invalid travel date.');
    if (!CLASS_CODES.includes(classCode)) throw new Error('Invalid class.');
    const finalQuota = QUOTA_CODES.includes(quota) ? quota : 'GN';
    if (!Array.isArray(passengers) || passengers.length === 0) throw new Error('At least one passenger is required.');
    if (passengers.length > 6) throw new Error('A maximum of 6 passengers is allowed per PNR (IRCTC rule).');
    if (!EMAIL_RE.test(String(contactEmail || ''))) throw new Error('A valid contact email is required.');
    if (!PHONE_RE.test(String(contactPhone || '').replace(/\D/g, ''))) throw new Error('A valid contact phone number is required.');

    for (let i = 0; i < passengers.length; i++) {
      const err = validatePassenger(passengers[i], i);
      if (err) throw new Error(err);
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    const authHeader = req.headers.get('Authorization');
    const { data: { user } } = await supabase.auth
      .getUser(authHeader?.replace('Bearer ', '') || '')
      .catch(() => ({ data: { user: null } }));

    // ── Server-side fare recomputation — total_amount NEVER comes
    // from the client. Today this re-derives the same seeded mock
    // fare search used, which is deterministic per (trainType, class,
    // quota, trainNumber/from/to/date) so it always matches what the
    // customer saw in search results. Once a real provider is active,
    // its class should expose an equivalent authoritative-fare call
    // and this block should use that instead of calcMockFare.
    const provider = await getRailProvider(supabase);
    const routeSeed = hashSeed(`${from}${to}${travelDate}`);
    const seed = hashSeed(`${routeSeed}-${trainNumber}-${classCode}`);
    const perPersonFare = provider.name === 'mock'
      ? calcMockFare(trainType || 'Express', classCode, finalQuota, seed)
      : (() => { throw new Error(`Fare recomputation for provider "${provider.name}" is not implemented yet.`); })();

    const total = perPersonFare.total * passengers.length;
    const base = perPersonFare.perPerson * passengers.length;
    const tax = perPersonFare.tax * passengers.length;

    const { data: refRow } = await supabase.rpc('generate_booking_ref', { svc: 'TRN' });
    const bookingRef = refRow || `ZF-TRN${Date.now()}`;

    const { data: booking, error: bookingError } = await supabase
      .from('bookings')
      .insert({
        booking_ref: bookingRef,
        user_id: user?.id || null,
        service_type: 'train',
        booking_type: 'train',
        service_name: `${from} → ${to} (${trainNumber} ${trainName || ''})`.trim(),
        customer_name: passengers[0].name,
        customer_email: contactEmail,
        customer_phone: contactPhone.replace(/\D/g, ''),
        num_adults: passengers.length,
        travellers: passengers,
        travel_details: {
          trainNumber, trainName, trainType, from, to, travelDate,
          classCode, quota: finalQuota,
        },
        base_amount: base,
        tax_amount: tax,
        total_amount: total,          // ← server-recomputed, never client-supplied
        currency: perPersonFare.currency || 'INR',
        booking_source: 'website',
        status: 'pending',
        payment_status: 'pending',
        rail_provider: provider.name,
        rail_ticketing_status: 'awaiting_payment',
      })
      .select('id, booking_ref, total_amount')
      .single();

    if (bookingError) throw new Error('Could not create booking: ' + bookingError.message);

    return new Response(JSON.stringify({
      bookingId: booking.id,
      bookingRef: booking.booking_ref,
      totalAmount: booking.total_amount,
    }), { headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } });

  } catch (err) {
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }), {
      status: 400,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }
});
