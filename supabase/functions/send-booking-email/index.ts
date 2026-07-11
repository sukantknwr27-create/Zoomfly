// ============================================================
// Supabase Edge Function: send-booking-email
// File: supabase/functions/send-booking-email/index.ts
// Deploy: npx supabase functions deploy send-booking-email
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

// Minimal HTML-escaping for any freeform text a customer typed
// (name, message, etc.) before it's interpolated into an email we
// send from our own verified domain. Not a DOM, so not "XSS" in the
// browser sense, but unescaped freeform text in outbound HTML mail is
// still a real injection vector (arbitrary links/markup in mail sent
// from ZoomFly's domain).
function esc(v: unknown): string {
  return String(v ?? '').replace(/[&<>"']/g, c => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c] as string
  ));
}
async function sendEmail({ to, subject, html }: { to: string; subject: string; html: string }) {
  const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')!;
  const FROM_EMAIL     = Deno.env.get('FROM_EMAIL') || 'hello@zoomfly.in';
  const ADMIN_EMAIL    = Deno.env.get('ADMIN_EMAIL') || 'admin@zoomfly.in';

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: `ZoomFly <${FROM_EMAIL}>`, to, subject, html }),
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Email send failed: ${err}`);
  }
  return res.json();
}

function bookingConfirmationHtml(booking: any) {
  return `
  <!DOCTYPE html>
  <html>
  <head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
  <body style="margin:0;padding:0;background:#F9FAFB;font-family:'Segoe UI',system-ui,sans-serif">
    <div style="max-width:600px;margin:40px auto;background:white;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,0.08)">
      <!-- Header -->
      <div style="background:linear-gradient(135deg,#0057FF,#003BB5);padding:32px;text-align:center;color:white">
        <h1 style="margin:0;font-size:28px;font-weight:900;letter-spacing:-0.5px">ZoomFly ✈</h1>
        <p style="margin:8px 0 0;opacity:0.85;font-size:14px">India's Trusted Travel Partner</p>
      </div>
      <!-- Success Banner -->
      <div style="background:#ECFDF5;padding:24px;text-align:center;border-bottom:1px solid #D1FAE5">
        <div style="font-size:48px;margin-bottom:8px">🎉</div>
        <h2 style="margin:0;color:#059669;font-size:20px">Booking Confirmed!</h2>
        <p style="margin:8px 0 0;color:#065F46;font-size:14px">Your adventure is officially booked.</p>
      </div>
      <!-- Booking Ref -->
      <div style="padding:24px;text-align:center;background:#EEF3FF">
        <p style="margin:0;font-size:12px;color:#6B7280;text-transform:uppercase;letter-spacing:0.08em">Booking Reference</p>
        <p style="margin:8px 0 0;font-size:24px;font-weight:900;color:#0057FF;letter-spacing:0.1em;font-family:monospace">${esc(booking.booking_ref)}</p>
        <p style="margin:4px 0 0;font-size:12px;color:#9CA3AF">Keep this for your records</p>
      </div>
      <!-- Details -->
      <div style="padding:24px 32px">
        <h3 style="margin:0 0 16px;font-size:16px;color:#111827">Booking Details</h3>
        <table style="width:100%;border-collapse:collapse">
          <tr style="border-bottom:1px solid #F3F4F6"><td style="padding:10px 0;font-size:13px;color:#6B7280;width:40%">Guest Name</td><td style="padding:10px 0;font-size:13px;font-weight:600;color:#111827">${esc(booking.guest_name)}</td></tr>
          <tr style="border-bottom:1px solid #F3F4F6"><td style="padding:10px 0;font-size:13px;color:#6B7280">Email</td><td style="padding:10px 0;font-size:13px;font-weight:600;color:#111827">${esc(booking.guest_email)}</td></tr>
          <tr style="border-bottom:1px solid #F3F4F6"><td style="padding:10px 0;font-size:13px;color:#6B7280">Booking Type</td><td style="padding:10px 0;font-size:13px;font-weight:600;color:#111827;text-transform:capitalize">${esc(booking.booking_type)}</td></tr>
          ${booking.travel_date ? `<tr style="border-bottom:1px solid #F3F4F6"><td style="padding:10px 0;font-size:13px;color:#6B7280">Travel Date</td><td style="padding:10px 0;font-size:13px;font-weight:600;color:#111827">${new Date(booking.travel_date).toLocaleDateString('en-IN',{day:'numeric',month:'long',year:'numeric'})}</td></tr>` : ''}
          ${booking.checkin_date ? `<tr style="border-bottom:1px solid #F3F4F6"><td style="padding:10px 0;font-size:13px;color:#6B7280">Check-in</td><td style="padding:10px 0;font-size:13px;font-weight:600;color:#111827">${new Date(booking.checkin_date).toLocaleDateString('en-IN',{day:'numeric',month:'long',year:'numeric'})}</td></tr>` : ''}
          ${booking.checkout_date ? `<tr style="border-bottom:1px solid #F3F4F6"><td style="padding:10px 0;font-size:13px;color:#6B7280">Check-out</td><td style="padding:10px 0;font-size:13px;font-weight:600;color:#111827">${new Date(booking.checkout_date).toLocaleDateString('en-IN',{day:'numeric',month:'long',year:'numeric'})}</td></tr>` : ''}
          <tr style="border-bottom:1px solid #F3F4F6"><td style="padding:10px 0;font-size:13px;color:#6B7280">Guests</td><td style="padding:10px 0;font-size:13px;font-weight:600;color:#111827">${booking.num_guests}</td></tr>
          <tr style="background:#F9FAFB"><td style="padding:12px 0;font-size:14px;font-weight:700;color:#111827">Amount Paid</td><td style="padding:12px 0;font-size:18px;font-weight:900;color:#0057FF">₹${Number(booking.total_amount).toLocaleString('en-IN')}</td></tr>
        </table>
      </div>
      <!-- Support -->
      <div style="padding:20px 32px;background:#F9FAFB;border-top:1px solid #E5E7EB">
        <p style="margin:0;font-size:13px;color:#6B7280;text-align:center">Need help? WhatsApp us at <strong style="color:#111827">+91 80761 36300</strong> or email <a href="mailto:hello@zoomfly.in" style="color:#0057FF">hello@zoomfly.in</a></p>
      </div>
      <!-- Footer -->
      <div style="padding:16px;background:#0f172a;text-align:center">
        <p style="margin:0;font-size:12px;color:#94a3b8">© 2025 ZoomFly · Connaught Place, New Delhi · <a href="https://zoomfly-virid.vercel.app" style="color:#60a5fa">zoomfly.in</a></p>
      </div>
    </div>
  </body>
  </html>`;
}

function enquiryAlertHtml(enquiry: any) {
  return `
  <!DOCTYPE html><html><body style="font-family:'Segoe UI',system-ui,sans-serif;background:#F9FAFB;margin:0;padding:40px 0">
  <div style="max-width:560px;margin:0 auto;background:white;border-radius:12px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.07)">
    <div style="background:#FF6B35;padding:20px 24px;color:white">
      <h2 style="margin:0;font-size:18px">🔔 New Enquiry — ZoomFly</h2>
    </div>
    <div style="padding:24px">
      <table style="width:100%;border-collapse:collapse">
        <tr><td style="padding:8px 0;font-size:13px;color:#6B7280;width:35%">Name</td><td style="font-size:13px;font-weight:600">${esc(enquiry.name)}</td></tr>
        <tr><td style="padding:8px 0;font-size:13px;color:#6B7280">Phone</td><td style="font-size:13px;font-weight:600"><a href="tel:${esc(enquiry.phone)}">${esc(enquiry.phone)}</a></td></tr>
        <tr><td style="padding:8px 0;font-size:13px;color:#6B7280">Email</td><td style="font-size:13px;font-weight:600"><a href="mailto:${esc(enquiry.email)}">${esc(enquiry.email)}</a></td></tr>
        <tr><td style="padding:8px 0;font-size:13px;color:#6B7280">Interested In</td><td style="font-size:13px;font-weight:600">${esc(enquiry.interest?.join(', '))}</td></tr>
        <tr><td style="padding:8px 0;font-size:13px;color:#6B7280">Destination</td><td style="font-size:13px;font-weight:600">${esc(enquiry.destination || '—')}</td></tr>
        <tr><td style="padding:8px 0;font-size:13px;color:#6B7280">Travel Date</td><td style="font-size:13px;font-weight:600">${esc(enquiry.travel_date || '—')}</td></tr>
        <tr><td style="padding:8px 0;font-size:13px;color:#6B7280">Travellers</td><td style="font-size:13px;font-weight:600">${esc(enquiry.travellers || '—')}</td></tr>
        <tr><td style="padding:8px 0;font-size:13px;color:#6B7280">Budget</td><td style="font-size:13px;font-weight:600">${esc(enquiry.budget || '—')}</td></tr>
        <tr><td style="padding:8px 0;font-size:13px;color:#6B7280">Message</td><td style="font-size:13px">${esc(enquiry.message || '—')}</td></tr>
        <tr><td style="padding:8px 0;font-size:13px;color:#6B7280">Received</td><td style="font-size:13px">${new Date().toLocaleString('en-IN')}</td></tr>
      </table>
    </div>
    <div style="padding:16px 24px;background:#F9FAFB;border-top:1px solid #E5E7EB;text-align:center">
      <a href="https://zoomfly-virid.vercel.app/pages/admin.html" style="display:inline-block;padding:10px 24px;background:#0057FF;color:white;border-radius:8px;font-weight:700;font-size:13px;text-decoration:none">Open Admin Dashboard →</a>
    </div>
  </div>
  </body></html>`;
}

function enquiryAckHtml(enquiry: any) {
  return `
  <!DOCTYPE html><html><body style="font-family:'Segoe UI',system-ui,sans-serif;background:#F9FAFB;margin:0;padding:40px 0">
  <div style="max-width:560px;margin:0 auto;background:white;border-radius:12px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.07)">
    <div style="background:linear-gradient(135deg,#0057FF,#003BB5);padding:28px;text-align:center;color:white">
      <h1 style="margin:0;font-size:24px;font-weight:900">ZoomFly ✈</h1>
    </div>
    <div style="padding:32px;text-align:center">
      <div style="font-size:48px;margin-bottom:12px">📩</div>
      <h2 style="margin:0 0 12px;font-size:20px;color:#111827">We've received your enquiry!</h2>
      <p style="margin:0 0 24px;color:#6B7280;font-size:14px;line-height:1.7">Hi <strong>${esc(enquiry.name)}</strong>, thank you for reaching out. Our travel expert will contact you within <strong>2 hours</strong> with a personalised quote.</p>
      <div style="background:#EEF3FF;border-radius:8px;padding:16px;margin-bottom:24px;text-align:left">
        <p style="margin:0 0 6px;font-size:13px;color:#6B7280">Your enquiry summary:</p>
        <p style="margin:0;font-size:13px;font-weight:600;color:#111827">📍 ${esc(enquiry.destination || 'Custom trip')} · ${esc(enquiry.travellers || '')} · ${esc(enquiry.budget || 'Flexible budget')}</p>
      </div>
      <a href="https://wa.me/918076136300?text=Hi!+I+just+submitted+an+enquiry+for+${encodeURIComponent(enquiry.destination || 'a trip')}" style="display:inline-block;padding:12px 28px;background:#25D366;color:white;border-radius:50px;font-weight:700;font-size:14px;text-decoration:none">💬 WhatsApp Us Now</a>
    </div>
    <div style="padding:16px 24px;background:#0f172a;text-align:center">
      <p style="margin:0;font-size:12px;color:#94a3b8">© 2025 ZoomFly · hello@zoomfly.in · +91 80761 36300</p>
    </div>
  </div>
  </body></html>`;
}

// ── RATE LIMITER ─────────────────────────────────────────────
// Simple in-memory sliding-window rate limit per IP.
// Deno isolates are recycled by Supabase, so this resets periodically —
// suitable as a first-line abuse guard, not a hard quota.
const _rateWindows = new Map<string, number[]>();
const RATE_LIMIT_MAX      = 10;   // max calls per window
const RATE_LIMIT_WINDOW   = 60_000; // 60 seconds

function isRateLimited(ip: string): boolean {
  const now = Date.now();
  const calls = (_rateWindows.get(ip) || []).filter(t => now - t < RATE_LIMIT_WINDOW);
  calls.push(now);
  _rateWindows.set(ip, calls);
  return calls.length > RATE_LIMIT_MAX;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });

  // Rate limit by IP
  const ip = req.headers.get('x-forwarded-for')?.split(',')[0].trim() || 'unknown';
  if (isRateLimited(ip)) {
    return new Response(JSON.stringify({ error: 'Too many requests. Please try again later.' }), {
      status: 429,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json', 'Retry-After': '60' },
    });
  }

  try {
    const { type, booking_id, enquiry_id } = await req.json();
    const ADMIN_EMAIL = Deno.env.get('ADMIN_EMAIL') || 'admin@zoomfly.in';

    // ── CRITICAL: this function used to accept a full `booking`/
    // `enquiry` object straight from the request body and email it
    // verbatim — no auth, no check that it referred to anything real.
    // That meant anyone who found this function's URL (visible in any
    // browser network tab on the site) could send an arbitrarily
    // worded, ZoomFly-branded email to any address in the world, at
    // this Resend account's expense — an open, unauthenticated
    // phishing relay riding on a verified sending domain. Fixed by
    // only ever accepting an ID and fetching the real row ourselves;
    // the recipient and every field in the email now comes from the
    // database, never from the caller.
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    if (type === 'confirmation' && booking_id) {
      const { data: booking, error } = await supabase
        .from('bookings').select('*').eq('id', booking_id).single();
      if (error || !booking) throw new Error('Booking not found.');
      // Only ever send a "confirmed" email for a booking that is
      // actually paid — this function is a notifier, not a source of
      // truth, and must not be usable to manufacture a confirmation.
      if (booking.payment_status !== 'paid') {
        throw new Error('Booking is not marked paid — refusing to send a confirmation email.');
      }
      const recipient = booking.guest_email || booking.customer_email;
      if (!recipient) throw new Error('Booking has no email on file.');

      await Promise.all([
        sendEmail({
          to: recipient,
          subject: `✈ Booking Confirmed — ${esc(booking.booking_ref)} | ZoomFly`,
          html: bookingConfirmationHtml(booking)
        }),
        sendEmail({
          to: ADMIN_EMAIL,
          subject: `💰 New Booking ${esc(booking.booking_ref)} — ₹${Number(booking.total_amount).toLocaleString('en-IN')}`,
          html: bookingConfirmationHtml(booking)
        })
      ]);
    }

    if (type === 'enquiry' && enquiry_id) {
      const { data: enquiry, error } = await supabase
        .from('enquiries').select('*').eq('id', enquiry_id).single();
      if (error || !enquiry) throw new Error('Enquiry not found.');
      const recipient = enquiry.email || enquiry.guest_email;
      if (!recipient) throw new Error('Enquiry has no email on file.');

      await Promise.all([
        sendEmail({
          to: ADMIN_EMAIL,
          subject: `🔔 New Enquiry from ${esc(enquiry.name)} — ${enquiry.destination || enquiry.interest?.[0] || 'ZoomFly'}`,
          html: enquiryAlertHtml(enquiry)
        }),
        sendEmail({
          to: recipient,
          subject: '✅ We received your enquiry — ZoomFly will call you within 2 hours',
          html: enquiryAckHtml(enquiry)
        })
      ]);
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' }
    });

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 400,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' }
    });
  }
});
