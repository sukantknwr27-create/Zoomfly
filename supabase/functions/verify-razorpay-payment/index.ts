// ============================================================
// Supabase Edge Function: verify-razorpay-payment
// File: supabase/functions/verify-razorpay-payment/index.ts
// Deploy: npx supabase functions deploy verify-razorpay-payment
// ============================================================

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { crypto } from 'https://deno.land/std@0.224.0/crypto/mod.ts';

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

async function hmacSHA256(secret: string, message: string): Promise<string> {
  const encoder = new TextEncoder();
  const keyData = encoder.encode(secret);
  const msgData = encoder.encode(message);
  const cryptoKey = await crypto.subtle.importKey(
    'raw', keyData, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const signature = await crypto.subtle.sign('HMAC', cryptoKey, msgData);
  return Array.from(new Uint8Array(signature)).map(b => b.toString(16).padStart(2, '0')).join('');
}

// Constant-time compare — same rationale as razorpay-webhook/index.ts:
// a plain `!==`/`===` on a signature is a timing side-channel.
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });

  try {
    const { booking_id, razorpay_order_id, razorpay_payment_id, razorpay_signature } = await req.json();

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    // Authenticate user
    const authHeader = req.headers.get('Authorization');
    const { data: { user }, error: authError } = await supabase.auth.getUser(
      authHeader?.replace('Bearer ', '') || ''
    );
    if (authError || !user) throw new Error('Unauthorized');

    // Verify Razorpay signature
    const keySecret = Deno.env.get('RAZORPAY_KEY_SECRET')!;
    const expectedSignature = await hmacSHA256(keySecret, `${razorpay_order_id}|${razorpay_payment_id}`);

    if (!razorpay_signature || !timingSafeEqual(expectedSignature, razorpay_signature)) {
      throw new Error('Payment signature verification failed. Possible fraud attempt.');
    }

    // Fetch booking and verify it belongs to the authenticated user
    const { data: booking } = await supabase.from('bookings').select('*').eq('id', booking_id).single();
    if (!booking) throw new Error('Booking not found');
    if (booking.user_id && booking.user_id !== user.id) {
      throw new Error('Unauthorized: booking does not belong to this user');
    }

    // ── CRITICAL: the order_id/payment_id/signature in the request
    // body are client-supplied. A valid signature only proves *some*
    // real Razorpay payment exists — it does NOT prove that payment
    // was ever created for *this* booking. Without this check, one
    // real payment (order_id/payment_id/signature) could be replayed
    // against any number of different booking_ids that happen to
    // share the same price, confirming them all as "paid" for free.
    // create-razorpay-order always stamps the booking with the exact
    // order_id it created, so that's the source of truth to check
    // against — never trust the order_id the client sends here.
    if (!booking.razorpay_order_id || booking.razorpay_order_id !== razorpay_order_id) {
      throw new Error('This payment does not match the order created for this booking.');
    }

    // Belt-and-braces: also make sure this exact payment_id hasn't
    // already been used to confirm a *different* booking (covers the
    // edge case where two bookings could somehow share an order_id).
    const { data: reusedPayment } = await supabase
      .from('bookings')
      .select('id')
      .eq('razorpay_payment_id', razorpay_payment_id)
      .neq('id', booking_id)
      .eq('payment_status', 'paid')
      .maybeSingle();
    if (reusedPayment) {
      throw new Error('This payment has already been used to confirm a different booking.');
    }

    if (booking.payment_status === 'paid') {
      // Already processed (e.g. duplicate webhook + client call) — return success idempotently.
      return new Response(JSON.stringify({
        success: true, booking_ref: booking.booking_ref, status: 'confirmed',
        message: 'Booking already confirmed.',
      }), { headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } });
    }

    // ── CRITICAL: verify the booking's own claimed total_amount is
    // actually the real catalog price — not just internally
    // consistent with whatever Razorpay captured. The `bookings`
    // table's INSERT policy is deliberately permissive (guest/anon
    // checkout needs to be able to create a row before an account
    // exists), which means anyone can bypass this page's UI entirely
    // and insert a booking claiming *any* total_amount for a real,
    // named, expensive package or hotel — then genuinely pay that
    // self-chosen (tiny) amount via Razorpay. Every check above this
    // point only proves the payment is real and internally
    // consistent with the booking row; none of them prove the booking
    // row's price was ever correct. This does: it looks up the real
    // price from the catalog and rejects anything wildly below it.
    // The 50% floor (rather than an exact match) is a deliberate,
    // conservative tolerance for legitimate promo codes/discounts —
    // it isn't meant to catch every mispriced booking, only to close
    // off "pay almost nothing for an expensive package" as a viable
    // exploit. A tighter, exact-match check would need to re-derive
    // promo/add-on/EMI-interest logic server-side, which is a larger
    // follow-up worth doing on its own.
    if (booking.package_id) {
      const { data: pkg } = await supabase.from('packages')
        .select('price, is_active').eq('id', booking.package_id).maybeSingle();
      if (pkg) {
        const adults = Math.max(1, Number(booking.num_adults) || 1);
        const catalogBase = Number(pkg.price) * adults;
        // Checked against total_amount, not base_amount: an attacker
        // could leave base_amount matching the catalog price and
        // instead inflate discount_amount (itself unvalidated — the
        // client-side promo-code check is display-only, never
        // re-verified server-side) to drive total_amount near zero.
        // total_amount is what's actually paid, so it's what has to
        // be checked against reality regardless of how base/discount
        // were split to get there.
        if (Number(booking.total_amount) < catalogBase * 0.5) {
          await supabase.from('bookings').update({
            internal_notes: `⚠️ PRICE MISMATCH: booking total ₹${booking.total_amount} is far below the catalog price ₹${pkg.price}/person × ${adults} = ₹${catalogBase}. payment_id=${razorpay_payment_id}`,
          }).eq('id', booking_id);
          throw new Error("This booking's price does not match our current catalog price. Our team has been flagged to review this payment.");
        }
      }
    }
    if (booking.hotel_id) {
      const { data: hotel } = await supabase.from('hotels')
        .select('price_per_night, rooms, is_active').eq('id', booking.hotel_id).maybeSingle();
      if (hotel) {
        const roomPrice = Array.isArray(hotel.rooms) && hotel.rooms[0]?.price ? Number(hotel.rooms[0].price) : 0;
        const perNight = roomPrice || Number(hotel.price_per_night || 0);
        if (perNight > 0 && Number(booking.total_amount) < perNight * 0.5) {
          await supabase.from('bookings').update({
            internal_notes: `⚠️ PRICE MISMATCH: booking total ₹${booking.total_amount} is far below the catalog price from ₹${perNight}/night. payment_id=${razorpay_payment_id}`,
          }).eq('id', booking_id);
          throw new Error("This booking's price does not match our current catalog price. Our team has been flagged to review this payment.");
        }
      }
    }

    // ── CRITICAL: confirm the amount actually captured by Razorpay
    // matches the booking's real price. A valid signature only proves
    // the order/payment IDs are genuine — it does NOT prove the
    // correct amount was paid. Without this check, someone could
    // create/pay a Razorpay order for ₹1 and still have this function
    // mark the full-price booking as paid.
    const razorpayKeyId     = Deno.env.get('RAZORPAY_KEY_ID')!;
    const razorpayKeySecret = Deno.env.get('RAZORPAY_KEY_SECRET')!;
    const credentials = btoa(`${razorpayKeyId}:${razorpayKeySecret}`);

    const paymentRes = await fetch(`https://api.razorpay.com/v1/payments/${razorpay_payment_id}`, {
      headers: { 'Authorization': `Basic ${credentials}` },
    });
    if (!paymentRes.ok) throw new Error('Could not verify payment with Razorpay.');
    const razorpayPayment = await paymentRes.json();

    const expectedPaise = Math.round(Number(booking.total_amount) * 100);
    if (razorpayPayment.status !== 'captured' && razorpayPayment.status !== 'authorized') {
      throw new Error(`Payment not completed (status: ${razorpayPayment.status}).`);
    }
    if (razorpayPayment.amount !== expectedPaise) {
      // Flag for manual review instead of silently confirming — do not
      // mark the booking paid on a mismatched amount.
      await supabase.from('bookings').update({
        internal_notes: `⚠️ AMOUNT MISMATCH: paid ${razorpayPayment.amount / 100} vs expected ${booking.total_amount}. payment_id=${razorpay_payment_id}`,
      }).eq('id', booking_id);
      throw new Error('Amount mismatch detected. Our team has been flagged to review this payment.');
    }

    // Update payment record
    await supabase.from('payments').update({
      razorpay_payment_id,
      razorpay_signature,
      status: 'captured',
    }).eq('razorpay_order_id', razorpay_order_id);

    // Confirm booking
    const { data: updatedBooking, error: updateError } = await supabase
      .from('bookings').update({
        status: 'confirmed',
        payment_status: 'paid',
        razorpay_payment_id,
        razorpay_signature,
        paid_amount: booking.total_amount,
        paid_at: new Date().toISOString(),
        confirmed_at: new Date().toISOString(),
      })
      .eq('id', booking_id)
      .select().single();

    if (updateError) throw updateError;

    // Award loyalty points now that the booking is genuinely paid — non-fatal:
    // a points-award failure shouldn't fail an already-successful payment.
    if (updatedBooking.user_id) {
      try {
        const { error: loyaltyError } = await supabase.rpc('earn_booking_points', {
          p_user_id: updatedBooking.user_id,
          p_booking_id: updatedBooking.id,
          p_booking_ref: updatedBooking.booking_ref,
          p_amount_paid: updatedBooking.total_amount,
        });
        if (loyaltyError) console.error('[verify-razorpay] Loyalty award failed:', loyaltyError.message);
      } catch (loyaltyErr) {
        console.error('[verify-razorpay] Loyalty award threw:', loyaltyErr);
      }
    }

    // Send confirmation email — non-fatal: log failure but don't fail the payment
    try {
      const { error: emailError } = await supabase.functions.invoke('send-booking-email', {
        body: { booking_id: updatedBooking.id, type: 'confirmation' }
      });
      if (emailError) console.error('[verify-razorpay] Email send failed:', emailError.message);
    } catch (emailErr) {
      console.error('[verify-razorpay] Email invoke threw:', emailErr);
    }

    return new Response(JSON.stringify({
      success: true,
      booking_ref: updatedBooking.booking_ref,
      status: 'confirmed',
      message: 'Payment verified and booking confirmed!'
    }), { headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } });

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 400,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' }
    });
  }
});
