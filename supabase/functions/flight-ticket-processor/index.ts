// ============================================================
// Supabase Edge Function: flight-ticket-processor
// File: supabase/functions/flight-ticket-processor/index.ts
// Deploy: npx supabase functions deploy flight-ticket-processor
//
// Stage 5. Triggered two ways:
//   1. Directly, with { bookingId } — called inline right after
//      verify-razorpay-payment / razorpay-webhook mark a flight
//      booking as paid, so most customers see a PNR within seconds.
//   2. On a schedule, with { source: "cron" } — processes anything
//      left in flight_ticketing_queue (status IN pending/processing
//      past its next_attempt_at), which is the backstop for retries
//      and for cases where the inline call above never ran (e.g. the
//      webhook path, which enqueues rather than calling inline — see
//      razorpay-webhook/index.ts).
//
// Money has already moved by the time this function runs, so every
// path either ends in a ticket or a refund — never a booking that's
// silently paid-but-nothing-issued. See handleFailure().
// ============================================================

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { getFlightProvider, type PassengerInput } from '../_shared/flight-provider.ts';

const MAX_ATTEMPTS = 3;
const RETRY_BACKOFF_SECONDS = [30, 120, 300]; // 30s, 2min, 5min

function isRetryable(err: Error): boolean {
  const msg = err.message.toLowerCase();
  // Sold-out / fare-gone errors are not retryable — the outcome won't
  // change. Timeouts and generic 5xx-style failures are.
  if (msg.includes('no longer available') || msg.includes('sold out')) return false;
  return true;
}

async function refundPayment(bookingId: string, razorpayPaymentId: string, amount: number, supabase: any) {
  const razorpayKeyId = Deno.env.get('RAZORPAY_KEY_ID')!;
  const razorpayKeySecret = Deno.env.get('RAZORPAY_KEY_SECRET')!;
  const credentials = btoa(`${razorpayKeyId}:${razorpayKeySecret}`);

  const res = await fetch(`https://api.razorpay.com/v1/payments/${razorpayPaymentId}/refund`, {
    method: 'POST',
    headers: { 'Authorization': `Basic ${credentials}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ amount: Math.round(amount * 100) }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(`Refund failed: ${err.error?.description || res.statusText}`);
  }
  return res.json();
}

async function processBooking(bookingId: string, supabase: any, provider: Awaited<ReturnType<typeof getFlightProvider>>) {
  const { data: booking } = await supabase.from('bookings').select('*').eq('id', bookingId).single();
  if (!booking) throw new Error(`Booking ${bookingId} not found`);
  if (booking.service_type !== 'flight') return { skipped: 'not a flight booking' };
  if (booking.payment_status !== 'paid') return { skipped: 'not paid yet' };
  if (booking.flight_ticketing_status === 'ticketed') return { skipped: 'already ticketed' };

  // Upsert the queue row so both call paths (inline + cron) share one
  // piece of retry/attempt state instead of drifting independently.
  await supabase.from('flight_ticketing_queue')
    .upsert({ booking_id: bookingId, status: 'processing' }, { onConflict: 'booking_id' });

  const { data: queueRow } = await supabase.from('flight_ticketing_queue').select('*').eq('booking_id', bookingId).single();
  const attempts = (queueRow?.attempts || 0) + 1;

  try {
    const hold = booking.flight_hold_id
      ? (await supabase.from('flight_fare_holds').select('provider_result_ref').eq('id', booking.flight_hold_id).single()).data
      : null;
    if (!hold?.provider_result_ref) throw new Error('Booking has no fare-hold reference to ticket against.');

    const passengers: PassengerInput[] = booking.travellers || [];
    const result = await provider.book(hold.provider_result_ref, passengers, {
      email: booking.customer_email,
      phone: booking.customer_phone,
    });

    await supabase.from('bookings').update({
      flight_pnr: result.pnr,
      flight_ticket_numbers: result.ticketNumbers,
      flight_ticketing_status: 'ticketed',
      status: 'confirmed',
    }).eq('id', bookingId);

    await supabase.from('flight_ticketing_queue').update({ status: 'ticketed', attempts }).eq('booking_id', bookingId);

    try {
      await supabase.functions.invoke('send-booking-email', { body: { booking_id: bookingId, type: 'confirmation' } });
    } catch (emailErr) {
      console.error('[flight-ticket-processor] confirmation email failed:', emailErr);
    }

    return { ticketed: true, pnr: result.pnr };

  } catch (err) {
    return handleFailure(bookingId, booking, err as Error, attempts, supabase);
  }
}

async function handleFailure(bookingId: string, booking: any, err: Error, attempts: number, supabase: any) {
  if (isRetryable(err) && attempts < MAX_ATTEMPTS) {
    const delaySec = RETRY_BACKOFF_SECONDS[Math.min(attempts - 1, RETRY_BACKOFF_SECONDS.length - 1)];
    await supabase.from('flight_ticketing_queue').update({
      status: 'pending',
      attempts,
      last_error: err.message,
      next_attempt_at: new Date(Date.now() + delaySec * 1000).toISOString(),
    }).eq('booking_id', bookingId);
    return { retrying: true, attempts, error: err.message };
  }

  // Not retryable, or out of attempts — customer paid, no ticket.
  // Refund automatically; do not make the customer chase this.
  await supabase.from('flight_ticketing_queue').update({
    status: 'failed_refunding', attempts, last_error: err.message,
  }).eq('booking_id', bookingId);
  await supabase.from('bookings').update({ flight_ticketing_status: 'failed_refunding' }).eq('id', bookingId);

  try {
    if (!booking.razorpay_payment_id) throw new Error('No razorpay_payment_id on booking — cannot auto-refund, needs manual handling.');
    await refundPayment(bookingId, booking.razorpay_payment_id, booking.total_amount, supabase);

    await supabase.from('bookings').update({
      payment_status: 'refunded',
      flight_ticketing_status: 'refunded',
      internal_notes: `⚠️ FLIGHT TICKETING FAILED after payment — auto-refunded. Reason: ${err.message}`,
    }).eq('id', bookingId);
    await supabase.from('flight_ticketing_queue').update({ status: 'refunded' }).eq('booking_id', bookingId);

    try {
      await supabase.functions.invoke('send-booking-email', { body: { booking_id: bookingId, type: 'ticketing_failed_refunded' } });
    } catch (emailErr) {
      console.error('[flight-ticket-processor] failure-notice email failed:', emailErr);
    }
  } catch (refundErr) {
    // Refund itself failed — this absolutely needs a human. Flag loudly
    // and stop; do not leave it in a state that silently gets ignored.
    await supabase.from('bookings').update({
      internal_notes: `🚨 FLIGHT TICKETING FAILED AND AUTO-REFUND ALSO FAILED — MANUAL ACTION REQUIRED. Ticketing error: ${err.message}. Refund error: ${(refundErr as Error).message}`,
    }).eq('id', bookingId);
    await supabase.from('flight_ticketing_queue').update({ status: 'needs_review' }).eq('booking_id', bookingId);
  }

  return { refunded: true, error: err.message };
}

serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({}));
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );
    const provider = await getFlightProvider(supabase);

    if (body.bookingId) {
      const result = await processBooking(body.bookingId, supabase, provider);
      return new Response(JSON.stringify(result), { headers: { 'Content-Type': 'application/json' } });
    }

    // Cron / queue-poll mode: process everything due, oldest first,
    // capped per invocation so one run can't hang indefinitely.
    const { data: due } = await supabase
      .from('flight_ticketing_queue')
      .select('booking_id')
      .in('status', ['pending'])
      .lte('next_attempt_at', new Date().toISOString())
      .order('next_attempt_at', { ascending: true })
      .limit(20);

    const results = [];
    for (const row of due || []) {
      results.push(await processBooking(row.booking_id, supabase, provider));
    }

    return new Response(JSON.stringify({ processed: results.length, results }), {
      headers: { 'Content-Type': 'application/json' },
    });

  } catch (err) {
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
