// ============================================================
// ZoomFly — Supabase Client (FIXED v2)
// ============================================================
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const SUPABASE_URL  = 'https://ndaurluolurdljrjbxii.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5kYXVybHVvbHVyZGxqcmpieGlpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5MDY2MzksImV4cCI6MjA5MzQ4MjYzOX0.JsZXOof19JkyX7asJQ7EtoaBKqURJUYzVqXQIenCzjQ';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON);
export const RAZORPAY_KEY_ID = 'rzp_test_YOUR_KEY_HERE';

// ── Site URL helper (works on localhost AND production) ──
function siteUrl() {
  const h = window.location.hostname;
  if (h === 'localhost' || h === '127.0.0.1') return window.location.origin;
  return 'https://zoomfly.in';
}

export async function signUp({ email, password, fullName, phone }) {
  const { data, error } = await supabase.auth.signUp({
    email, password,
    options: { data: { full_name: fullName, phone } }
  });
  if (error) throw error;
  return data;
}

export async function signIn({ email, password }) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data;
}

// FIX #3: Google OAuth — redirectTo uses siteUrl() not localhost
export async function signInWithGoogle() {
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: {
      redirectTo: siteUrl() + '/pages/dashboard.html',
      queryParams: { prompt: 'select_account' }
    }
  });
  if (error) throw error;
  return data;
}

// FIX #8: signOut — properly clears session and redirects
export async function signOut() {
  try {
    await supabase.auth.signOut({ scope: 'global' });
  } catch(e) { console.warn('signOut error:', e); }
  // Clear any local storage
  Object.keys(localStorage).forEach(k => {
    if (k.startsWith('sb-') || k.includes('supabase')) localStorage.removeItem(k);
  });
  // Redirect to home
  const base = siteUrl();
  window.location.replace(base + '/pages/login.html');
}

export async function getUser() {
  const { data: { user } } = await supabase.auth.getUser();
  return user;
}

export async function getProfile() {
  const user = await getUser();
  if (!user) return null;
  const { data, error } = await supabase.from('profiles').select('*').eq('id', user.id).single();
  if (error) throw error;
  return data;
}

export async function updateProfile(updates) {
  const user = await getUser();
  if (!user) throw new Error('Not logged in');
  const { data, error } = await supabase.from('profiles').update(updates).eq('id', user.id).select().single();
  if (error) throw error;
  return data;
}

export async function requireAuth(redirectTo = '/pages/login.html') {
  const user = await getUser();
  if (!user) { window.location.href = redirectTo; return null; }
  return user;
}

export async function requireAdmin() {
  const profile = await getProfile();
  if (!profile || profile.role !== 'admin') {
    alert('Access denied. Admin only.');
    window.location.href = '/index.html';
    return null;
  }
  return profile;
}

// ── PACKAGES ──────────────────────────────────────────────
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

export async function getPackage(slug) {
  const { data, error } = await supabase.from('packages').select('*, reviews(*)').eq('slug', slug).single();
  if (error) throw error;
  return data;
}

// ── HOTELS ────────────────────────────────────────────────
export async function getHotels({ stars, type, maxPrice, city, search } = {}) {
  let q = supabase.from('hotels').select('*').eq('is_active', true);
  if (stars && stars !== 'all')   q = q.gte('stars', parseInt(stars));
  if (type && type !== 'all')     q = q.eq('type', type);
  if (maxPrice)   q = q.lte('price_per_night', maxPrice);
  if (city)       q = q.ilike('city', `%${city}%`);
  if (search)     q = q.or(`name.ilike.%${search}%,city.ilike.%${search}%`);
  const { data, error } = await q.order('review_count', { ascending: false });
  if (error) throw error;
  return data;
}

// ── BOOKINGS ──────────────────────────────────────────────
export async function createBooking(bookingData) {
  const user = await getUser();
  const payload = { ...bookingData, user_id: user?.id || null };
  const { data, error } = await supabase.from('bookings').insert(payload).select().single();
  if (error) throw error;
  return data;
}

export async function getMyBookings() {
  const user = await getUser();
  if (!user) return [];
  const { data, error } = await supabase
    .from('bookings')
    .select('*')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data;
}

export async function cancelBooking(bookingId, reason = '') {
  const { data, error } = await supabase
    .from('bookings')
    .update({ status: 'cancelled', cancel_reason: reason, cancelled_at: new Date().toISOString() })
    .eq('id', bookingId).select().single();
  if (error) throw error;
  return data;
}

// ── ENQUIRIES ─────────────────────────────────────────────
export async function submitEnquiry(data) {
  const user = await getUser();
  const payload = { ...data, user_id: user?.id || null, source: 'website' };
  const { data: result, error } = await supabase.from('enquiries').insert(payload).select().single();
  if (error) throw error;
  return result;
}

// ── PAYMENTS ──────────────────────────────────────────────
export async function initiatePayment(booking) {
  const { data: orderData, error: orderError } = await supabase.functions.invoke('create-razorpay-order', {
    body: { booking_id: booking.id, amount: booking.total_amount, currency: 'INR' }
  });
  if (orderError) throw orderError;
  return new Promise((resolve, reject) => {
    const options = {
      key: RAZORPAY_KEY_ID, amount: orderData.amount, currency: 'INR',
      name: 'ZoomFly', description: `Booking ${booking.booking_ref}`,
      order_id: orderData.razorpay_order_id,
      prefill: { name: booking.guest_name, email: booking.guest_email, contact: booking.guest_phone },
      theme: { color: '#0057FF' },
      handler: async (response) => {
        const { data: verified, error: verifyErr } = await supabase.functions.invoke('verify-razorpay-payment', {
          body: { booking_id: booking.id, ...response }
        });
        if (verifyErr) { reject(verifyErr); return; }
        resolve(verified);
      },
      modal: { ondismiss: () => reject(new Error('Payment cancelled')) }
    };
    const rzp = new window.Razorpay(options);
    rzp.on('payment.failed', (r) => reject(new Error(r.error.description)));
    rzp.open();
  });
}

// ── PROMO CODES ───────────────────────────────────────────
export async function validatePromoCode(code, orderAmount) {
  const today = new Date().toISOString().split('T')[0];
  const { data, error } = await supabase
    .from('promo_codes').select('*').eq('code', code.toUpperCase()).eq('is_active', true)
    .lte('valid_from', today).or(`valid_until.is.null,valid_until.gte.${today}`).single();
  if (error || !data) throw new Error('Invalid or expired promo code');
  if (data.usage_limit && data.used_count >= data.usage_limit) throw new Error('Promo code usage limit reached');
  if (orderAmount < data.min_order) throw new Error(`Minimum order ₹${data.min_order} required`);
  let discount = data.discount_type === 'percentage'
    ? Math.min((orderAmount * data.discount_value) / 100, data.max_discount || Infinity)
    : data.discount_value;
  return { ...data, calculated_discount: Math.round(discount) };
}

// ── WISHLIST ──────────────────────────────────────────────
export async function addToWishlist(packageId) {
  const user = await getUser();
  if (!user) throw new Error('Please log in to save packages');
  const { error } = await supabase.from('wishlists').insert({ user_id: user.id, package_id: packageId });
  if (error && error.code !== '23505') throw error;
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

// ── REVIEWS ───────────────────────────────────────────────
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

// ── VENDOR REGISTRATION ───────────────────────────────────
export async function registerVendor(vendorData) {
  const user = await getUser();
  const payload = { ...vendorData, user_id: user?.id || null };
  const { data, error } = await supabase.from('vendors').insert(payload).select().single();
  if (error) throw error;
  return data;
}

// ── TRAVEL PARTNER (formerly Agent) REGISTRATION ──────────
export async function registerTravelPartner(partnerData) {
  const user = await getUser();
  const payload = { ...partnerData, user_id: user?.id || null };
  const { data, error } = await supabase.from('agents').insert(payload).select().single();
  if (error) throw error;
  return data;
}

// ── ADMIN ─────────────────────────────────────────────────
export const admin = {
  async getStats() {
    const [{ count: totalBookings }, { count: newEnquiries }, { count: totalCustomers }] = await Promise.all([
      supabase.from('bookings').select('*', { count: 'exact', head: true }),
      supabase.from('enquiries').select('*', { count: 'exact', head: true }).eq('status', 'new'),
      supabase.from('profiles').select('*', { count: 'exact', head: true }).eq('role', 'customer'),
    ]);
    const { data: revenue } = await supabase.from('bookings').select('total_amount').eq('payment_status', 'paid');
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
    let q = supabase.from('bookings').select('*, profiles(full_name, phone)').order('created_at', { ascending: false });
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
  async getAllTravelPartners() {
    const { data, error } = await supabase.from('agents').select('*').order('created_at', { ascending: false });
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
  async getAllCustomers() {
    const { data, error } = await supabase.from('profiles').select('*').eq('role', 'customer').order('created_at', { ascending: false });
    if (error) throw error;
    return data;
  },
  // FIX #14: Get/save site settings (logo, favicon, offers)
  async getSiteSettings() {
    const { data } = await supabase.from('site_settings').select('*').single();
    return data;
  },
  async saveSiteSettings(updates) {
    const { data, error } = await supabase.from('site_settings').upsert({ id: 1, ...updates }).select().single();
    if (error) throw error;
    return data;
  }
};

// ── REALTIME ──────────────────────────────────────────────
export function subscribeToEnquiries(callback) {
  return supabase.channel('enquiries-channel')
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'enquiries' }, callback)
    .subscribe();
}

export function subscribeToBookings(callback) {
  return supabase.channel('bookings-channel')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'bookings' }, callback)
    .subscribe();
}
