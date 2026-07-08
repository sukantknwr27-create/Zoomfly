// ============================================================
// Supabase Edge Function: get-guest-booking
// File: supabase/functions/get-guest-booking/index.ts
// Deploy: npx supabase functions deploy get-guest-booking
//
// WHY THIS EXISTS:
// The old RLS policy let anyone with the (public) anon key read
// EVERY guest booking in the database, because it only checked
// `user_id IS NULL` — not who was asking. This function replaces
// that: it requires the booking_ref AND the email on file, and
// only ever returns that one booking, looked up with the service
// role so no broad table grant is needed.
// ============================================================

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

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

// ── RATE LIMITER (prevent brute-forcing booking refs) ────────
const _rateWindows = new Map<string, number[]>();
const RATE_LIMIT_MAX    = 10;      // 10 lookups per window per IP
const RATE_LIMIT_WINDOW = 60_000;  // 60 seconds

function isRateLimited(ip: string): boolean {
  const now = Date.now();
  const calls = (_rateWindows.get(ip) || []).filter(t => now - t < RATE_LIMIT_WINDOW);
  calls.push(now);
  _rateWindows.set(ip, calls);
  return calls.length > RATE_LIMIT_MAX;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });

  const ip = req.headers.get('x-forwarded-for')?.split(',')[0].trim() || 'unknown';
  if (isRateLimited(ip)) {
    return new Response(JSON.stringify({ error: 'Too many requests. Please try again later.' }), {
      status: 429,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json', 'Retry-After': '60' },
    });
  }

  try {
    const { booking_ref, email } = await req.json();
    if (!booking_ref || !email) {
      throw new Error('booking_ref and email are both required');
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    const { data, error } = await supabase.rpc('get_guest_booking', {
      p_ref: booking_ref,
      p_email: email,
    });

    if (error) throw error;
    const booking = Array.isArray(data) ? data[0] : data;

    // Deliberately vague error — don't reveal whether the ref exists
    // but the email didn't match, vs. the ref not existing at all.
    if (!booking) throw new Error('No booking found for that reference and email.');

    return new Response(JSON.stringify({ booking }), {
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 400,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }
});
