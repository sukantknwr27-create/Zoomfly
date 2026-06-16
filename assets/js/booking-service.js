// ============================================================
//  ZOOMFLY — BOOKING SERVICE  (booking-service.js)
//
//  Responsibility: ONLY database writes and reads.
//  No UI, no WhatsApp, no DOM manipulation here.
//
//  Imports from: supabase.js
//  Imported by:  booking.js (orchestrator)
// ============================================================

import { supabase } from './supabase.js';

const CONFIG = {
  gst_rate: 0.18,
};

// ─── SAVE BOOKING TO DB ──────────────────────────────────────
export async function saveBooking(payload) {
  const { data, error } = await supabase
    .from('bookings')
    .insert([payload])
    .select()
    .single();

  if (error) throw new Error(`DB write failed: ${error.message}`);
  return data;
}

// ─── FETCH BY REF ────────────────────────────────────────────
export async function getBookingByRef(ref) {
  const { data, error } = await supabase
    .from('bookings')
    .select('*')
    .eq('booking_ref', ref.trim().toUpperCase())
    .single();
  if (error) throw new Error(error.message);
  return data;
}

// ─── FETCH BY EMAIL ──────────────────────────────────────────
export async function getBookingsByEmail(email) {
  const { data, error } = await supabase
    .from('bookings')
    .select('*')
    .eq('customer_email', email.trim().toLowerCase())
    .order('created_at', { ascending: false });
  if (error) throw new Error(error.message);
  return data || [];
}

// ─── CANCEL BOOKING ──────────────────────────────────────────
export async function cancelBooking(bookingId, reason = '') {
  const { data, error } = await supabase
    .from('bookings')
    .update({
      status:       'cancelled',
      cancel_reason: reason,
      cancelled_at:  new Date().toISOString(),
    })
    .eq('id', bookingId)
    .select()
    .single();
  if (error) throw new Error(error.message);
  return data;
}

// ─── CONFIRM PAYMENT ─────────────────────────────────────────
export async function confirmPayment(bookingId, razorpayResponse, method = 'upi') {
  const { data, error } = await supabase
    .from('bookings')
    .update({
      status:              'confirmed',
      payment_status:      'paid',
      payment_method:      method,
      payment_id:          razorpayResponse.razorpay_payment_id,
      razorpay_order_id:   razorpayResponse.razorpay_order_id,
      razorpay_signature:  razorpayResponse.razorpay_signature,
      confirmed_at:        new Date().toISOString(),
    })
    .eq('id', bookingId)
    .select()
    .single();
  if (error) throw new Error(error.message);
  return data;
}

// ─── BUILD PAYLOAD (form data → DB row) ──────────────────────
export function buildPayload(serviceType, f) {
  const base  = parseFloat(f.base_amount   || f.price || 0);
  const tax   = parseFloat(f.tax_amount    || (base * CONFIG.gst_rate));
  const disc  = parseFloat(f.discount_amount || 0);
  const total = parseFloat(f.total_amount  || (base + tax - disc));

  return {
    service_type:      serviceType,
    service_name:      _buildServiceName(serviceType, f),
    customer_name:     f.customer_name    || f.name  || '',
    customer_email:    f.customer_email   || f.email || '',
    customer_phone:    f.customer_phone   || f.phone || '',
    customer_whatsapp: f.customer_whatsapp || f.phone || '',
    num_adults:        parseInt(f.adults  || f.travellers || 1),
    num_children:      parseInt(f.children  || 0),
    num_infants:       parseInt(f.infants   || 0),
    travellers:        f.travellers_list  || [],
    base_amount:       base,
    tax_amount:        parseFloat(tax.toFixed(2)),
    discount_amount:   disc,
    promo_code:        f.promo_code || null,
    total_amount:      parseFloat(total.toFixed(2)),
    special_requests:  f.special_requests || f.notes || '',
    booking_source:    f.booking_source   || 'website',
    travel_details:    _buildTravelDetails(serviceType, f),
    status:            'pending',
    payment_status:    'pending',
  };
}

// ─── PRIVATE HELPERS ─────────────────────────────────────────
function _buildServiceName(type, f) {
  switch (type) {
    case 'flight':  return `${f.from || f.origin} → ${f.to || f.destination}`;
    case 'hotel':   return f.hotel_name || f.property_name || 'Hotel Booking';
    case 'package': return f.package_name || f.tour_name   || 'Tour Package';
    case 'bus':     return `${f.from_city} → ${f.to_city}`;
    case 'cab':     return `${f.pickup_location} → ${f.drop_location || 'Drop'}`;
    default:        return 'Travel Booking';
  }
}

function _buildTravelDetails(type, f) {
  switch (type) {
    case 'flight': return {
      origin:        f.from         || f.origin,
      destination:   f.to           || f.destination,
      depart_date:   f.depart_date  || f.travel_date,
      return_date:   f.return_date  || null,
      trip_type:     f.trip_type    || 'oneway',
      cabin_class:   f.cabin_class  || 'economy',
      airline:       f.airline      || null,
      flight_number: f.flight_number || null,
    };
    case 'hotel': return {
      property_name: f.hotel_name   || f.property_name,
      location:      f.location     || f.city,
      check_in:      f.check_in     || f.checkin,
      check_out:     f.check_out    || f.checkout,
      nights:        _calcNights(f.check_in || f.checkin, f.check_out || f.checkout),
      room_type:     f.room_type    || 'standard',
      rooms:         parseInt(f.rooms || 1),
    };
    case 'package': return {
      package_id:    f.package_id   || f.tour_id,
      package_name:  f.package_name || f.tour_name,
      start_date:    f.start_date   || f.travel_date,
      end_date:      f.end_date     || null,
      duration:      f.duration     || null,
    };
    case 'bus': return {
      from_city:     f.from_city,
      to_city:       f.to_city,
      travel_date:   f.travel_date,
      departure_time: f.departure_time || null,
      bus_type:      f.bus_type     || 'ac_sleeper',
      seats:         f.seats        || [],
      operator:      f.operator     || null,
    };
    case 'cab': return {
      pickup_location: f.pickup_location,
      drop_location:   f.drop_location,
      pickup_date:     f.pickup_date || f.travel_date,
      pickup_time:     f.pickup_time || null,
      cab_type:        f.cab_type    || 'sedan',
      trip_type:       f.cab_trip_type || 'oneway',
    };
    default: return f;
  }
}

function _calcNights(checkIn, checkOut) {
  if (!checkIn || !checkOut) return 0;
  const diff = new Date(checkOut) - new Date(checkIn);
  return Math.max(0, Math.round(diff / 86400000));
}
