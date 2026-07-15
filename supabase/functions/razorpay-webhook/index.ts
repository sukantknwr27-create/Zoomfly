// ============================================================
// Supabase Edge Function: razorpay-webhook
// File: supabase/functions/razorpay-webhook/index.ts
// Deploy: npx supabase functions deploy razorpay-webhook
// Register webhook URL in Razorpay Dashboard:
//   https://YOUR_PROJECT_ID.supabase.co/functions/v1/razorpay-webhook
// ============================================================

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { crypto } from 'https://deno.land/std@0.224.0/crypto/mod.ts';

// Constant-time string compare — prevents a timing side-channel from
// leaking the correct signature one character at a time. A plain `===`
// on a signature check is a classic byte-by-byte timing oracle.
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

async function verifyWebhookSignature(body: string, signature: string, secret: string): Promise<boolean> {
  if (!signature) return false;
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', key, encoder.encode(body));
  const expected = Array.from(new Uint8Array(mac)).map(b => b.toString(16).padStart(2, '0')).join('');
  return timingSafeEqual(expected, signature);
}

serve(async (req) => {
  try {
    const body = await req.text();
    const signature = req.headers.get('x-razorpay-signature') || '';
    const webhookSecret = Deno.env.get('RAZORPAY_WEBHOOK_SECRET')!;

    const isValid = await verifyWebhookSignature(body, signature, webhookSecret);
    if (!isValid) return new Response('Invalid signature', { status: 400 });

    const event = JSON.parse(body);
    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

    const { event: eventType, payload } = event;

    if (eventType === 'payment.captured') {
      const payment = payload.payment.entity;
      await supabase.from('payments').update({
        status: 'captured',
        razorpay_payment_id: payment.id,
        webhook_payload: event,
        updated_at: new Date().toISOString()
      }).eq('razorpay_order_id', payment.order_id);

      // ── CRITICAL: this used to blindly mark EVERY booking row
      // whose razorpay_order_id matched this event's order_id as
      // paid+confirmed, with no check on amount at all. Since the
      // bookings INSERT policy is deliberately permissive (guest
      // checkout needs it), anyone can set a booking's
      // razorpay_order_id to any real order_id they choose — including
      // one from a genuine, unrelated, tiny payment — and this
      // handler would confirm it (and every other booking sharing
      // that order_id) for free the moment that real payment
      // captured. Fixed by fetching the actual candidate booking(s)
      // and verifying, per row, that the captured amount matches what
      // the booking claims AND that the claim matches the real
      // catalog price, before ever marking anything paid. Mismatches
      // are flagged for manual review instead of silently confirmed.
      const { data: candidates } = await supabase
        .from('bookings')
        .select('id, user_id, booking_ref, total_amount, base_amount, num_adults, package_id, hotel_id, payment_status')
        .eq('razorpay_order_id', payment.order_id);

      for (const b of candidates || []) {
        if (b.payment_status === 'paid') continue; // already confirmed — don't reprocess

        const expectedPaise = Math.round(Number(b.total_amount) * 100);
        if (payment.amount !== expectedPaise) {
          await supabase.from('bookings').update({
            internal_notes: `⚠️ WEBHOOK AMOUNT MISMATCH: captured ₹${payment.amount / 100} vs booking claims ₹${b.total_amount}. payment_id=${payment.id}`,
          }).eq('id', b.id);
          continue;
        }

        // Checked against total_amount, not base_amount — see the
        // matching comment in verify-razorpay-payment/index.ts:
        // base_amount alone can look correct while an unvalidated
        // discount_amount drives the actual total near zero.
        let catalogOk = true;
        if (b.package_id) {
          const { data: pkg } = await supabase.from('packages').select('price').eq('id', b.package_id).maybeSingle();
          if (pkg) {
            const adults = Math.max(1, Number(b.num_adults) || 1);
            if (Number(b.total_amount) < Number(pkg.price) * adults * 0.5) catalogOk = false;
          }
        }
        if (b.hotel_id) {
          const { data: hotel } = await supabase.from('hotels').select('price_per_night, rooms').eq('id', b.hotel_id).maybeSingle();
          if (hotel) {
            const roomPrice = Array.isArray(hotel.rooms) && hotel.rooms[0]?.price ? Number(hotel.rooms[0].price) : 0;
            const perNight = roomPrice || Number(hotel.price_per_night || 0);
            if (perNight > 0 && Number(b.total_amount) < perNight * 0.5) catalogOk = false;
          }
        }
        if (!catalogOk) {
          await supabase.from('bookings').update({
            internal_notes: `⚠️ WEBHOOK PRICE MISMATCH: booking price doesn't match catalog. payment_id=${payment.id}`,
          }).eq('id', b.id);
          continue;
        }

        await supabase.from('bookings').update({
          payment_status: 'paid',
          status: 'confirmed',
          paid_at: new Date().toISOString(),
          razorpay_payment_id: payment.id,
        }).eq('id', b.id);

        // Award loyalty points now that the booking is genuinely paid —
        // non-fatal, and skipped if verify-razorpay-payment already did it
        // for this booking (earn_booking_points has no idempotency guard
        // of its own, but the client-side verify call and this webhook
        // race for the same `payment_status==='paid'` transition above,
        // so only one of them will ever reach this point per booking).
        if (b.user_id) {
          const { error: loyaltyError } = await supabase.rpc('earn_booking_points', {
            p_user_id: b.user_id,
            p_booking_id: b.id,
            p_booking_ref: b.booking_ref,
            p_amount_paid: b.total_amount,
          });
          if (loyaltyError) console.error('[razorpay-webhook] Loyalty award failed:', loyaltyError.message);
        }
      }
    }

    if (eventType === 'payment.failed') {
      const payment = payload.payment.entity;
      await supabase.from('payments').update({
        status: 'failed',
        webhook_payload: event,
      }).eq('razorpay_order_id', payment.order_id);

      await supabase.from('bookings').update({
        payment_status: 'failed',
      }).eq('razorpay_order_id', payment.order_id);
    }

    if (eventType === 'refund.created') {
      const refund = payload.refund.entity;
      await supabase.from('payments').update({
        status: 'refunded',
        webhook_payload: event,
      }).eq('razorpay_payment_id', refund.payment_id);

      await supabase.from('bookings').update({
        payment_status: 'refunded',
      }).eq('razorpay_payment_id', refund.payment_id);
    }

    return new Response(JSON.stringify({ received: true }), {
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});
