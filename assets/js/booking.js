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

// Falls back to this literal only if main.js (which sets window.ZF
// from the admin-configured site_settings.whatsapp_number) hasn't
// loaded — keeps this working standalone, but prefers the live value.
function _supportWA() {
  return (typeof window !== 'undefined' && window.ZF && window.ZF.whatsapp) || '918076136300';
}

// ─── MAIN ENTRY POINT ────────────────────────────────────────
export async function createBooking(serviceType, formData) {
  // Open the WhatsApp tab synchronously, *before* any await below —
  // once the calling click handler has awaited something, some
  // browsers (notably Safari) no longer treat window.open() as part
  // of the original user gesture and silently block it, so the
  // notification would never open even though the booking succeeded.
  // We fill in the real wa.me URL once the booking is saved. Can't
  // pass the `noopener` feature here (it makes window.open() return
  // null instead of a handle), so sever `.opener` manually instead —
  // same reverse-tabnabbing protection, without losing the reference.
  const waWindow = window.open('', '_blank');
  if (waWindow) { try { waWindow.opener = null; } catch (_) {} }

  try {
    const payload = buildPayload(serviceType, formData);
    const booking = await saveBooking(payload);

    // ✦ Persist for booking-confirmation.html to read
    try {
      sessionStorage.setItem('zf_last_booking', JSON.stringify(booking));
    } catch (_) {}

    _openWhatsApp(waWindow, _buildWAMessage(serviceType, booking, formData));
    showBookingSuccess(booking);
    return { success: true, booking };
  } catch (err) {
    if (waWindow && !waWindow.closed) waWindow.close();
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

function _openWhatsApp(win, message) {
  const url = `https://wa.me/${_supportWA()}?text=${encodeURIComponent(message)}`;
  if (win && !win.closed) {
    win.location.href = url;
  } else {
    // Placeholder tab was blocked (or the user closed it) — fall back
    // to a fresh attempt; if that's blocked too, there's nothing more
    // we can do without the user re-initiating it themselves.
    window.open(url, '_blank', 'noopener,noreferrer');
  }
}

// ─── CONVENIENCE WRAPPERS ────────────────────────────────────
export const bookFlight  = d => createBooking('flight',  d);
export const bookHotel   = d => createBooking('hotel',   d);
export const bookPackage = d => createBooking('package', d);
export const bookBus     = d => createBooking('bus',     d);
export const bookCab     = d => createBooking('cab',     d);

// ─── RE-EXPORTS (so pages only need one import) ──────────────
export { confirmPayment, getBookingByRef, getBookingsByEmail, cancelBooking };
