// ============================================================
// Supabase Edge Function: get-payment-link
// File: supabase/functions/get-payment-link/index.ts
// Deploy: npx supabase functions deploy get-payment-link
//
// WHY THIS EXISTS:
// Admin-generated payment links (payment.html?ref=<id>) point at the
// payment_links table, but that table's RLS policy only lets the
// booking's owner (or an admin) read it directly — by design, this
// closed an earlier leak where "Anyone view payment_links" was
// readable by anyone. That means a guest who receives a shared link
// (the normal use case — sent over WhatsApp to someone who often
// isn't logged in as the account it was issued to) cannot read it via
// the anon key. This function is the guest-safe read path: possession
// of the unguessable link id is the credential, mirroring
// get-guest-booking's booking_ref+email model. It returns only the
// display fields payment.html needs — never the full row — and is
// the single source of truth for what a `ref=` link actually charges,
// so the frontend never has to trust a client-supplied `amount`.
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

// ── RATE LIMITER (prevent brute-forcing link ids) ─────────────
const _rateWindows = new Map<string, number[]>();
const RATE_LIMIT_MAX    = 10;
const RATE_LIMIT_WINDOW = 60_000;

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
    const { id } = await req.json();
    if (!id) throw new Error('id is required');

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    const { data: link, error } = await supabase
      .from('payment_links')
      .select('id, amount, description, customer_name, status, expires_at, paid_at')
      .eq('id', id)
      .single();

    if (error || !link) throw new Error('Payment link not found.');
    if (link.status !== 'active') throw new Error('This payment link is no longer active.');
    if (link.paid_at) throw new Error('This payment link has already been paid.');
    if (link.expires_at && new Date(link.expires_at) < new Date()) {
      throw new Error('This payment link has expired.');
    }

    return new Response(JSON.stringify({
      amount: Number(link.amount),
      description: link.description || null,
      customer_name: link.customer_name || null,
    }), { headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 400,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }
});
