// ============================================================
//  ZOOMFLY — BOOKING CONFIRMATION FLOW
//  File: assets/js/booking.js
//  
//  Usage: import this on any booking page
//  Handles: DB write → WhatsApp redirect → confirmation UI
//
//  Supports: flight, hotel, package, bus, cab
// ============================================================

import { supabase } from './supabase.js';

// ─── CONFIG ────────────────────────────────────────────────
const ZOOMFLY_CONFIG = {
  whatsapp_number: '918076136300',
  admin_email:     's.admin@zoomfly.in',
  currency:        'INR',
  gst_rate:        0.18,  // 18% GST on travel services
};


// ============================================================
//  MAIN BOOKING FUNCTION
//  Call this from any booking form on submit
//
//  Usage:
//    import { createBooking } from './booking.js';
//    const result = await createBooking('flight', formData);
// ============================================================
export async function createBooking(serviceType, formData) {
  try {
    // 1. Build booking payload
    const payload = buildPayload(serviceType, formData);

    // 2. Write to Supabase
    const booking = await saveToDatabase(payload);

    // 3. Send WhatsApp confirmation
    const waMessage = buildWhatsAppMessage(serviceType, booking, formData);
    openWhatsApp(waMessage);

    // 4. Show success UI
    showBookingSuccess(booking);

    return { success: true, booking };

  } catch (err) {
    console.error('[ZoomFly Booking Error]', err);
    showBookingError(err.message);
    return { success: false, error: err.message };
  }
}


// ============================================================
//  PAYLOAD BUILDER
//  Converts raw form data into Supabase booking row
// ============================================================
function buildPayload(serviceType, f) {
  const base   = parseFloat(f.base_amount   || f.price || 0);
  const tax    = parseFloat(f.tax_amount    || (base * ZOOMFLY_CONFIG.gst_rate));
  const disc   = parseFloat(f.discount_amount || 0);
  const total  = parseFloat(f.total_amount  || (base + tax - disc));

  const common = {
    service_type:      serviceType,
    service_name:      buildServiceName(serviceType, f),
    customer_name:     f.customer_name    || f.name     || '',
    customer_email:    f.customer_email   || f.email    || '',
    customer_phone:    f.customer_phone   || f.phone    || '',
    customer_whatsapp: f.customer_whatsapp || f.phone   || '',
    num_adults:        parseInt(f.adults  || f.travellers || 1),
    num_children:      parseInt(f.children  || 0),
    num_infants:       parseInt(f.infants   || 0),
    travellers:        f.travellers_list  || [],
    base_amount:       base,
    tax_amount:        parseFloat(tax.toFixed(2)),
    discount_amount:   disc,
    promo_code:        f.promo_code       || null,
    total_amount:      parseFloat(total.toFixed(2)),
    payment_status:    'pending',
    status:            'pending',
    special_requests:  f.special_requests || null,
    booking_source:    'website',
    // Attach logged-in user if available
    user_id:           null,
  };

  // Attach user_id if logged in
  // (resolved async before calling, or left null for guests)
  if (f.user_id) common.user_id = f.user_id;

  // Service-specific travel_details
  common.travel_details = buildTravelDetails(serviceType, f);

  return common;
}


// ─── SERVICE NAME BUILDER ────────────────────────────────────
function buildServiceName(type, f) {
  switch (type) {
    case 'flight':
      return `${f.from_city || f.from || 'Origin'} → ${f.to_city || f.to || 'Destination'}`;
    case 'hotel':
      return `${f.hotel_name || 'Hotel'}, ${f.city || ''}`.trim();
    case 'package':
      return f.package_name || f.name || 'Holiday Package';
    case 'bus':
      return `${f.from || 'Origin'} → ${f.to || 'Destination'} (Bus)`;
    case 'cab':
      return `${f.pickup || f.from || 'Pickup'} → ${f.drop || f.to || 'Drop'}`;
    default:
      return f.name || 'ZoomFly Booking';
  }
}


// ─── TRAVEL DETAILS PER SERVICE ──────────────────────────────
function buildTravelDetails(type, f) {
  switch (type) {
    case 'flight':
      return {
        from:         f.from       || f.from_code || '',
        to:           f.to         || f.to_code   || '',
        from_city:    f.from_city  || '',
        to_city:      f.to_city    || '',
        date:         f.date       || f.departure_date || '',
        return_date:  f.return_date || null,
        trip_type:    f.trip_type  || 'one_way',
        airline:      f.airline    || '',
        pnr:          f.pnr        || '',
        class:        f.travel_class || f.class || 'economy',
        adults:       f.adults     || 1,
        children:     f.children   || 0,
        infants:      f.infants    || 0,
      };

    case 'hotel':
      return {
        hotel_name:   f.hotel_name || '',
        city:         f.city       || '',
        check_in:     f.check_in   || f.checkin   || '',
        check_out:    f.check_out  || f.checkout  || '',
        room_type:    f.room_type  || 'Standard',
        num_rooms:    f.num_rooms  || 1,
        nights:       f.nights     || calcNights(f.check_in, f.check_out),
        adults:       f.adults     || 1,
        children:     f.children   || 0,
      };

    case 'package':
      return {
        package_name: f.package_name || f.name     || '',
        package_id:   f.package_id   || null,
        destination:  f.destination  || f.city     || '',
        start_date:   f.start_date   || f.date     || '',
        end_date:     f.end_date     || '',
        duration:     f.duration     || '',
        adults:       f.adults       || 1,
        children:     f.children     || 0,
        inclusions:   f.inclusions   || [],
        hotel_class:  f.hotel_class  || '',
      };

    case 'bus':
      return {
        from:           f.from          || '',
        to:             f.to            || '',
        date:           f.date          || f.travel_date || '',
        operator:       f.operator      || '',
        bus_type:       f.bus_type      || '',
        departure_time: f.departure_time || '',
        arrival_time:   f.arrival_time  || '',
        seat_numbers:   f.seat_numbers  || [],
        adults:         f.adults        || 1,
        children:       f.children      || 0,
      };

    case 'cab':
      return {
        from:         f.pickup        || f.from || '',
        to:           f.drop          || f.to   || '',
        pickup_date:  f.pickup_date   || f.date || '',
        pickup_time:  f.pickup_time   || '',
        cab_type:     f.cab_type      || 'Sedan',
        trip_type:    f.trip_type     || 'one_way',
        driver_name:  f.driver_name   || '',
        driver_phone: f.driver_phone  || '',
        passengers:   f.passengers    || f.adults || 1,
        luggage:      f.luggage       || '',
      };

    default:
      return f.details || {};
  }
}


// ─── NIGHT CALCULATOR ────────────────────────────────────────
function calcNights(checkIn, checkOut) {
  if (!checkIn || !checkOut) return 1;
  const diff = new Date(checkOut) - new Date(checkIn);
  return Math.max(1, Math.round(diff / (1000 * 60 * 60 * 24)));
}


// ============================================================
//  DATABASE WRITE
// ============================================================
async function saveToDatabase(payload) {
  // Try to attach logged-in user
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (user) payload.user_id = user.id;
  } catch (_) { /* guest booking - fine */ }

  const { data, error } = await supabase
    .from('bookings')
    .insert([payload])
    .select()
    .single();

  if (error) throw new Error(`Database error: ${error.message}`);
  if (!data)  throw new Error('Booking could not be saved. Please try again.');

  return data;
}


// ============================================================
//  WHATSAPP MESSAGE BUILDERS
// ============================================================
function buildWhatsAppMessage(serviceType, booking, formData) {
  const header = buildWAHeader(booking);
  const body   = buildWABody(serviceType, booking, formData);
  const footer = buildWAFooter(booking);
  return encodeURIComponent(`${header}\n\n${body}\n\n${footer}`);
}


function buildWAHeader(booking) {
  return [
    `✈️ *ZoomFly Booking Request*`,
    `━━━━━━━━━━━━━━━━━━━━━━━`,
    `🎫 Ref: *${booking.booking_ref}*`,
    `📅 Date: ${formatDate(booking.created_at)}`,
  ].join('\n');
}


function buildWABody(type, booking, f) {
  const td = booking.travel_details || {};

  switch (type) {

    case 'flight': return [
      `✈️ *FLIGHT BOOKING*`,
      `Route: *${td.from_city || td.from} → ${td.to_city || td.to}*`,
      `Date: ${formatDate(td.date)}`,
      td.return_date ? `Return: ${formatDate(td.return_date)}` : null,
      `Type: ${td.trip_type === 'round_trip' ? 'Round Trip' : 'One Way'}`,
      `Class: ${capitalize(td.class || 'Economy')}`,
      `Travellers: ${booking.num_adults} Adult${booking.num_adults > 1 ? 's' : ''}${booking.num_children > 0 ? `, ${booking.num_children} Child` : ''}${booking.num_infants > 0 ? `, ${booking.num_infants} Infant` : ''}`,
      ``,
      `👤 *Passenger*`,
      `Name: ${booking.customer_name}`,
      `Phone: ${booking.customer_phone}`,
      `Email: ${booking.customer_email}`,
      ``,
      `💰 *Fare Breakup*`,
      `Base Fare: ₹${formatAmount(booking.base_amount)}`,
      `Taxes & Fees: ₹${formatAmount(booking.tax_amount)}`,
      booking.discount_amount > 0 ? `Discount: -₹${formatAmount(booking.discount_amount)}` : null,
      `*Total: ₹${formatAmount(booking.total_amount)}*`,
      booking.promo_code ? `Promo Used: ${booking.promo_code}` : null,
    ].filter(Boolean).join('\n');

    case 'hotel': return [
      `🏨 *HOTEL BOOKING*`,
      `Hotel: *${td.hotel_name}*`,
      `City: ${td.city}`,
      `Check-in: ${formatDate(td.check_in)}`,
      `Check-out: ${formatDate(td.check_out)}`,
      `Nights: ${td.nights}`,
      `Room: ${td.room_type} × ${td.num_rooms || 1}`,
      `Guests: ${booking.num_adults} Adult${booking.num_adults > 1 ? 's' : ''}${booking.num_children > 0 ? `, ${booking.num_children} Child` : ''}`,
      ``,
      `👤 *Guest*`,
      `Name: ${booking.customer_name}`,
      `Phone: ${booking.customer_phone}`,
      `Email: ${booking.customer_email}`,
      ``,
      `💰 *Price Breakup*`,
      `Room Rate: ₹${formatAmount(booking.base_amount)}`,
      `Taxes: ₹${formatAmount(booking.tax_amount)}`,
      booking.discount_amount > 0 ? `Discount: -₹${formatAmount(booking.discount_amount)}` : null,
      `*Total: ₹${formatAmount(booking.total_amount)}*`,
    ].filter(Boolean).join('\n');

    case 'package': return [
      `🧳 *HOLIDAY PACKAGE*`,
      `Package: *${td.package_name}*`,
      `Destination: ${td.destination}`,
      `Travel Date: ${formatDate(td.start_date)}`,
      td.end_date ? `Return Date: ${formatDate(td.end_date)}` : null,
      td.duration ? `Duration: ${td.duration}` : null,
      `Travellers: ${booking.num_adults} Adult${booking.num_adults > 1 ? 's' : ''}${booking.num_children > 0 ? `, ${booking.num_children} Child` : ''}`,
      td.hotel_class ? `Hotel Category: ${td.hotel_class}` : null,
      td.inclusions?.length > 0 ? `Inclusions: ${td.inclusions.join(', ')}` : null,
      ``,
      `👤 *Lead Traveller*`,
      `Name: ${booking.customer_name}`,
      `Phone: ${booking.customer_phone}`,
      `Email: ${booking.customer_email}`,
      ``,
      `💰 *Price Breakup*`,
      `Package Cost: ₹${formatAmount(booking.base_amount)}`,
      `Taxes: ₹${formatAmount(booking.tax_amount)}`,
      booking.discount_amount > 0 ? `Discount: -₹${formatAmount(booking.discount_amount)}` : null,
      `*Total: ₹${formatAmount(booking.total_amount)}*`,
      booking.promo_code ? `Promo Used: ${booking.promo_code}` : null,
    ].filter(Boolean).join('\n');

    case 'bus': return [
      `🚌 *BUS BOOKING*`,
      `Route: *${td.from} → ${td.to}*`,
      `Date: ${formatDate(td.date)}`,
      `Departure: ${td.departure_time || 'As scheduled'}`,
      td.operator ? `Operator: ${td.operator}` : null,
      td.bus_type ? `Bus Type: ${td.bus_type}` : null,
      td.seat_numbers?.length > 0 ? `Seats: ${td.seat_numbers.join(', ')}` : null,
      `Passengers: ${booking.num_adults} Adult${booking.num_adults > 1 ? 's' : ''}${booking.num_children > 0 ? `, ${booking.num_children} Child` : ''}`,
      ``,
      `👤 *Passenger*`,
      `Name: ${booking.customer_name}`,
      `Phone: ${booking.customer_phone}`,
      ``,
      `💰 *Fare*`,
      `Fare: ₹${formatAmount(booking.base_amount)}`,
      `Taxes: ₹${formatAmount(booking.tax_amount)}`,
      `*Total: ₹${formatAmount(booking.total_amount)}*`,
    ].filter(Boolean).join('\n');

    case 'cab': return [
      `🚖 *CAB BOOKING*`,
      `Pickup: *${td.from}*`,
      `Drop: *${td.to}*`,
      `Date: ${formatDate(td.pickup_date)}`,
      `Time: ${td.pickup_time || 'As requested'}`,
      `Cab Type: ${td.cab_type || 'Sedan'}`,
      `Trip Type: ${td.trip_type === 'round_trip' ? 'Round Trip' : 'One Way'}`,
      `Passengers: ${td.passengers || booking.num_adults}`,
      td.luggage ? `Luggage: ${td.luggage}` : null,
      ``,
      `👤 *Customer*`,
      `Name: ${booking.customer_name}`,
      `Phone: ${booking.customer_phone}`,
      ``,
      `💰 *Fare*`,
      `Base Fare: ₹${formatAmount(booking.base_amount)}`,
      `Taxes: ₹${formatAmount(booking.tax_amount)}`,
      `*Total: ₹${formatAmount(booking.total_amount)}*`,
    ].filter(Boolean).join('\n');

    default: return `Service: ${booking.service_name}\nTotal: ₹${formatAmount(booking.total_amount)}`;
  }
}


function buildWAFooter(booking) {
  const lines = [
    `━━━━━━━━━━━━━━━━━━━━━━━`,
    `📌 *Status: Booking Request Submitted*`,
    `Our team will confirm within 30 minutes.`,
  ];
  if (booking.special_requests) {
    lines.push(``, `📝 Special Request: ${booking.special_requests}`);
  }
  lines.push(
    ``,
    `Thank you for choosing *ZoomFly* 🙏`,
    `📞 Support: +91 80761 36300`,
    `🌐 zoomfly.in`
  );
  return lines.join('\n');
}


// ============================================================
//  WHATSAPP OPENER
// ============================================================
function openWhatsApp(encodedMessage) {
  const url = `https://wa.me/${ZOOMFLY_CONFIG.whatsapp_number}?text=${encodedMessage}`;
  window.open(url, '_blank');
}


// ============================================================
//  SUCCESS / ERROR UI
// ============================================================
function showBookingSuccess(booking) {
  // Remove any existing modal
  document.getElementById('zf-booking-modal')?.remove();

  const modal = document.createElement('div');
  modal.id = 'zf-booking-modal';
  modal.innerHTML = `
    <div style="
      position:fixed; inset:0; background:rgba(0,0,0,0.6);
      display:flex; align-items:center; justify-content:center;
      z-index:9999; padding:20px; backdrop-filter:blur(4px);
      animation: zfFadeIn 0.3s ease;
    ">
      <div style="
        background:#fff; border-radius:20px; padding:40px 36px;
        max-width:460px; width:100%; text-align:center;
        box-shadow:0 24px 80px rgba(0,0,0,0.25);
        animation: zfSlideUp 0.4s ease;
      ">
        <!-- Success icon -->
        <div style="
          width:72px; height:72px; background:linear-gradient(135deg,#22c55e,#16a34a);
          border-radius:50%; display:flex; align-items:center; justify-content:center;
          margin:0 auto 20px; font-size:32px;
          box-shadow:0 8px 24px rgba(34,197,94,0.35);
        ">✅</div>

        <h2 style="
          font-family:'Playfair Display',serif; font-size:1.5rem;
          color:#0f1923; margin-bottom:8px;
        ">Booking Request Sent!</h2>

        <p style="color:#64748b; font-size:0.9rem; margin-bottom:24px; line-height:1.6;">
          Your booking has been recorded and our team has been notified on WhatsApp.
          We'll confirm within <strong>30 minutes</strong>.
        </p>

        <!-- Booking Ref -->
        <div style="
          background:#f8fafc; border:1px solid #e2e8f0;
          border-radius:12px; padding:16px 20px; margin-bottom:24px;
        ">
          <div style="font-size:0.72rem; font-weight:600; text-transform:uppercase;
            letter-spacing:1px; color:#94a3b8; margin-bottom:4px;">
            Booking Reference
          </div>
          <div style="font-size:1.2rem; font-weight:700; color:#1a73e8; letter-spacing:1px;">
            ${booking.booking_ref}
          </div>
          <div style="font-size:0.78rem; color:#94a3b8; margin-top:4px;">
            Save this for tracking your booking
          </div>
        </div>

        <!-- Info rows -->
        <div style="text-align:left; margin-bottom:24px;">
          <div style="display:flex; justify-content:space-between; padding:8px 0;
            border-bottom:1px solid #f1f5f9; font-size:0.85rem;">
            <span style="color:#64748b;">Service</span>
            <span style="font-weight:600; color:#2d3748;">${booking.service_name}</span>
          </div>
          <div style="display:flex; justify-content:space-between; padding:8px 0;
            border-bottom:1px solid #f1f5f9; font-size:0.85rem;">
            <span style="color:#64748b;">Amount</span>
            <span style="font-weight:700; color:#ff6b35;">₹${formatAmount(booking.total_amount)}</span>
          </div>
          <div style="display:flex; justify-content:space-between; padding:8px 0;
            font-size:0.85rem;">
            <span style="color:#64748b;">Status</span>
            <span style="
              background:rgba(234,179,8,0.1); color:#854d0e;
              padding:2px 10px; border-radius:20px; font-size:0.78rem; font-weight:600;
            ">⏳ Pending Confirmation</span>
          </div>
        </div>

        <!-- WhatsApp CTA -->
        <a href="https://wa.me/${ZOOMFLY_CONFIG.whatsapp_number}"
          target="_blank"
          style="
            display:block; background:linear-gradient(135deg,#25d366,#128c7e);
            color:#fff; padding:13px 24px; border-radius:10px; text-decoration:none;
            font-weight:700; font-size:0.92rem; margin-bottom:12px;
            box-shadow:0 4px 16px rgba(37,211,102,0.35);
          ">
          💬 Chat with Us on WhatsApp
        </a>

        <button onclick="document.getElementById('zf-booking-modal').remove()"
          style="
            background:none; border:1.5px solid #e2e8f0; color:#64748b;
            padding:11px 24px; border-radius:10px; cursor:pointer;
            font-size:0.88rem; width:100%; transition:all 0.2s;
          "
          onmouseover="this.style.background='#f8fafc'"
          onmouseout="this.style.background='none'"
        >
          Close
        </button>
      </div>
    </div>
    <style>
      @keyframes zfFadeIn  { from { opacity:0 } to { opacity:1 } }
      @keyframes zfSlideUp { from { opacity:0; transform:translateY(24px) } to { opacity:1; transform:translateY(0) } }
    </style>
  `;
  document.body.appendChild(modal);

  // Close on backdrop click
  modal.addEventListener('click', (e) => {
    if (e.target === modal.firstElementChild) modal.remove();
  });
}


function showBookingError(message) {
  document.getElementById('zf-booking-modal')?.remove();

  const modal = document.createElement('div');
  modal.id = 'zf-booking-modal';
  modal.innerHTML = `
    <div style="
      position:fixed; inset:0; background:rgba(0,0,0,0.6);
      display:flex; align-items:center; justify-content:center;
      z-index:9999; padding:20px; backdrop-filter:blur(4px);
    ">
      <div style="
        background:#fff; border-radius:20px; padding:40px 36px;
        max-width:420px; width:100%; text-align:center;
        box-shadow:0 24px 80px rgba(0,0,0,0.25);
      ">
        <div style="
          width:72px; height:72px; background:linear-gradient(135deg,#ef4444,#dc2626);
          border-radius:50%; display:flex; align-items:center; justify-content:center;
          margin:0 auto 20px; font-size:32px;
        ">❌</div>

        <h2 style="font-family:'Playfair Display',serif; font-size:1.4rem; color:#0f1923; margin-bottom:8px;">
          Booking Failed
        </h2>

        <p style="color:#64748b; font-size:0.88rem; margin-bottom:20px; line-height:1.6;">
          ${message || 'Something went wrong. Please try again or contact us on WhatsApp.'}
        </p>

        <a href="https://wa.me/${ZOOMFLY_CONFIG.whatsapp_number}"
          target="_blank"
          style="
            display:block; background:linear-gradient(135deg,#25d366,#128c7e);
            color:#fff; padding:13px 24px; border-radius:10px; text-decoration:none;
            font-weight:700; font-size:0.9rem; margin-bottom:12px;
          ">
          💬 Contact Us on WhatsApp
        </a>

        <button onclick="document.getElementById('zf-booking-modal').remove()"
          style="
            background:none; border:1.5px solid #e2e8f0; color:#64748b;
            padding:11px 24px; border-radius:10px; cursor:pointer;
            font-size:0.88rem; width:100%;
          ">
          Try Again
        </button>
      </div>
    </div>
  `;
  document.body.appendChild(modal);
  modal.addEventListener('click', (e) => {
    if (e.target === modal.firstElementChild) modal.remove();
  });
}


// ============================================================
//  UTILITY FUNCTIONS
// ============================================================
function formatAmount(num) {
  return parseFloat(num || 0).toLocaleString('en-IN', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2
  });
}

function formatDate(dateStr) {
  if (!dateStr) return '—';
  try {
    return new Date(dateStr).toLocaleDateString('en-IN', {
      day: 'numeric', month: 'short', year: 'numeric'
    });
  } catch (_) { return dateStr; }
}

function capitalize(str) {
  if (!str) return '';
  return str.charAt(0).toUpperCase() + str.slice(1);
}


// ============================================================
//  CONVENIENCE WRAPPERS (call directly from each page)
// ============================================================
export const bookFlight  = (data) => createBooking('flight',  data);
export const bookHotel   = (data) => createBooking('hotel',   data);
export const bookPackage = (data) => createBooking('package', data);
export const bookBus     = (data) => createBooking('bus',     data);
export const bookCab     = (data) => createBooking('cab',     data);


// ============================================================
//  PAYMENT CONFIRMATION (call after Razorpay success callback)
//
//  Usage:
//    const { booking } = await createBooking('flight', formData);
//    razorpay.on('payment.success', async (response) => {
//      await confirmPayment(booking.id, response, 'upi');
//    });
// ============================================================
export async function confirmPayment(bookingId, razorpayResponse, method = 'upi') {
  const { data, error } = await supabase.rpc('confirm_payment', {
    p_booking_id:       bookingId,
    p_razorpay_order:   razorpayResponse.razorpay_order_id,
    p_razorpay_payment: razorpayResponse.razorpay_payment_id,
    p_razorpay_sig:     razorpayResponse.razorpay_signature,
    p_method:           method,
  });

  if (error) throw new Error(`Payment confirmation failed: ${error.message}`);
  return data;
}


// ============================================================
//  BOOKING STATUS CHECKER
//  For customers to track their booking by ref or email
// ============================================================
export async function getBookingByRef(bookingRef) {
  const { data, error } = await supabase
    .from('bookings')
    .select('*')
    .eq('booking_ref', bookingRef.trim().toUpperCase())
    .single();

  if (error) throw new Error('Booking not found. Please check your reference number.');
  return data;
}

export async function getBookingsByEmail(email) {
  const { data, error } = await supabase
    .rpc('get_bookings_by_email', { p_email: email });

  if (error) throw new Error('Could not retrieve bookings.');
  return data || [];
}

export async function getMyBookings() {
  const { data, error } = await supabase
    .from('bookings')
    .select('*')
    .order('created_at', { ascending: false });

  if (error) throw new Error('Could not retrieve your bookings.');
  return data || [];
}


// ============================================================
//  CANCEL BOOKING (customer-initiated)
// ============================================================
export async function cancelBooking(bookingId, reason = '') {
  const { data, error } = await supabase
    .from('bookings')
    .update({
      status:         'cancelled',
      internal_notes: reason,
      cancelled_at:   new Date().toISOString(),
    })
    .eq('id', bookingId)
    .select()
    .single();

  if (error) throw new Error(`Cancellation failed: ${error.message}`);
  return data;
}
