// ============================================================
// Supabase Edge Function: flight-create-booking
// File: supabase/functions/flight-create-booking/index.ts
// Deploy: npx supabase functions deploy flight-create-booking
//
// Stage 3→4 bridge. Called after the passenger-details form is
// submitted. Unlike packages/hotels (where the browser inserts the
// bookings row directly via RLS, and total_amount is only checked
// against a catalog price later, at payment time), flight bookings
// are created here, server-side, with the service-role key — the
// total_amount is taken ONLY from the fare_hold row, never from
// anything the client sends. This is deliberately stricter than the
// existing package/hotel path because flights have no catalog table
// to cross-check a client-supplied amount against later.
//
// Output: a booking_id the frontend hands straight to the existing
// create-razorpay-order function, exactly like payment.html does for
// packages/hotels today.
// ============================================================

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import type { PassengerInput } from '../_shared/flight-provider.ts';

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
const DOB_RE = /^\d{4}-\d{2}-\d{2}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_RE = /^\d{10,15}$/;

function validatePassenger(p: any, index: number): string | null {
  if (!['Mr', 'Mrs', 'Ms', 'Master', 'Miss'].includes(p.title)) return `Passenger ${index + 1}: invalid title.`;
  if (!NAME_RE.test(String(p.firstName || ''))) return `Passenger ${index + 1}: invalid first name.`;
  if (!NAME_RE.test(String(p.lastName || ''))) return `Passenger ${index + 1}: invalid last name.`;
  if (!DOB_RE.test(String(p.dob || ''))) return `Passenger ${index + 1}: invalid date of birth.`;
  if (!['M', 'F'].includes(p.gender)) return `Passenger ${index + 1}: invalid gender.`;
  if (!['adult', 'child', 'infant'].includes(p.type)) return `Passenger ${index + 1}: invalid passenger type.`;

  // Age-vs-type sanity check — airlines reject fare-bucket mismatches,
  // better to catch it here than after payment.
  const ageYears = (Date.now() - new Date(p.dob).getTime()) / (365.25 * 86_400_000);
  if (p.type === 'infant' && ageYears >= 2) return `Passenger ${index + 1}: infant fare requires age under 2.`;
  if (p.type === 'child' && (ageYears < 2 || ageYears >= 12)) return `Passenger ${index + 1}: child fare requires age 2–11.`;
  if (p.type === 'adult' && ageYears < 12) return `Passenger ${index + 1}: adult fare requires age 12+.`;

  return null;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });

  try {
    const { holdId, passengers, contactEmail, contactPhone, specialRequests } = await req.json();
    if (!holdId) throw new Error('holdId is required');
    if (!Array.isArray(passengers) || passengers.length === 0) throw new Error('At least one passenger is required.');
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

    // Lock the hold: fetch, check ownership/expiry/status, then mark
    // consumed. Not a DB-level transaction, but the 'active' → status
    // update below is a compare-and-set-style guard against the same
    // hold being consumed twice (e.g. a double-submitted form).
    const { data: hold, error: holdFetchError } = await supabase
      .from('flight_fare_holds')
      .select('*')
      .eq('id', holdId)
      .single();
    if (holdFetchError || !hold) throw new Error('Fare hold not found.');
    if (hold.user_id && hold.user_id !== user?.id) throw new Error('This fare hold does not belong to you.');
    if (hold.status !== 'active') throw new Error('This fare hold has already been used or has expired. Please search again.');
    if (new Date(hold.expires_at).getTime() < Date.now()) {
      await supabase.from('flight_fare_holds').update({ status: 'expired' }).eq('id', holdId);
      throw new Error('This fare has expired. Please search again to get the current price.');
    }

    const counts = hold.passenger_counts || { adults: 1, children: 0, infants: 0 };
    const expectedPax = (counts.adults || 0) + (counts.children || 0) + (counts.infants || 0);
    if (passengers.length !== expectedPax) {
      throw new Error(`This fare was locked for ${expectedPax} passenger(s), but ${passengers.length} were submitted.`);
    }

    const { data: refRow } = await supabase.rpc('generate_booking_ref', { svc: 'FLT' });
    const bookingRef = refRow || `ZF-FLT${Date.now()}`;

    const itinerary = hold.itinerary || {};
    const firstLeg = Array.isArray(itinerary.segments) ? itinerary.segments[0] : itinerary.segments?.[0];
    const originCode = firstLeg?.from || hold.search_snapshot?.origin || '';
    const destCode = firstLeg?.to || hold.search_snapshot?.destination || '';

    const { data: booking, error: bookingError } = await supabase
      .from('bookings')
      .insert({
        booking_ref: bookingRef,
        user_id: user?.id || null,
        service_type: 'flight',
        booking_type: 'flight',
        service_name: `${originCode} → ${destCode}`,
        customer_name: `${passengers[0].firstName} ${passengers[0].lastName}`.trim(),
        customer_email: contactEmail,
        customer_phone: contactPhone.replace(/\D/g, ''),
        num_adults: counts.adults || 0,
        num_children: counts.children || 0,
        num_infants: counts.infants || 0,
        travellers: passengers,
        travel_details: { origin: originCode, destination: destCode, itinerary, search: hold.search_snapshot },
        base_amount: hold.fare.base,
        tax_amount: hold.fare.taxes,
        total_amount: hold.fare.total,       // ← from the hold, never client-supplied
        currency: hold.fare.currency || 'INR',
        special_requests: specialRequests || '',
        booking_source: 'website',
        status: 'pending',
        payment_status: 'pending',
        flight_hold_id: hold.id,
        flight_provider: hold.provider,
      })
      .select('id, booking_ref, total_amount')
      .single();

    if (bookingError) {
      console.error('[flight-create-booking] insert failed:', bookingError.message);
      throw new Error('Could not create booking. Please try again.');
    }

    await supabase.from('flight_fare_holds')
      .update({ status: 'consumed', consumed_by_booking_id: booking.id })
      .eq('id', holdId)
      .eq('status', 'active'); // guard: only transitions if still active (see comment above)

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
