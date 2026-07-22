// ============================================================
// Supabase Edge Function: create-razorpay-order
// File: supabase/functions/create-razorpay-order/index.ts
// Deploy: npx supabase functions deploy create-razorpay-order
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

// ── RATE LIMITER ─────────────────────────────────────────────
const _rateWindows = new Map<string, number[]>();
const RATE_LIMIT_MAX    = 5;       // 5 order creation attempts per window per IP
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
    // NOTE: we intentionally do NOT accept `amount` OR `currency` from
    // the client. Trusting a client-supplied amount would let anyone
    // request an order for ₹1 instead of the real price. The price
    // always comes from the booking row itself (always stored in
    // INR), which only the server (this function, with the service
    // role) and Razorpay's webhook can set — never the browser.
    // Currency is hardcoded below for the same reason: if a client
    // could pick e.g. a currency with a much weaker minor-unit value
    // than INR, verify-razorpay-payment/razorpay-webhook's amount
    // check (which compares raw subunits, not currency-aware value)
    // could be satisfied by a real payment worth far less than the
    // booking's actual INR price.
    const { booking_id } = await req.json();
    const currency = 'INR';
    if (!booking_id) throw new Error('booking_id is required');

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    // Identify the caller if there is one — may be null, and that's fine.
    // Guest checkout (no account) is a supported flow on payment.html, so
    // this can't require a logged-in user unconditionally.
    const authHeader = req.headers.get('Authorization');
    const { data: { user } } = await supabase.auth
      .getUser(authHeader?.replace('Bearer ', '') || '')
      .catch(() => ({ data: { user: null } }));

    const { data: booking, error: bookingError } = await supabase
      .from('bookings').select('*').eq('id', booking_id).single();
    if (bookingError || !booking) throw new Error('Booking not found');

    // If this booking belongs to a registered account, only that account
    // may create a payment order for it. Guest bookings (user_id null)
    // have no owner to check against — the booking_id itself (only ever
    // handed to whoever just created it) is the credential, same trust
    // model as get-guest-booking's booking_ref+email.
    if (booking.user_id && booking.user_id !== user?.id) {
      throw new Error('Unauthorized');
    }

    if (booking.payment_status === 'paid') {
      throw new Error('This booking has already been paid for.');
    }

    // Price comes from the booking row — never from the request body.
    const amount = Number(booking.total_amount);
    if (!amount || amount <= 0) throw new Error('Booking has no valid amount to charge.');

    // Idempotency: if an order was already created for this booking
    // (the user hit "Pay" twice, a retry after a network blip, etc),
    // reuse it instead of minting a new Razorpay order — and a new
    // `payments` row — on every call. Razorpay orders don't expire by
    // default, and the amount is always derived from this same
    // booking row, so the existing order is still valid to pay
    // against as long as the booking itself is still unpaid (checked
    // above).
    if (booking.razorpay_order_id) {
      return new Response(JSON.stringify({
        razorpay_order_id: booking.razorpay_order_id,
        amount: Math.round(amount * 100),
        currency,
      }), { headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } });
    }

    // Create Razorpay order
    const razorpayKeyId     = Deno.env.get('RAZORPAY_KEY_ID')!;
    const razorpayKeySecret = Deno.env.get('RAZORPAY_KEY_SECRET')!;
    const credentials = btoa(`${razorpayKeyId}:${razorpayKeySecret}`);

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 10_000); // 10-second timeout

    let orderRes: Response;
    try {
      orderRes = await fetch('https://api.razorpay.com/v1/orders', {
        method: 'POST',
        signal: controller.signal,
        headers: {
          'Authorization': `Basic ${credentials}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          amount: Math.round(amount * 100), // Razorpay uses paise
          currency,
          receipt: booking.booking_ref,
          notes: { booking_id, user_id: user?.id || null }
        }),
      });
    } finally {
      clearTimeout(timeoutId);
    }

    if (!orderRes.ok) {
      const err = await orderRes.json();
      throw new Error(err.error?.description || 'Razorpay order creation failed');
    }

    const order = await orderRes.json();

    // Save order to payments table
    await supabase.from('payments').insert({
      booking_id,
      user_id: user?.id || null,
      razorpay_order_id: order.id,
      amount,
      currency,
      status: 'created'
    });

    // Update booking with Razorpay order ID
    await supabase.from('bookings')
      .update({ razorpay_order_id: order.id })
      .eq('id', booking_id);

    return new Response(JSON.stringify({
      razorpay_order_id: order.id,
      amount: order.amount,
      currency: order.currency,
    }), { headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } });

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 400,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' }
    });
  }
});
