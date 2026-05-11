// ============================================================
//  ZOOMFLY — WHATSAPP CONFIRMATION TEMPLATES
//  File: assets/js/whatsapp-templates.js
//
//  Two messages per booking:
//    1. CUSTOMER message  → sent to customer's WhatsApp
//    2. ADMIN message     → sent to ZoomFly admin (8076136300)
//
//  Each template is structured, emoji-rich, and mobile-optimised.
//  Usage:
//    import { sendCustomerConfirmation, sendAdminAlert } from './whatsapp-templates.js';
//    sendCustomerConfirmation('flight', booking);
//    sendAdminAlert('flight', booking);
// ============================================================


const ZOOMFLY = {
  name:      'ZoomFly',
  website:   'zoomfly.in',
  admin_wa:  '918076136300',
  admin_email: 's.admin@zoomfly.in',
  support_hours: 'Mon–Sat · 9 AM – 9 PM IST',
};


// ============================================================
//  PUBLIC API
// ============================================================

/**
 * Open WhatsApp with a pre-filled customer confirmation message.
 * The customer sends this to ZoomFly as their booking request.
 */
export function sendCustomerConfirmation(serviceType, booking) {
  const message = buildCustomerMessage(serviceType, booking);
  openWA(ZOOMFLY.admin_wa, message);
}

/**
 * Open WhatsApp with an admin alert (for internal use / admin panel).
 * Admin uses this to notify the team about a new booking.
 */
export function sendAdminAlert(serviceType, booking) {
  const message = buildAdminMessage(serviceType, booking);
  return message; // Return for admin panel display — don't auto-open
}

/**
 * Get both messages as strings (for preview or email fallback).
 */
export function getTemplates(serviceType, booking) {
  return {
    customer: buildCustomerMessage(serviceType, booking),
    admin:    buildAdminMessage(serviceType, booking),
  };
}

/**
 * Open WhatsApp with a custom booking status update to customer.
 */
export function sendStatusUpdate(booking, newStatus, note = '') {
  const message = buildStatusUpdateMessage(booking, newStatus, note);
  const phone   = sanitizePhone(booking.customer_whatsapp || booking.customer_phone);
  openWA(phone, message);
}

/**
 * Send payment confirmation to customer.
 */
export function sendPaymentConfirmation(booking) {
  const message = buildPaymentConfirmationMessage(booking);
  const phone   = sanitizePhone(booking.customer_whatsapp || booking.customer_phone);
  openWA(phone, message);
}

/**
 * Send cancellation confirmation to customer.
 */
export function sendCancellationMessage(booking, refundAmount = 0) {
  const message = buildCancellationMessage(booking, refundAmount);
  const phone   = sanitizePhone(booking.customer_whatsapp || booking.customer_phone);
  openWA(phone, message);
}


// ============================================================
//  CUSTOMER MESSAGES — one per service type
// ============================================================

function buildCustomerMessage(type, b) {
  const header = customerHeader(b);
  const body   = customerBody(type, b);
  const footer = customerFooter(b);
  return `${header}\n\n${body}\n\n${footer}`;
}

function customerHeader(b) {
  return [
    `✈️ *ZoomFly — Booking Request*`,
    `━━━━━━━━━━━━━━━━━━━━━━`,
    `📋 Ref No: *${b.booking_ref}*`,
    `🗓️ Submitted: ${fmtDateTime(b.created_at || new Date())}`,
  ].join('\n');
}

function customerFooter(b) {
  return [
    `━━━━━━━━━━━━━━━━━━━━━━`,
    `⏳ *Status: Awaiting Confirmation*`,
    ``,
    `Our team will confirm your booking within *30 minutes* during business hours.`,
    ``,
    `📞 Questions? Call/WhatsApp: *+91 80761 36300*`,
    `📧 Email: ${ZOOMFLY.admin_email}`,
    `🌐 ${ZOOMFLY.website}`,
    ``,
    `_Thank you for choosing ZoomFly_ 🙏`,
  ].join('\n');
}

function customerBody(type, b) {
  const td = b.travel_details || {};
  switch (type) {

    // ── FLIGHT ───────────────────────────────────────────────
    case 'flight': return [
      `✈️ *FLIGHT BOOKING REQUEST*`,
      ``,
      `🛫 *Route*`,
      `   ${td.from_city || td.from || '—'} (${td.from || ''}) → ${td.to_city || td.to || '—'} (${td.to || ''})`,
      ``,
      `📅 *Travel Details*`,
      `   Departure : ${fmtDate(td.date)}`,
      td.return_date
        ? `   Return    : ${fmtDate(td.return_date)}`
        : null,
      `   Trip Type : ${td.trip_type === 'round_trip' ? '🔄 Round Trip' : '➡️ One Way'}`,
      `   Cabin     : ${capitalize(td.class || 'Economy')}`,
      ``,
      `👥 *Travellers*`,
      `   Adults   : ${b.num_adults || 1}`,
      b.num_children > 0 ? `   Children : ${b.num_children}` : null,
      b.num_infants  > 0 ? `   Infants  : ${b.num_infants}`  : null,
      ``,
      `👤 *Lead Passenger*`,
      `   Name  : ${b.customer_name}`,
      `   Phone : ${b.customer_phone}`,
      `   Email : ${b.customer_email}`,
      ``,
      `💰 *Fare Summary*`,
      `   Base Fare : ₹${fmtAmt(b.base_amount)}`,
      `   Taxes     : ₹${fmtAmt(b.tax_amount)}`,
      b.discount_amount > 0
        ? `   Discount  : -₹${fmtAmt(b.discount_amount)}`
        : null,
      `   ┌──────────────────────┐`,
      `   │ *TOTAL: ₹${fmtAmt(b.total_amount)}* │`,
      `   └──────────────────────┘`,
      b.promo_code ? `   🎟️ Promo: ${b.promo_code}` : null,
      b.special_requests
        ? `\n📝 *Special Request*\n   ${b.special_requests}`
        : null,
    ].filter(v => v !== null).join('\n');


    // ── HOTEL ────────────────────────────────────────────────
    case 'hotel': return [
      `🏨 *HOTEL BOOKING REQUEST*`,
      ``,
      `🏩 *Property*`,
      `   ${td.hotel_name || '—'}`,
      `   📍 ${td.city || '—'}`,
      ``,
      `📅 *Stay Details*`,
      `   Check-in  : ${fmtDate(td.check_in)}`,
      `   Check-out : ${fmtDate(td.check_out)}`,
      `   Nights    : ${td.nights || calcNights(td.check_in, td.check_out)}`,
      `   Room Type : ${td.room_type || 'Standard'}`,
      `   Rooms     : ${td.num_rooms || 1}`,
      ``,
      `👥 *Guests*`,
      `   Adults   : ${b.num_adults || 1}`,
      b.num_children > 0 ? `   Children : ${b.num_children}` : null,
      ``,
      `👤 *Lead Guest*`,
      `   Name  : ${b.customer_name}`,
      `   Phone : ${b.customer_phone}`,
      `   Email : ${b.customer_email}`,
      ``,
      `💰 *Price Summary*`,
      `   Room Rate : ₹${fmtAmt(b.base_amount)}`,
      `   Taxes     : ₹${fmtAmt(b.tax_amount)}`,
      b.discount_amount > 0
        ? `   Discount  : -₹${fmtAmt(b.discount_amount)}`
        : null,
      `   ┌──────────────────────┐`,
      `   │ *TOTAL: ₹${fmtAmt(b.total_amount)}* │`,
      `   └──────────────────────┘`,
      b.special_requests
        ? `\n📝 *Special Request*\n   ${b.special_requests}`
        : null,
    ].filter(v => v !== null).join('\n');


    // ── PACKAGE ──────────────────────────────────────────────
    case 'package': return [
      `🧳 *HOLIDAY PACKAGE REQUEST*`,
      ``,
      `🌴 *Package*`,
      `   ${td.package_name || '—'}`,
      `   📍 ${td.destination || '—'}`,
      td.duration ? `   ⏱️ Duration : ${td.duration}` : null,
      ``,
      `📅 *Travel Dates*`,
      `   Departure : ${fmtDate(td.start_date)}`,
      td.end_date ? `   Return    : ${fmtDate(td.end_date)}` : null,
      ``,
      `👥 *Travellers*`,
      `   Adults   : ${b.num_adults || 1}`,
      b.num_children > 0 ? `   Children : ${b.num_children}` : null,
      td.hotel_class ? `   Hotel    : ${td.hotel_class}` : null,
      td.inclusions?.length > 0
        ? `\n✅ *Inclusions*\n${td.inclusions.map(i => `   • ${i}`).join('\n')}`
        : null,
      ``,
      `👤 *Lead Traveller*`,
      `   Name  : ${b.customer_name}`,
      `   Phone : ${b.customer_phone}`,
      `   Email : ${b.customer_email}`,
      ``,
      `💰 *Package Price*`,
      `   Package Cost : ₹${fmtAmt(b.base_amount)}`,
      `   Taxes        : ₹${fmtAmt(b.tax_amount)}`,
      b.discount_amount > 0
        ? `   Discount     : -₹${fmtAmt(b.discount_amount)}`
        : null,
      `   ┌──────────────────────┐`,
      `   │ *TOTAL: ₹${fmtAmt(b.total_amount)}* │`,
      `   └──────────────────────┘`,
      b.promo_code ? `   🎟️ Promo: ${b.promo_code}` : null,
      b.special_requests
        ? `\n📝 *Special Request*\n   ${b.special_requests}`
        : null,
    ].filter(v => v !== null).join('\n');


    // ── BUS ──────────────────────────────────────────────────
    case 'bus': return [
      `🚌 *BUS BOOKING REQUEST*`,
      ``,
      `🛣️ *Route*`,
      `   ${td.from || '—'} → ${td.to || '—'}`,
      ``,
      `📅 *Journey Details*`,
      `   Date       : ${fmtDate(td.date)}`,
      td.departure_time ? `   Departure  : ${td.departure_time}` : null,
      td.arrival_time   ? `   Arrival    : ${td.arrival_time}`   : null,
      td.operator   ? `   Operator   : ${td.operator}`   : null,
      td.bus_type   ? `   Bus Type   : ${td.bus_type}`   : null,
      td.seat_numbers?.length > 0
        ? `   Seats      : ${td.seat_numbers.join(', ')}`
        : null,
      ``,
      `👥 *Passengers*`,
      `   Adults   : ${b.num_adults || 1}`,
      b.num_children > 0 ? `   Children : ${b.num_children}` : null,
      ``,
      `👤 *Lead Passenger*`,
      `   Name  : ${b.customer_name}`,
      `   Phone : ${b.customer_phone}`,
      `   Email : ${b.customer_email}`,
      ``,
      `💰 *Fare Summary*`,
      `   Fare   : ₹${fmtAmt(b.base_amount)}`,
      `   Taxes  : ₹${fmtAmt(b.tax_amount)}`,
      `   ┌──────────────────────┐`,
      `   │ *TOTAL: ₹${fmtAmt(b.total_amount)}* │`,
      `   └──────────────────────┘`,
      b.special_requests
        ? `\n📝 *Special Request*\n   ${b.special_requests}`
        : null,
    ].filter(v => v !== null).join('\n');


    // ── CAB ──────────────────────────────────────────────────
    case 'cab': return [
      `🚖 *CAB BOOKING REQUEST*`,
      ``,
      `📍 *Journey*`,
      `   Pickup : ${td.from || '—'}`,
      `   Drop   : ${td.to   || '—'}`,
      ``,
      `📅 *Pickup Details*`,
      `   Date     : ${fmtDate(td.pickup_date)}`,
      td.pickup_time
        ? `   Time     : ${td.pickup_time}`
        : null,
      `   Cab Type : ${td.cab_type || 'Sedan'}`,
      `   Trip     : ${td.trip_type === 'round_trip' ? '🔄 Round Trip' : '➡️ One Way'}`,
      `   Pax      : ${td.passengers || b.num_adults || 1}`,
      td.luggage ? `   Luggage  : ${td.luggage}` : null,
      ``,
      `👤 *Customer*`,
      `   Name  : ${b.customer_name}`,
      `   Phone : ${b.customer_phone}`,
      `   Email : ${b.customer_email}`,
      ``,
      `💰 *Fare*`,
      `   Base Fare : ₹${fmtAmt(b.base_amount)}`,
      `   Taxes     : ₹${fmtAmt(b.tax_amount)}`,
      `   ┌──────────────────────┐`,
      `   │ *TOTAL: ₹${fmtAmt(b.total_amount)}* │`,
      `   └──────────────────────┘`,
      b.special_requests
        ? `\n📝 *Special Request*\n   ${b.special_requests}`
        : null,
    ].filter(v => v !== null).join('\n');

    default:
      return `Service: ${b.service_name || '—'}\nTotal: ₹${fmtAmt(b.total_amount)}`;
  }
}


// ============================================================
//  ADMIN ALERT MESSAGES
//  Shown in admin panel + used when admin manually sends update
// ============================================================

function buildAdminMessage(type, b) {
  const td = b.travel_details || {};
  const urgency = getUrgencyFlag(b);

  return [
    `🔔 *NEW BOOKING — ZoomFly Admin*`,
    `━━━━━━━━━━━━━━━━━━━━━━`,
    `${urgency}`,
    `📋 Ref   : *${b.booking_ref}*`,
    `🗂️ Type  : ${typeLabel(type)}`,
    ``,
    `👤 *Customer*`,
    `   Name  : ${b.customer_name}`,
    `   Phone : ${b.customer_phone}`,
    `   Email : ${b.customer_email}`,
    b.customer_whatsapp && b.customer_whatsapp !== b.customer_phone
      ? `   WA    : ${b.customer_whatsapp}`
      : null,
    ``,
    `📦 *Service*`,
    `   ${b.service_name || '—'}`,
    ...buildAdminTravelSummary(type, td, b),
    ``,
    `💰 *Financials*`,
    `   Base     : ₹${fmtAmt(b.base_amount)}`,
    `   Tax      : ₹${fmtAmt(b.tax_amount)}`,
    b.discount_amount > 0
      ? `   Discount : -₹${fmtAmt(b.discount_amount)}`
      : null,
    `   *TOTAL   : ₹${fmtAmt(b.total_amount)}*`,
    b.promo_code ? `   Promo    : ${b.promo_code}` : null,
    ``,
    `📊 *Status*`,
    `   Booking  : ${b.status || 'pending'}`,
    `   Payment  : ${b.payment_status || 'pending'}`,
    `   Source   : ${b.booking_source || 'website'}`,
    ``,
    b.special_requests
      ? `📝 *Special Req*: ${b.special_requests}\n`
      : null,
    `━━━━━━━━━━━━━━━━━━━━━━`,
    `⏰ Submitted: ${fmtDateTime(b.created_at || new Date())}`,
    ``,
    `👉 *Action Required:* Confirm with vendor and send customer update within 30 mins.`,
  ].filter(v => v !== null).join('\n');
}

function buildAdminTravelSummary(type, td, b) {
  switch (type) {
    case 'flight': return [
      `   Route : ${td.from || '—'} → ${td.to || '—'}`,
      `   Date  : ${fmtDate(td.date)}`,
      td.return_date ? `   Ret   : ${fmtDate(td.return_date)}` : null,
      `   Pax   : ${b.num_adults}A ${b.num_children}C ${b.num_infants}I`,
      `   Class : ${td.class || 'economy'}`,
    ];
    case 'hotel': return [
      `   Hotel : ${td.hotel_name || '—'}, ${td.city || '—'}`,
      `   In    : ${fmtDate(td.check_in)} → Out: ${fmtDate(td.check_out)}`,
      `   Room  : ${td.room_type} × ${td.num_rooms || 1}`,
      `   Nights: ${td.nights || '—'}`,
    ];
    case 'package': return [
      `   Pkg   : ${td.package_name || '—'}`,
      `   Dest  : ${td.destination || '—'}`,
      `   Dates : ${fmtDate(td.start_date)} → ${fmtDate(td.end_date)}`,
      `   Pax   : ${b.num_adults}A ${b.num_children}C`,
    ];
    case 'bus': return [
      `   Route : ${td.from || '—'} → ${td.to || '—'}`,
      `   Date  : ${fmtDate(td.date)} @ ${td.departure_time || '—'}`,
      `   Seats : ${td.seat_numbers?.join(', ') || '—'}`,
      `   Pax   : ${b.num_adults}A ${b.num_children}C`,
    ];
    case 'cab': return [
      `   Pickup: ${td.from || '—'}`,
      `   Drop  : ${td.to   || '—'}`,
      `   Date  : ${fmtDate(td.pickup_date)} @ ${td.pickup_time || '—'}`,
      `   Cab   : ${td.cab_type || 'Sedan'}`,
    ];
    default: return [];
  }
}

function getUrgencyFlag(b) {
  const td = b.travel_details || {};
  const travelDate = td.date || td.check_in || td.start_date || td.pickup_date;
  if (!travelDate) return `🟡 *Priority: Normal*`;
  const daysAway = Math.round((new Date(travelDate) - new Date()) / 86400000);
  if (daysAway <= 1)  return `🔴 *Priority: URGENT — Travel in ${daysAway <= 0 ? 'Today!' : '1 day!'}*`;
  if (daysAway <= 3)  return `🟠 *Priority: HIGH — Travel in ${daysAway} days*`;
  if (daysAway <= 7)  return `🟡 *Priority: Medium — Travel in ${daysAway} days*`;
  return `🟢 *Priority: Normal — Travel in ${daysAway} days*`;
}


// ============================================================
//  STATUS UPDATE MESSAGE (admin → customer)
// ============================================================

function buildStatusUpdateMessage(booking, newStatus, note) {
  const statusMap = {
    confirmed:  { emoji: '✅', label: 'CONFIRMED',  msg: 'Your booking is confirmed! Payment details will follow.' },
    processing: { emoji: '⚙️', label: 'PROCESSING', msg: 'We are processing your booking with the service provider.' },
    completed:  { emoji: '🎉', label: 'COMPLETED',  msg: 'Your journey is complete. Thank you for travelling with ZoomFly!' },
    cancelled:  { emoji: '❌', label: 'CANCELLED',  msg: 'Your booking has been cancelled. Refund (if applicable) will be processed within 5–7 business days.' },
    refunded:   { emoji: '💰', label: 'REFUNDED',   msg: 'Your refund has been processed and will reflect in your account within 3–5 business days.' },
  };

  const s = statusMap[newStatus] || { emoji: 'ℹ️', label: newStatus.toUpperCase(), msg: '' };

  return [
    `${s.emoji} *ZoomFly Booking Update*`,
    `━━━━━━━━━━━━━━━━━━━━━━`,
    `📋 Ref: *${booking.booking_ref}*`,
    `📦 Service: ${booking.service_name}`,
    ``,
    `🔄 *Status: ${s.label}*`,
    ``,
    s.msg,
    note ? `\n📝 Note: ${note}` : null,
    ``,
    `━━━━━━━━━━━━━━━━━━━━━━`,
    `❓ Questions? Reply to this message or call +91 80761 36300`,
    `🌐 ${ZOOMFLY.website}`,
  ].filter(v => v !== null).join('\n');
}


// ============================================================
//  PAYMENT CONFIRMATION MESSAGE (admin → customer)
// ============================================================

function buildPaymentConfirmationMessage(booking) {
  return [
    `💳 *Payment Received — ZoomFly*`,
    `━━━━━━━━━━━━━━━━━━━━━━`,
    `📋 Booking Ref : *${booking.booking_ref}*`,
    `📦 Service     : ${booking.service_name}`,
    ``,
    `✅ *Payment of ₹${fmtAmt(booking.total_amount)} confirmed*`,
    booking.payment_method
      ? `   Method : ${paymentMethodLabel(booking.payment_method)}`
      : null,
    booking.razorpay_payment_id
      ? `   Txn ID : ${booking.razorpay_payment_id}`
      : null,
    `   Paid At: ${fmtDateTime(booking.paid_at || new Date())}`,
    ``,
    `📄 Your e-ticket / booking voucher will be sent within 2 hours.`,
    ``,
    `━━━━━━━━━━━━━━━━━━━━━━`,
    `🙏 Thank you for choosing ZoomFly!`,
    `📞 Support: +91 80761 36300`,
    `🌐 ${ZOOMFLY.website}`,
  ].filter(v => v !== null).join('\n');
}


// ============================================================
//  CANCELLATION MESSAGE (admin → customer)
// ============================================================

function buildCancellationMessage(booking, refundAmount) {
  return [
    `❌ *Booking Cancelled — ZoomFly*`,
    `━━━━━━━━━━━━━━━━━━━━━━`,
    `📋 Ref     : *${booking.booking_ref}*`,
    `📦 Service : ${booking.service_name}`,
    `👤 Name    : ${booking.customer_name}`,
    ``,
    `Your booking has been successfully cancelled.`,
    ``,
    refundAmount > 0
      ? `💰 *Refund Amount: ₹${fmtAmt(refundAmount)}*\n   Will be credited to your original payment method within *5–7 business days*.`
      : `ℹ️ This booking is non-refundable as per our cancellation policy.`,
    ``,
    `📋 Cancellation Policy: ${ZOOMFLY.website}/refund-policy.html`,
    ``,
    `━━━━━━━━━━━━━━━━━━━━━━`,
    `Need help? WhatsApp us: +91 80761 36300`,
    `🌐 ${ZOOMFLY.website}`,
  ].filter(v => v !== null).join('\n');
}


// ============================================================
//  UTILITY FUNCTIONS
// ============================================================

function openWA(phone, message) {
  const clean = sanitizePhone(phone);
  const url   = `https://wa.me/${clean}?text=${encodeURIComponent(message)}`;
  window.open(url, '_blank');
}

function sanitizePhone(phone) {
  if (!phone) return ZOOMFLY.admin_wa;
  let p = phone.replace(/\D/g, '');
  if (p.startsWith('0')) p = '91' + p.slice(1);
  if (p.length === 10)   p = '91' + p;
  return p;
}

function fmtDate(dateStr) {
  if (!dateStr) return '—';
  try {
    return new Date(dateStr).toLocaleDateString('en-IN', {
      day: 'numeric', month: 'short', year: 'numeric'
    });
  } catch (_) { return dateStr; }
}

function fmtDateTime(dateStr) {
  if (!dateStr) return '—';
  try {
    return new Date(dateStr).toLocaleString('en-IN', {
      day: 'numeric', month: 'short', year: 'numeric',
      hour: '2-digit', minute: '2-digit', hour12: true,
      timeZone: 'Asia/Kolkata'
    }) + ' IST';
  } catch (_) { return dateStr; }
}

function fmtAmt(num) {
  return parseFloat(num || 0).toLocaleString('en-IN', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2
  });
}

function capitalize(str) {
  return str ? str.charAt(0).toUpperCase() + str.slice(1) : '';
}

function typeLabel(type) {
  const map = {
    flight: '✈️ Flight', hotel: '🏨 Hotel', package: '🧳 Package',
    bus: '🚌 Bus', cab: '🚖 Cab', destination: '🗺️ Destination'
  };
  return map[type] || type;
}

function paymentMethodLabel(method) {
  const map = {
    upi: 'UPI', card: 'Credit/Debit Card',
    netbanking: 'Net Banking', neft: 'NEFT/RTGS',
    emi: 'EMI', wallet: 'Wallet', cash: 'Cash'
  };
  return map[method] || method;
}

function calcNights(checkIn, checkOut) {
  if (!checkIn || !checkOut) return 1;
  return Math.max(1, Math.round((new Date(checkOut) - new Date(checkIn)) / 86400000));
}


// ============================================================
//  ADMIN PANEL HELPER
//  Call this from admin panel to display all templates for a booking
// ============================================================
export function renderTemplatePreview(serviceType, booking, containerId) {
  const container = document.getElementById(containerId);
  if (!container) return;

  const { customer, admin } = getTemplates(serviceType, booking);

  container.innerHTML = `
    <div style="display:grid; grid-template-columns:1fr 1fr; gap:20px;">

      <div>
        <div style="font-size:0.75rem;font-weight:700;text-transform:uppercase;
          letter-spacing:1px;color:#64748b;margin-bottom:10px;">
          📲 Customer Message
        </div>
        <div style="background:#075e54;border-radius:12px;padding:20px;
          font-family:monospace;font-size:0.82rem;color:#fff;
          white-space:pre-wrap;line-height:1.6;max-height:400px;overflow-y:auto;">
${escHtml(customer)}
        </div>
        <button onclick="copyText('customer-msg-${booking.booking_ref}')"
          style="margin-top:10px;padding:8px 16px;background:#1a73e8;color:#fff;
          border:none;border-radius:8px;cursor:pointer;font-size:0.82rem;font-weight:600;">
          📋 Copy Customer Message
        </button>
        <textarea id="customer-msg-${booking.booking_ref}"
          style="position:absolute;left:-9999px;">${customer}</textarea>
      </div>

      <div>
        <div style="font-size:0.75rem;font-weight:700;text-transform:uppercase;
          letter-spacing:1px;color:#64748b;margin-bottom:10px;">
          🔔 Admin Alert Message
        </div>
        <div style="background:#1a2535;border-radius:12px;padding:20px;
          font-family:monospace;font-size:0.82rem;color:#e2e8f0;
          white-space:pre-wrap;line-height:1.6;max-height:400px;overflow-y:auto;">
${escHtml(admin)}
        </div>
        <button onclick="copyText('admin-msg-${booking.booking_ref}')"
          style="margin-top:10px;padding:8px 16px;background:#ff6b35;color:#fff;
          border:none;border-radius:8px;cursor:pointer;font-size:0.82rem;font-weight:600;">
          📋 Copy Admin Alert
        </button>
        <textarea id="admin-msg-${booking.booking_ref}"
          style="position:absolute;left:-9999px;">${admin}</textarea>
      </div>

    </div>
  `;
}

function copyText(id) {
  const el = document.getElementById(id);
  if (!el) return;
  el.select();
  document.execCommand('copy');
  alert('Copied to clipboard!');
}

function escHtml(str) {
  return str.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}
