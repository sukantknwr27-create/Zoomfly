// ============================================================
// Supabase Edge Function: create-razorpay-order
// File: supabase/functions/create-razorpay-order/index.ts
// Deploy: npx supabase functions deploy create-razorpay-order
// ============================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const { booking_id, amount, currency = 'INR' } = await req.json();

    // Verify user is authenticated
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    const authHeader = req.headers.get('Authorization');
    const { data: { user }, error: authError } = await supabase.auth.getUser(
      authHeader?.replace('Bearer ', '') || ''
    );
    if (authError || !user) throw new Error('Unauthorized');

    // Verify booking belongs to user
    const { data: booking, error: bookingError } = await supabase
      .from('bookings').select('*').eq('id', booking_id).eq('user_id', user.id).single();
    if (bookingError || !booking) throw new Error('Booking not found');

    // Create Razorpay order
    const razorpayKeyId     = Deno.env.get('RAZORPAY_KEY_ID')!;
    const razorpayKeySecret = Deno.env.get('RAZORPAY_KEY_SECRET')!;
    const credentials = btoa(`${razorpayKeyId}:${razorpayKeySecret}`);

    const orderRes = await fetch('https://api.razorpay.com/v1/orders', {
      method: 'POST',
      headers: {
        'Authorization': `Basic ${credentials}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        amount: Math.round(amount * 100), // Razorpay uses paise
        currency,
        receipt: booking.booking_ref,
        notes: { booking_id, user_id: user.id }
      }),
    });

    if (!orderRes.ok) {
      const err = await orderRes.json();
      throw new Error(err.error?.description || 'Razorpay order creation failed');
    }

    const order = await orderRes.json();

    // Save order to payments table
    await supabase.from('payments').insert({
      booking_id,
      user_id: user.id,
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
    }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
});
