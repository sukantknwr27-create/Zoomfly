// ============================================================
// ZoomFly — Supabase Client
// File: js/supabase.js  (place in your project root /js/ folder)
// Import this in every HTML page that needs backend access
// ============================================================

import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

// ── Replace these with your actual Supabase project values ──
// Supabase Dashboard → Settings → API
const SUPABASE_URL  = 'https://ndaurluolurdljrjbxii.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5kYXVybHVvbHVyZGxqcmpieGlpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5MDY2MzksImV4cCI6MjA5MzQ4MjYzOX0.JsZXOof19JkyX7asJQ7EtoaBKqURJUYzVqXQIenCzjQ';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON);

// ── Razorpay Key (get from razorpay.com → Settings → API Keys) ──
export const RAZORPAY_KEY_ID = 'rzp_test_YOUR_KEY_HERE';

// ============================================================
// AUTH HELPERS
// ============================================================

/** Sign up with email + password */
export async function signUp({ email, password, fullName, phone }) {
  const { data, error } = await supabase.auth.signUp({
    email, password,
    options: { data: { full_name: fullName, phone } }
  });
  if (error) throw error;
  return data;
}

/** Sign in with email + password */
export async function signIn({ email, password }) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data;
}

/** Sign in with Google OAuth */
export async function signInWithGoogle() {
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo: window.location.origin + '/pages/dashboard.html' }
  });
  if (error) throw error;
  return data;
}

/** Sign out */
export async function signOut() {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
  window.location.href = '/pages/login.html';
}

/** Get current logged-in user */
export async function getUser() {
  const { data: { user } } = await supabase.auth.getUser();
  return user;
}

/** Get current user's profile */
export async function getProfile() {
  const user = await getUser();
  if (!user) return null;
  const { data, error } = await supabase.from('profiles').select('*').eq('id', user.id).single();
  if (error) throw error;
  return data;
}

/** Update profile */
export async function updateProfile(updates) {
  const user = await getUser();
  if (!user) throw new Error('Not logged in');
  const { data, error } = await supabase.from('profiles').update(updates).eq('id', user.id).select().single();
  if (error) throw error;
  return data;
}

/** Require auth — redirect to login if not signed in */
export async function requireAuth(redirectTo = '/pages/login.html') {
  const user = await getUser();
  if (!user) { window.location.href = redirectTo; return null; }
  return user;
}

/** Require admin role */
export async function requireAdmin() {
  const profile = await getProfile();
  if (!profile || profile.role !== 'admin') {
    alert('Access denied. Admin only.');
    window.location.href = '/index.html';
    return null;
  }
  return profile;
}

// ============================================================
// PACKAGES
// ============================================================

/** Get all active packages with optional filters */
export async function getPackages({ type, category, maxPrice, minRating, search } = {}) {
  let q = supabase.from('packages').select('*').eq('is_active', true);
  if (type && type !== 'all')     q = q.eq('type', type);
  if (category && category !== 'all') q = q.eq('category', category);
  if (maxPrice)   q = q.lte('price', maxPrice);
  if (minRating)  q = q.gte('rating', minRating);
  if (search)     q = q.or(`title.ilike.%${search}%,description.ilike.%${search}%`);
  const { data, error } = await q.order('review_count', { ascending: false });
  if (error) throw error;
  return data;
}

/** Get single package by slug */
export async function getPackage(slug) {
  const { data, error } = await supabase.from('packages').select('*, reviews(*)').eq('slug', slug).single();
  if (error) throw error;
  return data;
}

// ============================================================
// HOTELS
// ============================================================

/** Get all active hotels with optional filters */
export async function getHotels({ stars, type, maxPrice, city, search, amenities } = {}) {
  let q = supabase.from('hotels').select('*').eq('is_active', true);
  if (stars && stars !== 'all')   q = q.gte('stars', parseInt(stars));
  if (type && type !== 'all')     q = q.eq('type', type);
  if (maxPrice)   q = q.lte('price_per_night', maxPrice);
  if (city)       q = q.ilike('city', `%${city}%`);
  if (search)     q = q.or(`name.ilike.%${search}%,location.ilike.%${search}%,city.ilike.%${search}%`);
  const { data, error } = await q.order('review_count', { ascending: false });
  if (error) throw error;
  return data;
}

// ============================================================
// ENQUIRIES
// ============================================================

/** Submit a contact/quote enquiry */
export async function submitEnquiry(data) {
  const user = await getUser();
  const payload = {
    ...data,
    user_id: user?.id || null,
    source: 'website'
  };
  const { data: result, error } = await supabase.from('enquiries').insert(payload).select().single();
  if (error) throw error;
  return result;
}

// ============================================================
// BOOKINGS
// ============================================================

/** Create a new booking (works for both logged-in and guest users) */
export async function createBooking(bookingData) {
  const user = await getUser();
  const payload = { ...bookingData, user_id: user?.id || null };
  const { data, error } = await supabase.from('bookings').insert(payload).select().single();
  if (error) throw error;
  return data;
}

/** Get current user's bookings */
export async function getMyBookings() {
  const user = await getUser();
  if (!user) return [];
  const { data, error } = await supabase
    .from('bookings')
    .select('*, packages(title, emoji), hotels(name, emoji)')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data;
}

/** Cancel a booking */
export async function cancelBooking(bookingId, reason = '') {
  const { data, error } = await supabase
    .from('bookings')
    .update({ status: 'cancelled', cancel_reason: reason, cancelled_at: new Date().toISOString() })
    .eq('id', bookingId)
    .select().single();
  if (error) throw error;
  return data;
}

// ============================================================
// PAYMENTS — Razorpay
// ============================================================

/**
 * Initiate Razorpay payment for a booking
 * 1. Creates a Razorpay order via Supabase Edge Function
 * 2. Opens Razorpay checkout modal
 * 3. On success, verifies signature & updates booking
 */
export async function initiatePayment(booking) {
  // Step 1: Create Razorpay order via Edge Function
  const { data: orderData, error: orderError } = await supabase.functions.invoke('create-razorpay-order', {
    body: { booking_id: booking.id, amount: booking.total_amount, currency: 'INR' }
  });
  if (orderError) throw orderError;

  // Step 2: Open Razorpay checkout
  return new Promise((resolve, reject) => {
    const options = {
      key: RAZORPAY_KEY_ID,
      amount: orderData.amount,
      currency: 'INR',
      name: 'ZoomFly',
      description: `Booking ${booking.booking_ref}`,
      order_id: orderData.razorpay_order_id,
      prefill: {
        name: booking.guest_name,
        email: booking.guest_email,
        contact: booking.guest_phone
      },
      theme: { color: '#0057FF' },
      handler: async (response) => {
        // Step 3: Verify payment via Edge Function
        const { data: verified, error: verifyErr } = await supabase.functions.invoke('verify-razorpay-payment', {
          body: {
            booking_id: booking.id,
            razorpay_order_id: response.razorpay_order_id,
            razorpay_payment_id: response.razorpay_payment_id,
            razorpay_signature: response.razorpay_signature
          }
        });
        if (verifyErr) { reject(verifyErr); return; }
        resolve(verified);
      },
      modal: { ondismiss: () => reject(new Error('Payment cancelled by user')) }
    };
    const rzp = new window.Razorpay(options);
    rzp.on('payment.failed', (resp) => reject(new Error(resp.error.description)));
    rzp.open();
  });
}

// ============================================================
// PROMO CODES
// ============================================================

/** Validate a promo code and return discount info */
export async function validatePromoCode(code, orderAmount) {
  const { data, error } = await supabase
    .from('promo_codes')
    .select('*')
    .eq('code', code.toUpperCase())
    .eq('is_active', true)
    .lte('valid_from', new Date().toISOString().split('T')[0])
    .or(`valid_until.is.null,valid_until.gte.${new Date().toISOString().split('T')[0]}`)
    .single();
  if (error || !data) throw new Error('Invalid or expired promo code');
  if (data.usage_limit && data.used_count >= data.usage_limit) throw new Error('Promo code usage limit reached');
  if (orderAmount < data.min_order) throw new Error(`Minimum order ₹${data.min_order} required for this code`);

  let discount = 0;
  if (data.discount_type === 'percentage') {
    discount = (orderAmount * data.discount_value) / 100;
    if (data.max_discount) discount = Math.min(discount, data.max_discount);
  } else {
    discount = data.discount_value;
  }
  return { ...data, calculated_discount: Math.round(discount) };
}

// ============================================================
// WISHLIST
// ============================================================

export async function addToWishlist(packageId) {
  const user = await getUser();
  if (!user) throw new Error('Please log in to save packages');
  const { error } = await supabase.from('wishlists').insert({ user_id: user.id, package_id: packageId });
  if (error && error.code !== '23505') throw error; // ignore duplicate
}

export async function removeFromWishlist(packageId) {
  const user = await getUser();
  if (!user) return;
  await supabase.from('wishlists').delete().eq('user_id', user.id).eq('package_id', packageId);
}

export async function getWishlist() {
  const user = await getUser();
  if (!user) return [];
  const { data, error } = await supabase.from('wishlists').select('package_id, packages(*)').eq('user_id', user.id);
  if (error) throw error;
  return data.map(w => w.packages);
}

// ============================================================
// REVIEWS
// ============================================================

export async function submitReview({ packageId, hotelId, bookingId, rating, title, body }) {
  const user = await getUser();
  if (!user) throw new Error('Please log in to submit a review');
  const { data, error } = await supabase.from('reviews').insert({
    user_id: user.id, package_id: packageId, hotel_id: hotelId,
    booking_id: bookingId, rating, title, body
  }).select().single();
  if (error) throw error;
  return data;
}

// ============================================================
// VENDOR REGISTRATION
// ============================================================

export async function registerVendor(vendorData) {
  const user = await getUser();
  const payload = { ...vendorData, user_id: user?.id || null };
  const { data, error } = await supabase.from('vendors').insert(payload).select().single();
  if (error) throw error;
  return data;
}

// ============================================================
// ADMIN — (admin-only functions)
// ============================================================

export const admin = {
  async getStats() {
    const [
      { count: totalBookings },
      { count: newEnquiries },
      { count: totalCustomers },
    ] = await Promise.all([
      supabase.from('bookings').select('*', { count: 'exact', head: true }),
      supabase.from('enquiries').select('*', { count: 'exact', head: true }).eq('status', 'new'),
      supabase.from('profiles').select('*', { count: 'exact', head: true }).eq('role', 'customer'),
    ]);

    const { data: revenue } = await supabase
      .from('bookings')
      .select('total_amount')
      .eq('payment_status', 'paid');

    const totalRevenue = revenue?.reduce((s, b) => s + Number(b.total_amount), 0) || 0;

    return { totalBookings, newEnquiries, totalCustomers, totalRevenue };
  },

  async getAllEnquiries(status = null) {
    let q = supabase.from('enquiries').select('*').order('created_at', { ascending: false });
    if (status) q = q.eq('status', status);
    const { data, error } = await q;
    if (error) throw error;
    return data;
  },

  async updateEnquiryStatus(id, status, notes = '') {
    const { data, error } = await supabase.from('enquiries').update({ status, notes }).eq('id', id).select().single();
    if (error) throw error;
    return data;
  },

  async getAllBookings(status = null) {
    let q = supabase.from('bookings')
      .select('*, packages(title), hotels(name), profiles(full_name, phone)')
      .order('created_at', { ascending: false });
    if (status) q = q.eq('status', status);
    const { data, error } = await q;
    if (error) throw error;
    return data;
  },

  async updateBookingStatus(id, status) {
    const updates = { status };
    if (status === 'confirmed') updates.confirmed_at = new Date().toISOString();
    if (status === 'cancelled') updates.cancelled_at = new Date().toISOString();
    const { data, error } = await supabase.from('bookings').update(updates).eq('id', id).select().single();
    if (error) throw error;
    return data;
  },

  async getAllVendors() {
    const { data, error } = await supabase.from('vendors').select('*').order('created_at', { ascending: false });
    if (error) throw error;
    return data;
  },

  async approveVendor(id) {
    const { data, error } = await supabase.from('vendors')
      .update({ status: 'approved', verified_at: new Date().toISOString() }).eq('id', id).select().single();
    if (error) throw error;
    return data;
  },

  async createPackage(pkg) {
    const { data, error } = await supabase.from('packages').insert(pkg).select().single();
    if (error) throw error;
    return data;
  },

  async updatePackage(id, updates) {
    const { data, error } = await supabase.from('packages').update(updates).eq('id', id).select().single();
    if (error) throw error;
    return data;
  },

  async togglePackageStatus(id, isActive) {
    return admin.updatePackage(id, { is_active: isActive });
  },

  async getAllCustomers() {
    const { data, error } = await supabase
      .from('profiles')
      .select('*, bookings(count)')
      .eq('role', 'customer')
      .order('created_at', { ascending: false });
    if (error) throw error;
    return data;
  }
};

// ============================================================
// REALTIME — Live admin notifications
// ============================================================

/** Subscribe to new enquiries (admin dashboard live updates) */
export function subscribeToEnquiries(callback) {
  return supabase
    .channel('enquiries-channel')
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'enquiries' }, callback)
    .subscribe();
}

/** Subscribe to new bookings */
export function subscribeToBookings(callback) {
  return supabase
    .channel('bookings-channel')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'bookings' }, callback)
    .subscribe();
}
