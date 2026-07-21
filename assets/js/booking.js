// ============================================================
//  ZOOMFLY — BOOKING ORCHESTRATOR  (booking.js)
//
//  Responsibility: coordinate the booking flow ONLY.
//    1. Build payload          → booking-service.js
//    2. Write to DB            → booking-service.js
//    3. Send WhatsApp message  → this file (simple URL)
//    4. Show result modal      → booking-ui.js
//
//  Pages import from this file — not from service or UI directly.
//  Usage:
//    import { createBooking, bookFlight } from './booking.js';
// ============================================================

import { buildPayload, saveBooking, confirmPayment,
         getBookingByRef, getBookingsByEmail, cancelBooking } from './booking-service.js';
import { showBookingSuccess, showBookingError } from './booking-ui.js';

const WA = '918076136300';

// ─── MAIN ENTRY POINT ────────────────────────────────────────
export async function createBooking(serviceType, formData) {
  try {
    const payload = buildPayload(serviceType, formData);
    const booking = await saveBooking(payload);

    // ✦ Persist for booking-confirmation.html to read
    try {
      sessionStorage.setItem('zf_last_booking', JSON.stringify(booking));
    } catch (_) {}

    _openWhatsApp(_buildWAMessage(serviceType, booking, formData));
    showBookingSuccess(booking);
    return { success: true, booking };
  } catch (err) {
    console.error('[ZoomFly Booking]', err);
    showBookingError(err.message);
    return { success: false, error: err.message };
  }
}

// ─── WHATSAPP MESSAGE ────────────────────────────────────────
function _buildWAMessage(type, booking, f) {
  const lines = [
    `*New Booking — ZoomFly*`,
    `Ref: *${booking.booking_ref}*`,
    `Service: ${booking.service_name}`,
    `Name: ${booking.customer_name}`,
    `Phone: ${booking.customer_phone}`,
    `Amount: ₹${Number(booking.total_amount).toLocaleString('en-IN')}`,
  ];
  const travelDate = f.travel_date || f.depart_date || f.start_date || f.check_in || f.date || f.pickup_date;
  if (travelDate) {
    lines.push(`Date: ${travelDate}`);
  }
  if (f.special_requests) lines.push(`Notes: ${f.special_requests}`);
  lines.push(`\nPlease confirm this booking.`);
  return lines.join('\n');
}

function _openWhatsApp(message) {
  const url = `https://wa.me/${WA}?text=${encodeURIComponent(message)}`;
  window.open(url, '_blank', 'noopener,noreferrer');
}

// ─── CONVENIENCE WRAPPERS ────────────────────────────────────
export const bookFlight  = d => createBooking('flight',  d);
export const bookHotel   = d => createBooking('hotel',   d);
export const bookPackage = d => createBooking('package', d);
export const bookBus     = d => createBooking('bus',     d);
export const bookCab     = d => createBooking('cab',     d);

// ─── RE-EXPORTS (so pages only need one import) ──────────────
export { confirmPayment, getBookingByRef, getBookingsByEmail, cancelBooking };
