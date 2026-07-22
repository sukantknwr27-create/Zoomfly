// ============================================================
//  ZOOMFLY — BOOKING FORM INTEGRATIONS
//  File: assets/js/booking-forms.js
//
//  Drop-in handlers for all 5 booking forms.
//  Each section is self-contained — copy the relevant
//  section into the matching page's <script> block.
//
//  Requires: booking.js + supabase.js in assets/js/
// ============================================================

import { bookFlight, bookHotel, bookPackage, bookBus, bookCab } from './booking.js';
import { setLoading } from './booking-ui.js';
import { CONFIG } from './booking-service.js';
// ✦ setLoading previously duplicated in both booking.js and booking-forms.js.
//   Single definition now lives in booking-ui.js.

// ============================================================
//  VALIDATION UTILITIES
// ============================================================

/** Show an inline error under the given field element */
function _fieldError(el, msg) {
  if (!el) return;
  el.style.borderColor = '#ef4444';
  let err = el.parentElement.querySelector('.zf-err');
  if (!err) { err = document.createElement('span'); err.className = 'zf-err'; err.style.cssText = 'color:#ef4444;font-size:.78rem;display:block;margin-top:3px'; el.parentElement.appendChild(err); }
  err.textContent = msg;
}

function _clearErrors(form) {
  form.querySelectorAll('.zf-err').forEach(e => e.remove());
  form.querySelectorAll('[style*="border-color"]').forEach(e => e.style.borderColor = '');
}

function _validateEmail(v) { return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(v.trim()); }
function _validatePhone(v) { return /^[6-9]\d{9}$/.test(v.replace(/\D/g,'')); }
function _validateDate(v, minToday = true) {
  if (!v) return false;
  const d = new Date(v);
  if (isNaN(d)) return false;
  if (minToday) {
    // v is a plain "YYYY-MM-DD" from <input type="date">, which the
    // Date constructor parses as UTC midnight — comparing that
    // directly against a local "today" midnight is off by the local
    // UTC offset, and can wrongly reject today's date as "in the
    // past" for users west of UTC. Compare calendar dates in local
    // time on both sides instead.
    const [y, m, day] = v.split('-').map(Number);
    const localD = new Date(y, (m || 1) - 1, day || 1);
    if (localD < new Date(new Date().toDateString())) return false;
  }
  return true;
}

/**
 * Run common checks on customer contact fields present in a form.
 * Returns true if all valid, false (with inline errors shown) if not.
 */
function validateContactFields(form) {
  _clearErrors(form);
  let ok = true;

  const nameEl  = form.querySelector('[name="name"],[name="customer_name"],#passenger-name');
  const emailEl = form.querySelector('[name="email"],[name="customer_email"],#passenger-email');
  const phoneEl = form.querySelector('[name="phone"],[name="customer_phone"],#passenger-phone');

  if (nameEl && nameEl.value.trim().length < 2) {
    _fieldError(nameEl, 'Please enter your full name.'); ok = false;
  }
  if (emailEl && !_validateEmail(emailEl.value)) {
    _fieldError(emailEl, 'Enter a valid email address.'); ok = false;
  }
  if (phoneEl && !_validatePhone(phoneEl.value)) {
    _fieldError(phoneEl, 'Enter a valid 10-digit Indian mobile number.'); ok = false;
  }
  return ok;
}

/** Validate a travel date field — must be present and not in the past */
function validateDateField(form, selector, label = 'Travel date') {
  const el = form.querySelector(selector);
  if (!el) return true;
  if (!_validateDate(el.value)) {
    _fieldError(el, `${label} must be today or a future date.`);
    return false;
  }
  return true;
}

/** Validate that check-in is before check-out */
function validateDateRange(form, inSel, outSel) {
  const inEl  = form.querySelector(inSel);
  const outEl = form.querySelector(outSel);
  if (!inEl || !outEl) return true;
  if (!_validateDate(inEl.value))  { _fieldError(inEl,  'Select a valid check-in date.');  return false; }
  if (!_validateDate(outEl.value)) { _fieldError(outEl, 'Select a valid check-out date.'); return false; }
  if (new Date(outEl.value) <= new Date(inEl.value)) {
    _fieldError(outEl, 'Check-out must be after check-in.'); return false;
  }
  return true;
}

export { validateContactFields, validateDateField, validateDateRange, _clearErrors };


// ============================================================
//  1. FLIGHT BOOKING FORM
//  Page: flights.html
//  Add to bottom of flights.html <script> block
// ============================================================
function initFlightBookingForm() {
  const form = document.getElementById('flight-booking-form');
  if (!form) return;

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = form.querySelector('[type="submit"]');

    // Validate before loading
    const contactOk = validateContactFields(form);
    const dateOk    = validateDateField(form, '[name="date"],#departure-date,[type="date"]', 'Departure date');
    if (!contactOk || !dateOk) return;

    setLoading(btn, true);

    try {
      const adults   = parseInt(form.querySelector('[name="adults"]')?.value   || document.getElementById('adults-count')?.textContent   || 1);
      const children = parseInt(form.querySelector('[name="children"]')?.value || document.getElementById('children-count')?.textContent || 0);
      const infants  = parseInt(form.querySelector('[name="infants"]')?.value  || document.getElementById('infants-count')?.textContent  || 0);

      const fromInput = form.querySelector('[name="from"], #from-input, .from-field');
      const toInput   = form.querySelector('[name="to"],   #to-input,   .to-field');
      const dateInput = form.querySelector('[name="date"], #departure-date, [type="date"]');
      const returnInput = form.querySelector('[name="return_date"], #return-date');
      const classInput  = form.querySelector('[name="class"], #travel-class, select[name="class"]');
      const tripType    = form.querySelector('input[name="trip_type"]:checked, .trip-tab.active');

      // Price calculation
      const pricePerPerson = parseFloat(form.dataset.pricePerPerson || 0);
      const baseAmount = pricePerPerson * (adults + children);

      await bookFlight({
        from:          fromInput?.value || '',
        to:            toInput?.value   || '',
        from_city:     fromInput?.dataset.city || fromInput?.value || '',
        to_city:       toInput?.dataset.city   || toInput?.value   || '',
        date:          dateInput?.value  || '',
        return_date:   returnInput?.value || null,
        trip_type:     tripType?.dataset?.type || tripType?.value || 'one_way',
        travel_class:  classInput?.value || 'economy',
        adults, children, infants,

        // Customer info
        customer_name:  form.querySelector('[name="name"], #passenger-name')?.value  || '',
        customer_email: form.querySelector('[name="email"], #passenger-email')?.value || '',
        customer_phone: form.querySelector('[name="phone"], #passenger-phone')?.value || '',

        // Pricing
        base_amount: baseAmount,
        special_requests: form.querySelector('[name="special_requests"], #special-requests')?.value || '',
      });

    } catch (err) {
      console.error('[Flight Form]', err);
    } finally {
      setLoading(btn, false);
    }
  });
}


// ============================================================
//  2. HOTEL BOOKING FORM
//  Page: hotels.html / hotel-detail.html
// ============================================================
function initHotelBookingForm() {
  const form = document.getElementById('hotel-booking-form');
  if (!form) return;

  // Auto-calculate nights when dates change
  const checkInEl  = form.querySelector('[name="check_in"],  #check-in');
  const checkOutEl = form.querySelector('[name="check_out"], #check-out');
  const nightsEl   = form.querySelector('#nights-display, [name="nights"]');

  function updateNights() {
    if (!checkInEl?.value || !checkOutEl?.value) return;
    const nights = Math.max(1, Math.round(
      (new Date(checkOutEl.value) - new Date(checkInEl.value)) / 86400000
    ));
    if (nightsEl) nightsEl.textContent = nights;
    form.dataset.nights = nights;

    // Update total display
    const pricePerNight = parseFloat(form.dataset.pricePerNight || 0);
    const rooms = parseInt(form.querySelector('[name="num_rooms"]')?.value || 1);
    const totalEl = form.querySelector('#price-total, .booking-total');
    if (totalEl) totalEl.textContent = `₹${((pricePerNight * nights * rooms) * (1 + CONFIG.gst_rate)).toLocaleString('en-IN')}`;
  }

  checkInEl?.addEventListener('change', updateNights);
  checkOutEl?.addEventListener('change', updateNights);

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = form.querySelector('[type="submit"]');

    const contactOk = validateContactFields(form);
    const rangeOk    = validateDateRange(form, '[name="check_in"], #check-in', '[name="check_out"], #check-out');
    if (!contactOk || !rangeOk) return;

    setLoading(btn, true);

    try {
      const adults    = parseInt(form.querySelector('[name="adults"]')?.value   || 1);
      const children  = parseInt(form.querySelector('[name="children"]')?.value || 0);
      const rooms     = parseInt(form.querySelector('[name="num_rooms"]')?.value || 1);
      const nights    = parseInt(form.dataset.nights || 1);
      const roomType  = form.querySelector('[name="room_type"], #room-type, .room-selector.active')?.value
                     || form.querySelector('[name="room_type"]')?.value || 'Standard';

      const pricePerNight = parseFloat(form.dataset.pricePerNight || 0);
      const baseAmount    = pricePerNight * nights * rooms;

      await bookHotel({
        hotel_name: form.dataset.hotelName || form.querySelector('[name="hotel_name"]')?.value || '',
        city:       form.dataset.city      || form.querySelector('[name="city"]')?.value || '',
        check_in:   checkInEl?.value  || '',
        check_out:  checkOutEl?.value || '',
        room_type:  roomType,
        num_rooms:  rooms,
        nights,
        adults, children,

        customer_name:  form.querySelector('[name="name"],  #guest-name')?.value  || '',
        customer_email: form.querySelector('[name="email"], #guest-email')?.value || '',
        customer_phone: form.querySelector('[name="phone"], #guest-phone')?.value || '',

        base_amount: baseAmount,
        special_requests: form.querySelector('[name="special_requests"]')?.value || '',
        promo_code:       form.querySelector('[name="promo_code"], #promo-input')?.value || '',
      });

    } catch (err) {
      console.error('[Hotel Form]', err);
    } finally {
      setLoading(btn, false);
    }
  });
}


// ============================================================
//  3. PACKAGE BOOKING FORM
//  Page: packages.html / package-detail.html
// ============================================================
function initPackageBookingForm() {
  const form = document.getElementById('package-booking-form');
  if (!form) return;

  // Dynamic price recalc when travellers change
  const adultsInput   = form.querySelector('[name="adults"],   #pkg-adults');
  const childrenInput = form.querySelector('[name="children"], #pkg-children');
  const totalEl       = form.querySelector('#pkg-total, .package-total');

  function recalcPackagePrice() {
    const adults    = parseInt(adultsInput?.value || 1);
    const children  = parseInt(childrenInput?.value || 0);
    const pricePerAdult = parseFloat(form.dataset.pricePerAdult || form.dataset.price || 0);
    const pricePerChild = parseFloat(form.dataset.pricePerChild || pricePerAdult * 0.7);
    const base  = (adults * pricePerAdult) + (children * pricePerChild);
    const total = base * (1 + CONFIG.gst_rate);
    if (totalEl) totalEl.textContent = `₹${Math.round(total).toLocaleString('en-IN')}`;
    form.dataset.baseAmount  = base.toFixed(2);
    form.dataset.totalAmount = total.toFixed(2);
  }

  adultsInput?.addEventListener('change', recalcPackagePrice);
  childrenInput?.addEventListener('change', recalcPackagePrice);
  recalcPackagePrice(); // init

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = form.querySelector('[type="submit"]');

    const contactOk = validateContactFields(form);
    const dateOk    = validateDateField(form, '[name="start_date"], #travel-date', 'Travel date');
    if (!contactOk || !dateOk) return;

    setLoading(btn, true);

    try {
      const adults   = parseInt(adultsInput?.value || 1);
      const children = parseInt(childrenInput?.value || 0);

      await bookPackage({
        package_name: form.dataset.packageName || form.querySelector('[name="package_name"]')?.value || '',
        package_id:   form.dataset.packageId   || null,
        destination:  form.dataset.destination  || form.querySelector('[name="destination"]')?.value || '',
        start_date:   form.querySelector('[name="start_date"], #travel-date')?.value || '',
        duration:     form.dataset.duration     || '',
        inclusions:   form.dataset.inclusions   ? JSON.parse(form.dataset.inclusions) : [],
        hotel_class:  form.querySelector('[name="hotel_class"]')?.value || '',
        adults, children,

        customer_name:  form.querySelector('[name="name"],  #traveller-name')?.value  || '',
        customer_email: form.querySelector('[name="email"], #traveller-email')?.value || '',
        customer_phone: form.querySelector('[name="phone"], #traveller-phone')?.value || '',

        base_amount:  parseFloat(form.dataset.baseAmount  || 0),
        total_amount: parseFloat(form.dataset.totalAmount || 0),
        promo_code:   form.querySelector('[name="promo_code"], #promo-input')?.value || '',
        special_requests: form.querySelector('[name="special_requests"]')?.value || '',
      });

    } catch (err) {
      console.error('[Package Form]', err);
    } finally {
      setLoading(btn, false);
    }
  });
}


// ============================================================
//  4. BUS BOOKING FORM
//  Page: buses.html
// ============================================================
function initBusBookingForm() {
  const form = document.getElementById('bus-booking-form');
  if (!form) return;

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = form.querySelector('[type="submit"]');

    const contactOk = validateContactFields(form);
    const dateOk    = validateDateField(form, '[name="date"], #bus-date', 'Travel date');
    if (!contactOk || !dateOk) return;

    setLoading(btn, true);

    try {
      const adults   = parseInt(form.querySelector('[name="adults"],   #bus-adults')?.value   || 1);
      const children = parseInt(form.querySelector('[name="children"], #bus-children')?.value || 0);
      const pricePerSeat = parseFloat(form.dataset.pricePerSeat || form.dataset.price || 0);
      const baseAmount   = pricePerSeat * (adults + children);

      await bookBus({
        from:           form.querySelector('[name="from"],     #bus-from')?.value || '',
        to:             form.querySelector('[name="to"],       #bus-to')?.value   || '',
        date:           form.querySelector('[name="date"],     #bus-date')?.value || '',
        operator:       form.dataset.operator || form.querySelector('[name="operator"]')?.value || '',
        bus_type:       form.dataset.busType  || form.querySelector('[name="bus_type"]')?.value || '',
        departure_time: form.dataset.departureTime || '',
        arrival_time:   form.dataset.arrivalTime   || '',
        seat_numbers:   getSelectedSeats(form),
        adults, children,

        customer_name:  form.querySelector('[name="name"],  #passenger-name')?.value  || '',
        customer_email: form.querySelector('[name="email"], #passenger-email')?.value || '',
        customer_phone: form.querySelector('[name="phone"], #passenger-phone')?.value || '',

        base_amount: baseAmount,
        special_requests: form.querySelector('[name="special_requests"]')?.value || '',
      });

    } catch (err) {
      console.error('[Bus Form]', err);
    } finally {
      setLoading(btn, false);
    }
  });
}

function getSelectedSeats(form) {
  const selected = form.querySelectorAll('.seat.selected, input[name="seat"]:checked');
  return Array.from(selected).map(s => s.dataset.seat || s.value).filter(Boolean);
}


// ============================================================
//  5. CAB BOOKING FORM
//  Page: cabs.html
// ============================================================
function initCabBookingForm() {
  const form = document.getElementById('cab-booking-form');
  if (!form) return;

  // Show/hide return date based on trip type
  const tripTypeInputs = form.querySelectorAll('[name="trip_type"]');
  const returnDateWrap = form.querySelector('#return-date-wrap, .return-date-section');
  tripTypeInputs.forEach(input => {
    input.addEventListener('change', () => {
      if (returnDateWrap) {
        returnDateWrap.style.display = input.value === 'round_trip' ? 'block' : 'none';
      }
    });
  });

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = form.querySelector('[type="submit"]');

    const contactOk = validateContactFields(form);
    const dateOk    = validateDateField(form, '[name="date"], #cab-date', 'Pickup date');
    if (!contactOk || !dateOk) return;

    setLoading(btn, true);

    try {
      const passengers = parseInt(form.querySelector('[name="passengers"], #cab-passengers')?.value || 1);
      const cabType    = form.querySelector('[name="cab_type"], #cab-type, .cab-card.selected')?.value
                      || form.querySelector('[name="cab_type"]')?.value || 'Sedan';
      const tripType   = form.querySelector('[name="trip_type"]:checked, [name="trip_type"]')?.value || 'one_way';
      const baseAmount = parseFloat(form.dataset.price || form.dataset.fareEstimate || 0);

      await bookCab({
        pickup:       form.querySelector('[name="pickup"],  #cab-pickup, [name="from"]')?.value || '',
        drop:         form.querySelector('[name="drop"],    #cab-drop,   [name="to"]')?.value   || '',
        pickup_date:  form.querySelector('[name="date"],    #cab-date')?.value     || '',
        pickup_time:  form.querySelector('[name="time"],    #cab-time')?.value     || '',
        cab_type:     cabType,
        trip_type:    tripType,
        passengers,
        luggage:      form.querySelector('[name="luggage"]')?.value || '',

        customer_name:  form.querySelector('[name="name"],  #rider-name')?.value  || '',
        customer_email: form.querySelector('[name="email"], #rider-email')?.value || '',
        customer_phone: form.querySelector('[name="phone"], #rider-phone')?.value || '',

        base_amount: baseAmount,
        special_requests: form.querySelector('[name="special_requests"]')?.value || '',
      });

    } catch (err) {
      console.error('[Cab Form]', err);
    } finally {
      setLoading(btn, false);
    }
  });
}


// ============================================================
//  AUTO-INIT — detects which page and wires the right form
// ============================================================
document.addEventListener('DOMContentLoaded', () => {
  initFlightBookingForm();
  initHotelBookingForm();
  initPackageBookingForm();
  initBusBookingForm();
  initCabBookingForm();
});
