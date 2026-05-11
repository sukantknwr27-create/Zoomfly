// ============================================================
//  ZOOMFLY — EMAIL CONFIRMATION SYSTEM
//  
//  FILE 1: supabase/functions/send-booking-email/index.ts
//  Supabase Edge Function — triggered on every new booking
//
//  Sends:
//    → Customer: beautiful HTML booking confirmation
//    → Admin:    alert email with full booking details
//
//  Setup:
//    1. supabase functions deploy send-booking-email
//    2. Set secrets (see bottom of this file)
//    3. Create DB trigger to call this function
// ============================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const RESEND_API_KEY  = Deno.env.get('RESEND_API_KEY')  ?? '';
const SUPABASE_URL    = Deno.env.get('SUPABASE_URL')    ?? '';
const SUPABASE_KEY    = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const FROM_EMAIL      = 'bookings@zoomfly.in';
const FROM_NAME       = 'ZoomFly Bookings';
const ADMIN_EMAIL     = 's.admin@zoomfly.in';
const SITE_URL        = 'https://zoomfly.in';

serve(async (req) => {
  try {
    // ── Parse request ──
    const body = await req.json();

    // Called directly OR via DB webhook
    const booking = body.record ?? body.booking ?? body;
    if (!booking?.id) {
      return new Response(JSON.stringify({ error: 'No booking data' }), { status: 400 });
    }

    // ── Fetch full booking from DB (in case webhook only sends partial) ──
    const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);
    const { data: b, error } = await supabase
      .from('bookings')
      .select('*')
      .eq('id', booking.id)
      .single();

    if (error || !b) {
      return new Response(JSON.stringify({ error: 'Booking not found' }), { status: 404 });
    }

    // ── Send both emails in parallel ──
    const [customerResult, adminResult] = await Promise.allSettled([
      sendEmail({
        to:      b.customer_email,
        subject: `Booking Confirmed — ${b.booking_ref} | ZoomFly`,
        html:    buildCustomerEmail(b),
      }),
      sendEmail({
        to:      ADMIN_EMAIL,
        subject: `🔔 New Booking — ${b.booking_ref} | ${typeLabel(b.service_type)}`,
        html:    buildAdminEmail(b),
      }),
    ]);

    // ── Mark confirmation sent in DB ──
    await supabase
      .from('bookings')
      .update({
        confirmation_sent: true,
        last_notified_at:  new Date().toISOString(),
      })
      .eq('id', b.id);

    return new Response(JSON.stringify({
      success: true,
      customer: customerResult.status,
      admin:    adminResult.status,
    }), {
      status:  200,
      headers: { 'Content-Type': 'application/json' },
    });

  } catch (err) {
    console.error('[send-booking-email]', err);
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});


// ============================================================
//  RESEND API CALLER
// ============================================================
async function sendEmail({ to, subject, html }: {
  to: string; subject: string; html: string;
}) {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${RESEND_API_KEY}`,
      'Content-Type':  'application/json',
    },
    body: JSON.stringify({
      from:    `${FROM_NAME} <${FROM_EMAIL}>`,
      to:      [to],
      subject,
      html,
    }),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Resend error: ${err}`);
  }
  return res.json();
}


// ============================================================
//  CUSTOMER EMAIL TEMPLATE
// ============================================================
function buildCustomerEmail(b: any): string {
  const td     = b.travel_details ?? {};
  const body   = buildCustomerEmailBody(b.service_type, b, td);
  const amount = fmtAmt(b.total_amount);

  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>Booking Confirmation — ZoomFly</title>
  <style>
    * { margin:0; padding:0; box-sizing:border-box; }
    body { font-family: -apple-system, 'DM Sans', Arial, sans-serif;
           background:#f8fafc; color:#2d3748; line-height:1.6; }
    .wrapper  { max-width:620px; margin:0 auto; padding:32px 16px; }
    .card     { background:#ffffff; border-radius:20px; overflow:hidden;
                box-shadow:0 4px 32px rgba(0,0,0,0.08); }

    /* Header */
    .email-header {
      background:linear-gradient(135deg, #0f1923 0%, #1a2535 60%, #1a3a5c 100%);
      padding:40px 36px 32px;
      text-align:center;
      position:relative;
    }
    .logo-row  { display:flex; align-items:center; justify-content:center;
                 gap:10px; margin-bottom:28px; }
    .logo-icon { width:44px; height:44px;
                 background:linear-gradient(135deg,#1a73e8,#ff6b35);
                 border-radius:12px; display:flex; align-items:center;
                 justify-content:center; font-size:22px; }
    .logo-text { font-size:1.6rem; font-weight:700; color:#ffffff;
                 letter-spacing:-0.5px; }
    .logo-text span { color:#ff6b35; }

    .success-icon { width:72px; height:72px;
      background:linear-gradient(135deg,#22c55e,#16a34a);
      border-radius:50%; display:flex; align-items:center; justify-content:center;
      font-size:32px; margin:0 auto 16px;
      box-shadow:0 8px 24px rgba(34,197,94,0.4); }
    .email-header h1 { font-size:1.5rem; color:#ffffff;
                       font-weight:700; margin-bottom:8px; }
    .email-header p  { color:rgba(255,255,255,0.65); font-size:0.88rem; }

    /* Ref box */
    .ref-box { background:#f8fafc; border:2px dashed #cbd5e1;
               border-radius:12px; padding:20px; text-align:center;
               margin:28px 28px 0; }
    .ref-label { font-size:0.72rem; font-weight:700; text-transform:uppercase;
                 letter-spacing:1.5px; color:#94a3b8; margin-bottom:6px; }
    .ref-code  { font-size:1.5rem; font-weight:700; color:#1a73e8;
                 letter-spacing:2px; font-family:monospace; }
    .ref-sub   { font-size:0.78rem; color:#94a3b8; margin-top:4px; }

    /* Body */
    .email-body { padding:28px 28px 24px; }
    .section-label { font-size:0.72rem; font-weight:700; text-transform:uppercase;
                     letter-spacing:1.5px; color:#94a3b8; margin-bottom:14px; }

    /* Detail table */
    .detail-table { width:100%; border-collapse:collapse; margin-bottom:24px; }
    .detail-table tr { border-bottom:1px solid #f1f5f9; }
    .detail-table tr:last-child { border-bottom:none; }
    .detail-table td { padding:10px 0; font-size:0.88rem; vertical-align:top; }
    .detail-table td:first-child { color:#64748b; width:40%; }
    .detail-table td:last-child  { font-weight:600; color:#2d3748; text-align:right; }

    /* Price box */
    .price-box { background:linear-gradient(135deg,#f8fafc,#eff6ff);
                 border:1px solid #dbeafe; border-radius:12px;
                 padding:20px; margin-bottom:24px; }
    .price-row { display:flex; justify-content:space-between;
                 font-size:0.88rem; padding:6px 0; }
    .price-row.total { border-top:1px solid #dbeafe; margin-top:8px;
                       padding-top:12px; }
    .price-row.total span:first-child { font-weight:700; font-size:0.95rem; color:#1a2535; }
    .price-row.total span:last-child  { font-weight:800; font-size:1.1rem; color:#ff6b35; }

    /* Timeline */
    .timeline { margin-bottom:24px; }
    .tl-item  { display:flex; gap:14px; margin-bottom:14px; align-items:flex-start; }
    .tl-dot   { width:32px; height:32px; border-radius:50%; display:flex;
                align-items:center; justify-content:center;
                font-size:14px; flex-shrink:0; }
    .tl-done  { background:#dcfce7; color:#16a34a; }
    .tl-now   { background:#dbeafe; color:#1a73e8; }
    .tl-wait  { background:#f1f5f9; color:#94a3b8; border:2px solid #e2e8f0; }
    .tl-text  .tl-title { font-size:0.88rem; font-weight:700; color:#1a2535; }
    .tl-text  .tl-sub   { font-size:0.78rem; color:#94a3b8; margin-top:2px; }

    /* CTA */
    .cta-block { text-align:center; padding:8px 0 8px; margin-bottom:24px; }
    .cta-btn   { display:inline-block; background:linear-gradient(135deg,#25d366,#128c7e);
                 color:#ffffff; padding:14px 32px; border-radius:12px;
                 text-decoration:none; font-weight:700; font-size:0.92rem;
                 box-shadow:0 4px 16px rgba(37,211,102,0.35); }

    /* Divider */
    .divider { height:1px; background:#f1f5f9; margin:0 0 24px; }

    /* Help */
    .help-box { background:#f8fafc; border-radius:12px; padding:20px;
                border:1px solid #e2e8f0; margin-bottom:8px; }
    .help-box p { font-size:0.85rem; color:#64748b; line-height:1.6; }
    .help-box strong { color:#2d3748; }

    /* Footer */
    .email-footer { background:#0f1923; padding:24px 28px; text-align:center; }
    .footer-links a { color:rgba(255,255,255,0.5); text-decoration:none;
                      font-size:0.78rem; margin:0 8px; }
    .footer-links a:hover { color:#ff6b35; }
    .footer-copy { color:rgba(255,255,255,0.3); font-size:0.75rem; margin-top:12px; }
  </style>
</head>
<body>
<div class="wrapper">
  <div class="card">

    <!-- HEADER -->
    <div class="email-header">
      <div class="logo-row">
        <div class="logo-icon">✈️</div>
        <div class="logo-text">Zoom<span>Fly</span></div>
      </div>
      <div class="success-icon">✅</div>
      <h1>Booking Request Received!</h1>
      <p>Hi ${esc(b.customer_name)}, your booking has been submitted.<br/>
         We'll confirm within <strong style="color:#fff">30 minutes</strong>.</p>
    </div>

    <!-- BOOKING REF -->
    <div class="ref-box">
      <div class="ref-label">Your Booking Reference</div>
      <div class="ref-code">${esc(b.booking_ref)}</div>
      <div class="ref-sub">Save this number to track your booking anytime</div>
    </div>

    <!-- BODY -->
    <div class="email-body">

      <!-- Service summary -->
      <div class="section-label">Booking Summary</div>
      <table class="detail-table">
        <tr><td>Service</td><td>${esc(b.service_name)}</td></tr>
        ${body.rows}
        <tr><td>Travellers</td><td>${b.num_adults} Adult${b.num_adults>1?'s':''}${b.num_children>0?`, ${b.num_children} Child`:''}${b.num_infants>0?`, ${b.num_infants} Infant`:''}</td></tr>
        <tr><td>Booking Date</td><td>${fmtDate(b.created_at)}</td></tr>
        <tr><td>Status</td><td><span style="background:#fef9c3;color:#854d0e;
          padding:3px 10px;border-radius:20px;font-size:0.78rem;font-weight:700;">
          ⏳ Pending Confirmation</span></td></tr>
      </table>

      <!-- Price -->
      <div class="section-label">Price Breakdown</div>
      <div class="price-box">
        <div class="price-row">
          <span>Base Amount</span><span>₹${fmtAmt(b.base_amount)}</span>
        </div>
        <div class="price-row">
          <span>Taxes & Fees</span><span>₹${fmtAmt(b.tax_amount)}</span>
        </div>
        ${b.discount_amount > 0 ? `
        <div class="price-row" style="color:#16a34a">
          <span>Discount${b.promo_code ? ` (${esc(b.promo_code)})` : ''}</span>
          <span>-₹${fmtAmt(b.discount_amount)}</span>
        </div>` : ''}
        <div class="price-row total">
          <span>Total Amount</span><span>₹${fmtAmt(b.total_amount)}</span>
        </div>
      </div>

      <!-- Timeline -->
      <div class="section-label">What Happens Next</div>
      <div class="timeline">
        <div class="tl-item">
          <div class="tl-dot tl-done">✓</div>
          <div class="tl-text">
            <div class="tl-title">Booking Request Submitted</div>
            <div class="tl-sub">Your details are saved and our team has been notified</div>
          </div>
        </div>
        <div class="tl-item">
          <div class="tl-dot tl-now">⏳</div>
          <div class="tl-text">
            <div class="tl-title">Confirmation (within 30 mins)</div>
            <div class="tl-sub">We'll confirm availability and send you details via WhatsApp</div>
          </div>
        </div>
        <div class="tl-item">
          <div class="tl-dot tl-wait">💳</div>
          <div class="tl-text">
            <div class="tl-title">Payment</div>
            <div class="tl-sub">Complete payment to lock your booking</div>
          </div>
        </div>
        <div class="tl-item">
          <div class="tl-dot tl-wait">🎫</div>
          <div class="tl-text">
            <div class="tl-title">e-Ticket / Voucher</div>
            <div class="tl-sub">Receive your travel documents via email and WhatsApp</div>
          </div>
        </div>
      </div>

      <!-- WhatsApp CTA -->
      <div class="cta-block">
        <a href="https://wa.me/918076136300?text=Hi%20ZoomFly!%20My%20booking%20ref%20is%20${esc(b.booking_ref)}"
           class="cta-btn">
          💬 Chat with Us on WhatsApp
        </a>
      </div>

      <div class="divider"></div>

      <!-- Help -->
      <div class="help-box">
        <p>
          <strong>Need help?</strong> Contact our team:<br/>
          📞 <strong>+91 8076136300</strong> (WhatsApp / Call)<br/>
          📧 <strong>${ADMIN_EMAIL}</strong><br/>
          🕘 Mon–Sat · 9 AM – 9 PM IST
        </p>
      </div>

    </div><!-- /email-body -->

    <!-- FOOTER -->
    <div class="email-footer">
      <div class="footer-links">
        <a href="${SITE_URL}">Home</a>
        <a href="${SITE_URL}/privacy-policy.html">Privacy Policy</a>
        <a href="${SITE_URL}/terms.html">Terms</a>
        <a href="${SITE_URL}/refund-policy.html">Refund Policy</a>
        <a href="${SITE_URL}/contact.html">Contact</a>
      </div>
      <div class="footer-copy">
        © 2026 ZoomFly Travel Services · New Delhi, India<br/>
        You received this because you made a booking on zoomfly.in
      </div>
    </div>

  </div><!-- /card -->
</div><!-- /wrapper -->
</body>
</html>`;
}


// ============================================================
//  ADMIN EMAIL TEMPLATE
// ============================================================
function buildAdminEmail(b: any): string {
  const td      = b.travel_details ?? {};
  const urgency = getUrgency(td);

  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>New Booking Alert</title>
  <style>
    *{margin:0;padding:0;box-sizing:border-box;}
    body{font-family:-apple-system,Arial,sans-serif;background:#f8fafc;color:#2d3748;line-height:1.6;}
    .wrapper{max-width:620px;margin:0 auto;padding:32px 16px;}
    .card{background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,0.08);}
    .ah{background:linear-gradient(135deg,#0f1923,#1a2535);padding:28px 28px 20px;}
    .ah-top{display:flex;align-items:center;gap:14px;margin-bottom:4px;}
    .ah-icon{width:48px;height:48px;background:#ff6b35;border-radius:12px;
      display:flex;align-items:center;justify-content:center;font-size:22px;flex-shrink:0;}
    .ah h1{font-size:1.2rem;color:#fff;font-weight:700;}
    .ah p{color:rgba(255,255,255,0.5);font-size:0.82rem;margin-top:2px;}
    .urgency{display:inline-block;padding:5px 14px;border-radius:20px;
      font-size:0.78rem;font-weight:700;margin-top:12px;}
    .u-red   {background:rgba(239,68,68,0.2);color:#fca5a5;}
    .u-orange{background:rgba(255,107,53,0.2);color:#fdba74;}
    .u-yellow{background:rgba(234,179,8,0.2); color:#fde047;}
    .u-green {background:rgba(34,197,94,0.2); color:#86efac;}

    .ab{padding:24px 28px;}
    .sec-label{font-size:0.7rem;font-weight:700;text-transform:uppercase;
      letter-spacing:1.5px;color:#94a3b8;margin-bottom:12px;padding-bottom:8px;
      border-bottom:1px solid #f1f5f9;}
    .info-grid{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:24px;}
    .info-item{}
    .info-item .il{font-size:0.72rem;font-weight:600;text-transform:uppercase;
      letter-spacing:1px;color:#94a3b8;margin-bottom:3px;}
    .info-item .iv{font-size:0.88rem;font-weight:600;color:#1a2535;}
    .info-item .iv a{color:#1a73e8;text-decoration:none;}

    .travel-box{background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;
      padding:16px;margin-bottom:20px;}
    .travel-row{display:flex;justify-content:space-between;padding:6px 0;
      font-size:0.85rem;border-bottom:1px solid #f1f5f9;}
    .travel-row:last-child{border-bottom:none;}
    .travel-row span:first-child{color:#64748b;}
    .travel-row span:last-child{font-weight:600;color:#1a2535;}

    .price-strip{background:linear-gradient(135deg,#ff6b35,#ea580c);
      border-radius:10px;padding:16px 20px;margin-bottom:20px;
      display:flex;align-items:center;justify-content:space-between;}
    .ps-label{color:rgba(255,255,255,0.8);font-size:0.82rem;}
    .ps-amount{font-size:1.4rem;font-weight:800;color:#fff;}

    .action-box{background:#f0fdf4;border:1px solid #bbf7d0;border-radius:10px;
      padding:16px;margin-bottom:20px;}
    .action-box p{font-size:0.85rem;color:#166534;font-weight:600;margin-bottom:8px;}
    .action-links{display:flex;gap:10px;flex-wrap:wrap;}
    .action-link{padding:7px 14px;border-radius:8px;text-decoration:none;
      font-size:0.8rem;font-weight:700;}
    .al-wa{background:#25d366;color:#fff;}
    .al-admin{background:#1a73e8;color:#fff;}

    .af{background:#0f1923;padding:16px 28px;text-align:center;}
    .af p{color:rgba(255,255,255,0.35);font-size:0.75rem;}
  </style>
</head>
<body>
<div class="wrapper">
<div class="card">

  <div class="ah">
    <div class="ah-top">
      <div class="ah-icon">🔔</div>
      <div>
        <h1>New Booking — Action Required</h1>
        <p>${typeLabel(b.service_type)} · ${esc(b.booking_ref)}</p>
      </div>
    </div>
    <span class="urgency ${urgency.cls}">${urgency.label}</span>
  </div>

  <div class="ab">

    <!-- Customer -->
    <div class="sec-label">Customer Details</div>
    <div class="info-grid">
      <div class="info-item">
        <div class="il">Name</div>
        <div class="iv">${esc(b.customer_name)}</div>
      </div>
      <div class="info-item">
        <div class="il">Phone</div>
        <div class="iv"><a href="tel:${esc(b.customer_phone)}">${esc(b.customer_phone)}</a></div>
      </div>
      <div class="info-item">
        <div class="il">Email</div>
        <div class="iv"><a href="mailto:${esc(b.customer_email)}">${esc(b.customer_email)}</a></div>
      </div>
      <div class="info-item">
        <div class="il">WhatsApp</div>
        <div class="iv">
          <a href="https://wa.me/${sanitizePhone(b.customer_whatsapp||b.customer_phone)}">
            ${esc(b.customer_whatsapp || b.customer_phone)}
          </a>
        </div>
      </div>
      <div class="info-item">
        <div class="il">Adults / Children</div>
        <div class="iv">${b.num_adults}A / ${b.num_children}C / ${b.num_infants}I</div>
      </div>
      <div class="info-item">
        <div class="il">Source</div>
        <div class="iv">${esc(b.booking_source || 'website')}</div>
      </div>
    </div>

    <!-- Travel Details -->
    <div class="sec-label">Travel Details</div>
    <div class="travel-box">
      ${buildAdminTravelRows(b.service_type, b.travel_details ?? {})}
      ${b.special_requests
        ? `<div class="travel-row"><span>Special Request</span><span>${esc(b.special_requests)}</span></div>`
        : ''}
    </div>

    <!-- Price -->
    <div class="price-strip">
      <div>
        <div class="ps-label">Total Booking Amount</div>
        <div class="ps-label" style="font-size:0.75rem;margin-top:2px;">
          Base ₹${fmtAmt(b.base_amount)} + Tax ₹${fmtAmt(b.tax_amount)}
          ${b.discount_amount > 0 ? ` - Disc ₹${fmtAmt(b.discount_amount)}` : ''}
          ${b.promo_code ? ` · Promo: ${esc(b.promo_code)}` : ''}
        </div>
      </div>
      <div class="ps-amount">₹${fmtAmt(b.total_amount)}</div>
    </div>

    <!-- Actions -->
    <div class="action-box">
      <p>⚡ Confirm with vendor and update customer within 30 minutes:</p>
      <div class="action-links">
        <a class="action-link al-wa"
           href="https://wa.me/${sanitizePhone(b.customer_whatsapp||b.customer_phone)}?text=Hi%20${encodeURIComponent(b.customer_name)}!%20Your%20ZoomFly%20booking%20${encodeURIComponent(b.booking_ref)}%20is%20confirmed.">
          💬 WhatsApp Customer
        </a>
        <a class="action-link al-admin" href="${SITE_URL}/admin.html">
          📊 Open Admin Panel
        </a>
      </div>
    </div>

  </div><!-- /ab -->

  <div class="af">
    <p>ZoomFly Admin Alert · ${fmtDateTime(b.created_at)} · ${esc(b.booking_ref)}</p>
  </div>

</div>
</div>
</body>
</html>`;
}


// ============================================================
//  TRAVEL DETAIL ROWS FOR ADMIN EMAIL
// ============================================================
function buildAdminTravelRows(type: string, td: any): string {
  const row = (k: string, v: string) =>
    `<div class="travel-row"><span>${k}</span><span>${esc(v||'—')}</span></div>`;

  switch (type) {
    case 'flight': return [
      row('Route',      `${td.from_city||td.from||'—'} (${td.from||''}) → ${td.to_city||td.to||'—'} (${td.to||''})`),
      row('Date',       fmtDate(td.date)),
      td.return_date ? row('Return', fmtDate(td.return_date)) : '',
      row('Trip Type',  td.trip_type||'one_way'),
      row('Cabin',      td.class||'economy'),
    ].join('');
    case 'hotel': return [
      row('Hotel',      `${td.hotel_name||'—'}, ${td.city||'—'}`),
      row('Check-in',   fmtDate(td.check_in)),
      row('Check-out',  fmtDate(td.check_out)),
      row('Nights',     String(td.nights||'—')),
      row('Room',       `${td.room_type||'Standard'} × ${td.num_rooms||1}`),
    ].join('');
    case 'package': return [
      row('Package',    td.package_name||'—'),
      row('Destination',td.destination||'—'),
      row('Travel Date',fmtDate(td.start_date)),
      td.end_date ? row('Return', fmtDate(td.end_date)) : '',
      row('Duration',   td.duration||'—'),
      row('Hotel Class',td.hotel_class||'—'),
    ].join('');
    case 'bus': return [
      row('Route',      `${td.from||'—'} → ${td.to||'—'}`),
      row('Date',       fmtDate(td.date)),
      row('Departure',  td.departure_time||'—'),
      row('Operator',   td.operator||'—'),
      row('Seats',      td.seat_numbers?.join(', ')||'—'),
    ].join('');
    case 'cab': return [
      row('Pickup',     td.from||'—'),
      row('Drop',       td.to||'—'),
      row('Date/Time',  `${fmtDate(td.pickup_date)} @ ${td.pickup_time||'—'}`),
      row('Cab Type',   td.cab_type||'Sedan'),
      row('Passengers', String(td.passengers||'—')),
    ].join('');
    default: return '';
  }
}


// ============================================================
//  EMAIL-SPECIFIC BODY ROWS (service summary for customer email)
// ============================================================
function buildCustomerEmailBody(type: string, b: any, td: any) {
  const row = (k: string, v: string) =>
    `<tr><td>${k}</td><td>${esc(v||'—')}</td></tr>`;

  switch (type) {
    case 'flight': return { rows: [
      row('Route',     `${td.from_city||td.from||'—'} → ${td.to_city||td.to||'—'}`),
      row('Date',      fmtDate(td.date)),
      td.return_date ? row('Return', fmtDate(td.return_date)) : '',
      row('Trip Type', td.trip_type === 'round_trip' ? 'Round Trip' : 'One Way'),
      row('Cabin',     capitalize(td.class||'Economy')),
    ].join('') };
    case 'hotel': return { rows: [
      row('Hotel',     `${td.hotel_name||'—'}, ${td.city||'—'}`),
      row('Check-in',  fmtDate(td.check_in)),
      row('Check-out', fmtDate(td.check_out)),
      row('Nights',    String(td.nights||calcNights(td.check_in,td.check_out))),
      row('Room',      `${td.room_type||'Standard'} × ${td.num_rooms||1}`),
    ].join('') };
    case 'package': return { rows: [
      row('Package',    td.package_name||'—'),
      row('Destination',td.destination||'—'),
      row('Travel Date',fmtDate(td.start_date)),
      td.end_date ? row('Return', fmtDate(td.end_date)) : '',
      row('Duration',   td.duration||'—'),
    ].join('') };
    case 'bus': return { rows: [
      row('Route',    `${td.from||'—'} → ${td.to||'—'}`),
      row('Date',     fmtDate(td.date)),
      row('Departure',td.departure_time||'—'),
      row('Operator', td.operator||'—'),
      td.seat_numbers?.length > 0 ? row('Seats', td.seat_numbers.join(', ')) : '',
    ].join('') };
    case 'cab': return { rows: [
      row('Pickup',   td.from||'—'),
      row('Drop',     td.to||'—'),
      row('Date',     fmtDate(td.pickup_date)),
      row('Time',     td.pickup_time||'—'),
      row('Cab Type', td.cab_type||'Sedan'),
    ].join('') };
    default: return { rows: '' };
  }
}


// ============================================================
//  UTILITIES
// ============================================================
function esc(s: any): string {
  return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

function fmtDate(d: any): string {
  if (!d) return '—';
  try { return new Date(d).toLocaleDateString('en-IN',{day:'numeric',month:'short',year:'numeric'}); }
  catch(_){ return String(d); }
}

function fmtDateTime(d: any): string {
  if (!d) return '—';
  try { return new Date(d).toLocaleString('en-IN',{
    day:'numeric',month:'short',year:'numeric',
    hour:'2-digit',minute:'2-digit',hour12:true,timeZone:'Asia/Kolkata'
  }) + ' IST'; }
  catch(_){ return String(d); }
}

function fmtAmt(n: any): string {
  return parseFloat(n||0).toLocaleString('en-IN',{minimumFractionDigits:0,maximumFractionDigits:2});
}

function capitalize(s: string): string {
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : '';
}

function typeLabel(t: string): string {
  const m: Record<string,string> = {
    flight:'✈️ Flight', hotel:'🏨 Hotel', package:'🧳 Package',
    bus:'🚌 Bus', cab:'🚖 Cab'
  };
  return m[t] || t;
}

function sanitizePhone(p: string): string {
  if (!p) return '918076136300';
  let ph = p.replace(/\D/g,'');
  if (ph.length === 10) ph = '91' + ph;
  return ph;
}

function calcNights(ci: string, co: string): number {
  if (!ci||!co) return 1;
  return Math.max(1, Math.round((new Date(co).getTime()-new Date(ci).getTime())/86400000));
}

function getUrgency(td: any): { label: string; cls: string } {
  const date = td?.date || td?.check_in || td?.start_date || td?.pickup_date;
  if (!date) return { label: '🟡 Normal Priority', cls: 'u-yellow' };
  const days = Math.round((new Date(date).getTime() - Date.now()) / 86400000);
  if (days <= 0) return { label: '🔴 URGENT — Travel Today!',        cls: 'u-red'    };
  if (days <= 1) return { label: '🔴 URGENT — Travel Tomorrow!',     cls: 'u-red'    };
  if (days <= 3) return { label: `🟠 HIGH — Travel in ${days} days`, cls: 'u-orange' };
  if (days <= 7) return { label: `🟡 Medium — ${days} days away`,    cls: 'u-yellow' };
  return              { label: `🟢 Normal — ${days} days away`,      cls: 'u-green'  };
}


/* ============================================================
   SUPABASE SETUP INSTRUCTIONS
   ============================================================

   1. INSTALL RESEND (free 3,000 emails/month)
      → Sign up at resend.com
      → Add & verify domain: zoomfly.in
      → Create API key

   2. SET EDGE FUNCTION SECRETS
      Run in terminal:
        supabase secrets set RESEND_API_KEY=re_xxxxxxxxxxxx
        supabase secrets set SUPABASE_URL=https://yourproject.supabase.co
        supabase secrets set SUPABASE_SERVICE_ROLE_KEY=eyJxxxxxxxxx

   3. DEPLOY EDGE FUNCTION
        supabase functions deploy send-booking-email

   4. CREATE DB WEBHOOK (Supabase Dashboard)
      → Database → Webhooks → Create new webhook
      → Table: bookings
      → Events: INSERT
      → URL: https://yourproject.supabase.co/functions/v1/send-booking-email
      → HTTP Headers: Authorization: Bearer <your-anon-key>

   5. TEST IT
      Insert a test booking row and check:
      → Customer email inbox
      → s.admin@zoomfly.in inbox
      → Edge function logs in Supabase dashboard

   ALTERNATIVE: Call manually from booking.js after DB save:
      await fetch('/api/send-email', {
        method: 'POST',
        body: JSON.stringify({ booking: savedBooking })
      });

   ============================================================ */
