// ============================================================
// Supabase Edge Function: verify-razorpay-payment
// File: supabase/functions/verify-razorpay-payment/index.ts
// Deploy: npx supabase functions deploy verify-razorpay-payment
// ============================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { crypto } from 'https://deno.land/std@0.168.0/crypto/mod.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

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

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

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

    if (expectedSignature !== razorpay_signature) {
      throw new Error('Payment signature verification failed. Possible fraud attempt.');
    }

    // Fetch booking to get amount
    const { data: booking } = await supabase.from('bookings').select('*').eq('id', booking_id).single();
    if (!booking) throw new Error('Booking not found');

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

    // Send confirmation email via Edge Function
    await supabase.functions.invoke('send-booking-email', {
      body: { booking: updatedBooking, type: 'confirmation' }
    });

    return new Response(JSON.stringify({
      success: true,
      booking_ref: updatedBooking.booking_ref,
      status: 'confirmed',
      message: 'Payment verified and booking confirmed!'
    }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
});
