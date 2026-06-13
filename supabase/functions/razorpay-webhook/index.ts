// ============================================================
// Supabase Edge Function: razorpay-webhook
// File: supabase/functions/razorpay-webhook/index.ts
// Deploy: npx supabase functions deploy razorpay-webhook
// Register webhook URL in Razorpay Dashboard:
//   https://YOUR_PROJECT_ID.supabase.co/functions/v1/razorpay-webhook
// ============================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { crypto } from 'https://deno.land/std@0.168.0/crypto/mod.ts';

async function verifyWebhookSignature(body: string, signature: string, secret: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', key, encoder.encode(body));
  const expected = Array.from(new Uint8Array(mac)).map(b => b.toString(16).padStart(2, '0')).join('');
  return expected === signature;
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

      await supabase.from('bookings').update({
        payment_status: 'paid',
        status: 'confirmed',
        paid_at: new Date().toISOString(),
        razorpay_payment_id: payment.id,
      }).eq('razorpay_order_id', payment.order_id);
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
