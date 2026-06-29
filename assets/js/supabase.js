// ============================================================
// ZoomFly — Supabase Client (COMPLETE v4)
// ============================================================
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const SUPABASE_URL  = 'https://ndaurluolurdljrjbxii.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5kYXVybHVvbHVyZGxqcmpieGlpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5MDY2MzksImV4cCI6MjA5MzQ4MjYzOX0.JsZXOof19JkyX7asJQ7EtoaBKqURJUYzVqXQIenCzjQ';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON);
// Razorpay Key ID — loaded at runtime from /api/config so it is NEVER hardcoded in source.
// Fallback to empty string; pages check for empty and show WhatsApp booking instead.
let _razorpayKeyId = '';
export function getRazorpayKeyId() { return _razorpayKeyId; }

// Fetch the publishable key from the server (Vercel edge config / env var)
(async () => {
  try {
    const res = await fetch('/api/config');
    if (res.ok) {
      const cfg = await res.json();
      _razorpayKeyId = cfg.razorpay_key_id || '';
    }
  } catch (_) {
    // Silently fail — pages will fall back to WhatsApp booking when key is empty
  }
})();

// Legacy export kept for backward-compat — always returns '' until fetch resolves.
// Prefer getRazorpayKeyId() after awaiting the module init.
export const RAZORPAY_KEY_ID = '';

function siteUrl() {
  const h = window.location.hostname;
  if (h === 'localhost' || h === '127.0.0.1') return window.location.origin;
  return 'https://www.zoomfly.in';
}

// ── AUTH ──────────────────────────────────────────────────
export async function signUp({ email, password, fullName, phone }) {
  const { data, error } = await supabase.auth.signUp({
    email, password,
    options: { data: { full_name: fullName, phone } }
  });
  if (error) throw error;
  // Track referral if present
  const ref = sessionStorage.getItem('zf_ref');
  if (ref && data.user) {
    await supabase.from('referrals').insert({
      referee_id: data.user.id, referee_email: email,
      referee_name: fullName, referral_code: ref, status: 'signed_up'
    }).catch(() => {});
  }
  return data;
}

export async function signIn({ email, password }) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data;
}

export async function signInWithGoogle() {
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo: siteUrl() + '/pages/dashboard.html', queryParams: { prompt: 'select_account' } }
  });
  if (error) throw error;
  return data;
}

export async function signOut() {
  try { await supabase.auth.signOut({ scope: 'global' }); } catch(e) {}
  Object.keys(localStorage).forEach(k => { if (k.startsWith('sb-') || k.includes('supabase')) localStorage.removeItem(k); });
  window.location.replace(siteUrl() + '/pages/login.html');
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
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { window.location.replace('/pages/admin-login.html'); return null; }
    const metaRole = user.app_metadata?.role || user.user_metadata?.role;
    if (metaRole === 'admin') return { role: 'admin', ...user };
    const profile = await getProfile().catch(() => null);
    if (profile?.role === 'admin') return profile;
    window.location.replace('/pages/admin-login.html?reason=access_denied');
    return null;
  } catch(e) {
    window.location.replace('/pages/admin-login.html?reason=error');
    return null;
  }
}

// ── PACKAGES ─────────────────────────────────────────────
export async function getPackages({ type, category, maxPrice, minRating, search, limit } = {}) {
  let q = supabase.from('packages').select('*').eq('is_active', true);
  if (type && type !== 'all')         q = q.eq('type', type);
  if (category && category !== 'all') q = q.eq('category', category);
  if (maxPrice)                       q = q.lte('price', maxPrice);
  if (minRating)                      q = q.gte('rating', minRating);
  if (search)                         q = q.or(`title.ilike.%${search}%,description.ilike.%${search}%`);
  if (limit)                          q = q.limit(limit);
  const { data, error } = await q.order('review_count', { ascending: false });
  if (error) throw error;
  return data;
}

export async function getPackage(slug) {
  const { data, error } = await supabase.from('packages').select('*, reviews(*)').eq('slug', slug).single();
  if (error) throw error;
  return data;
}

// ── AVAILABILITY ──────────────────────────────────────────
export async function checkAvailability(packageId, date) {
  const { data } = await supabase.from('package_availability')
    .select('*').eq('package_id', packageId).eq('date', date).single();
  return data; // null = available
}

export async function blockDate(packageId, date, reason = '') {
  const { error } = await supabase.from('package_availability')
    .upsert({ package_id: packageId, date, is_blocked: true, reason });
  if (error) throw error;
}

// ── HOTELS ───────────────────────────────────────────────
export async function getHotels({ stars, maxPrice, city, search } = {}) {
  let q = supabase.from('hotels').select('*').eq('is_active', true);
  if (stars && stars !== 'all') q = q.gte('stars', parseInt(stars));
  if (maxPrice)   q = q.lte('price_per_night', maxPrice);
  if (city)       q = q.ilike('city', `%${city}%`);
  if (search)     q = q.or(`name.ilike.%${search}%,city.ilike.%${search}%`);
  const { data, error } = await q.order('stars', { ascending: false });
  if (error) throw error;
  return data;
}

// ── BOOKINGS ─────────────────────────────────────────────
export async function createBooking(bookingData) {
  const user = await getUser();
  const payload = { ...bookingData, user_id: user?.id || null };
  const { data, error } = await supabase.from('bookings').insert(payload).select().single();
  if (error) throw error;
  if (!data?.booking_ref) throw new Error('Booking created but no booking reference was returned. Please contact support.');
  // Award loyalty points
  if (user && data.total_amount > 0) {
    await awardLoyaltyPoints(user.id, Math.floor(data.total_amount / 100), data.id).catch(() => {});
  }
  return data;
}

export async function getMyBookings() {
  const user = await getUser();
  if (!user) return [];
  const { data, error } = await supabase.from('bookings').select('*')
    .eq('user_id', user.id).order('created_at', { ascending: false });
  if (error) throw error;
  return data;
}

export async function cancelBooking(bookingId, reason = '') {
  const { data, error } = await supabase.from('bookings')
    .update({ status: 'cancelled', cancel_reason: reason, cancelled_at: new Date().toISOString() })
    .eq('id', bookingId).select().single();
  if (error) throw error;
  return data;
}

export async function requestBookingModification(bookingId, changes, reason) {
  const { data, error } = await supabase.from('booking_modifications').insert({
    booking_id: bookingId, requested_changes: changes,
    reason, status: 'pending', created_at: new Date().toISOString()
  }).select().single();
  if (error) throw error;
  return data;
}

// ── PAYMENT LINKS ────────────────────────────────────────
export async function createPaymentLink({ bookingId, amount, customerName, customerEmail, customerPhone, description }) {
  const { data, error } = await supabase.from('payment_links').insert({
    booking_id: bookingId, amount, customer_name: customerName,
    customer_email: customerEmail, customer_phone: customerPhone,
    description, status: 'active', expires_at: new Date(Date.now() + 7 * 86400000).toISOString(),
    created_at: new Date().toISOString()
  }).select().single();
  if (error) throw error;
  // Generate WhatsApp link for sharing
  const link = `${siteUrl()}/pages/payment.html?ref=${data.id}`;
  return { ...data, payment_url: link };
}

export async function getPaymentLink(id) {
  const { data, error } = await supabase.from('payment_links').select('*, bookings(*)').eq('id', id).single();
  if (error) throw error;
  return data;
}

// ── TRAVEL DOCUMENTS ─────────────────────────────────────
export async function saveTravelDocument(doc) {
  const user = await getUser();
  if (!user) throw new Error('Not logged in');
  const { data, error } = await supabase.from('travel_documents').upsert({
    ...doc, user_id: user.id, updated_at: new Date().toISOString()
  }).select().single();
  if (error) throw error;
  return data;
}

export async function getTravelDocuments() {
  const user = await getUser();
  if (!user) return [];
  const { data, error } = await supabase.from('travel_documents').select('*').eq('user_id', user.id);
  if (error) throw error;
  return data || [];
}

// ── CO-TRAVELLERS ────────────────────────────────────────
export async function saveCotraveller(traveller) {
  const user = await getUser();
  if (!user) throw new Error('Not logged in');
  const { data, error } = await supabase.from('cotravellers').upsert({
    ...traveller, user_id: user.id
  }).select().single();
  if (error) throw error;
  return data;
}

export async function getCotravellers() {
  const user = await getUser();
  if (!user) return [];
  const { data } = await supabase.from('cotravellers').select('*').eq('user_id', user.id);
  return data || [];
}

export async function deleteCotraveller(id) {
  await supabase.from('cotravellers').delete().eq('id', id);
}

// ── PRICE ALERTS ─────────────────────────────────────────
export async function setPriceAlert(packageId, targetPrice) {
  const user = await getUser();
  if (!user) throw new Error('Please log in to set price alerts');
  const { data, error } = await supabase.from('price_alerts').upsert({
    user_id: user.id, package_id: packageId, target_price: targetPrice,
    is_active: true, created_at: new Date().toISOString()
  }, { onConflict: 'user_id,package_id' }).select().single();
  if (error) throw error;
  return data;
}

export async function getPriceAlerts() {
  const user = await getUser();
  if (!user) return [];
  const { data } = await supabase.from('price_alerts').select('*, packages(title,price,emoji)').eq('user_id', user.id).eq('is_active', true);
  return data || [];
}

// ── MESSAGES ─────────────────────────────────────────────
export async function sendMessage({ bookingId, body, attachmentUrl }) {
  const user = await getUser();
  if (!user) throw new Error('Not logged in');
  const { data, error } = await supabase.from('messages').insert({
    booking_id: bookingId, sender_id: user.id,
    sender_type: 'customer', body, attachment_url: attachmentUrl || null,
    created_at: new Date().toISOString()
  }).select().single();
  if (error) throw error;
  return data;
}

export async function getMessages(bookingId) {
  const { data, error } = await supabase.from('messages').select('*')
    .eq('booking_id', bookingId).order('created_at', { ascending: true });
  if (error) throw error;
  return data || [];
}

export function subscribeToMessages(bookingId, callback) {
  return supabase.channel(`messages-${bookingId}`)
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages', filter: `booking_id=eq.${bookingId}` }, callback)
    .subscribe();
}

// ── TRAIN BOOKING ────────────────────────────────────────
export async function searchTrains({ from, to, date, quota = 'GN' }) {
  // Store enquiry in DB for admin followup
  const user = await getUser();
  const { data } = await supabase.from('train_enquiries').insert({
    user_id: user?.id || null,
    from_station: from, to_station: to,
    travel_date: date, quota,
    status: 'new', created_at: new Date().toISOString()
  }).select().single().catch(() => ({ data: null }));
  return data;
}

export async function bookTrain(trainData) {
  const user = await getUser();
  const { data, error } = await supabase.from('bookings').insert({
    user_id: user?.id || null,
    service_type: 'train',
    service_name: `${trainData.train_name} · ${trainData.from} → ${trainData.to}`,
    customer_name: trainData.passenger_name,
    customer_phone: trainData.phone,
    customer_email: trainData.email,
    total_amount: trainData.fare,
    status: 'pending', payment_status: 'pending',
    travel_details: trainData,
    booking_source: 'website'
  }).select().single();
  if (error) throw error;
  return data;
}

// ── LOYALTY ──────────────────────────────────────────────
export async function awardLoyaltyPoints(userId, points, bookingId) {
  const { data: acct } = await supabase.from('loyalty_accounts').select('*').eq('user_id', userId).single();
  if (!acct) return;
  await supabase.from('loyalty_accounts').update({
    points_balance: (acct.points_balance || 0) + points,
    total_points_earned: (acct.total_points_earned || 0) + points,
  }).eq('user_id', userId);
  await supabase.from('loyalty_transactions').insert({
    account_id: acct.id, txn_type: 'earn', points,
    description: `Earned for booking`, booking_id: bookingId
  });
}

export async function validatePromoCode(code, orderAmount) {
  const today = new Date().toISOString().split('T')[0];
  const { data, error } = await supabase.from('promo_codes').select('*')
    .eq('code', code.toUpperCase()).eq('is_active', true)
    .single();
  if (error || !data) throw new Error('Invalid or expired promo code');
  if (data.expires_at && new Date(data.expires_at) < new Date()) throw new Error('Promo code has expired');
  if (data.max_uses && (data.times_used || 0) >= data.max_uses) throw new Error('Promo code usage limit reached');
  if (orderAmount < (data.min_order_amount || 0)) throw new Error(`Minimum order ₹${data.min_order_amount} required`);
  const discount = data.discount_type === 'percentage'
    ? Math.round(orderAmount * data.discount_value / 100)
    : data.discount_value;
  return { ...data, calculated_discount: discount };
}

// ── ENQUIRIES ────────────────────────────────────────────
export async function submitEnquiry(data) {
  const user = await getUser();
  const payload = { ...data, user_id: user?.id || null, source: 'website' };
  const { data: result, error } = await supabase.from('enquiries').insert(payload).select().single();
  if (error) throw error;
  return result;
}

// ── WISHLIST ─────────────────────────────────────────────
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
  return (data || []).map(w => w.packages).filter(Boolean);
}

// ── REVIEWS ──────────────────────────────────────────────
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

// ── VENDOR / AGENT REGISTRATION ──────────────────────────
export async function registerVendor(vendorData) {
  const user = await getUser();
  const { data, error } = await supabase.from('vendors').insert({ ...vendorData, user_id: user?.id || null }).select().single();
  if (error) throw error;
  return data;
}

export async function registerTravelPartner(partnerData) {
  const user = await getUser();
  const { data, error } = await supabase.from('agents').insert({ ...partnerData, user_id: user?.id || null }).select().single();
  if (error) throw error;
  return data;
}

// ── NEWSLETTER ───────────────────────────────────────────
export async function subscribeNewsletter(email, source = 'website') {
  const { error } = await supabase.from('newsletter_subscribers')
    .insert({ email, source, subscribed_at: new Date().toISOString() });
  if (error && error.code !== '23505') throw error;
  return { alreadySubscribed: error?.code === '23505' };
}

// ── ADMIN ─────────────────────────────────────────────────
export const admin = {
  async getStats() {
    const [bookRes, enqRes, custRes, revRes] = await Promise.allSettled([
      supabase.from('bookings').select('*', { count: 'exact', head: true }),
      supabase.from('enquiries').select('*', { count: 'exact', head: true }).eq('status', 'new'),
      supabase.from('profiles').select('*',  { count: 'exact', head: true }),
      supabase.from('bookings').select('total_amount').eq('payment_status', 'paid'),
    ]);
    const totalBookings  = bookRes.status  === 'fulfilled' ? (bookRes.value.count  || 0) : 0;
    const newEnquiries   = enqRes.status   === 'fulfilled' ? (enqRes.value.count   || 0) : 0;
    const totalCustomers = custRes.status  === 'fulfilled' ? (custRes.value.count  || 0) : 0;
    const revenue        = revRes.status   === 'fulfilled' ? (revRes.value.data    || []) : [];
    const totalRevenue   = revenue.reduce((s, b) => s + Number(b.total_amount || 0), 0);
    return { totalBookings, newEnquiries, totalCustomers, totalRevenue };
  },
  async getAllEnquiries(status = null) {
    let q = supabase.from('enquiries').select('*').order('created_at', { ascending: false });
    if (status) q = q.eq('status', status);
    const { data, error } = await q;
    if (error) throw error;
    return data || [];
  },
  async updateEnquiryStatus(id, status, notes = '') {
    const { data, error } = await supabase.from('enquiries').update({ status, notes }).eq('id', id).select().single();
    if (error) throw error;
    return data;
  },
  async getAllBookings(status = null) {
    let q = supabase.from('bookings').select('*').order('created_at', { ascending: false });
    if (status) q = q.eq('status', status);
    const { data, error } = await q;
    if (error) throw error;
    return data || [];
  },
  async updateBookingStatus(id, status) {
    const updates = { status };
    if (status === 'confirmed') updates.confirmed_at = new Date().toISOString();
    if (status === 'cancelled') updates.cancelled_at = new Date().toISOString();
    const { data, error } = await supabase.from('bookings').update(updates).eq('id', id).select().single();
    if (error) throw error;
    return data;
  },
  async createManualBooking(bookingData) {
    const { data, error } = await supabase.from('bookings').insert({
      ...bookingData, booking_source: 'admin_manual',
      created_at: new Date().toISOString()
    }).select().single();
    if (error) throw error;
    return data;
  },
  async generatePaymentLink(params) {
    return createPaymentLink(params);
  },
  async getAllCustomers() {
    const { data, error } = await supabase.from('profiles').select('*').order('created_at', { ascending: false });
    if (error) throw error;
    return data || [];
  },
  async getCustomerBookings(userId) {
    const { data, error } = await supabase.from('bookings').select('*').eq('user_id', userId).order('created_at', { ascending: false });
    if (error) throw error;
    return data || [];
  },
  async exportBookingsCSV(filters = {}) {
    let q = supabase.from('bookings').select('*').order('created_at', { ascending: false });
    if (filters.status) q = q.eq('status', filters.status);
    if (filters.from)   q = q.gte('created_at', filters.from);
    if (filters.to)     q = q.lte('created_at', filters.to);
    const { data, error } = await q;
    if (error) throw error;
    return data || [];
  },
  async sendBroadcast({ subject, message, recipients }) {
    const { data, error } = await supabase.from('broadcasts').insert({
      subject, message, recipient_type: recipients,
      sent_at: new Date().toISOString(), status: 'sent'
    }).select().single();
    if (error) throw error;
    return data;
  },
  async getAllVendors() {
    const { data, error } = await supabase.from('vendors').select('*').order('created_at', { ascending: false });
    if (error) throw error;
    return data || [];
  },
  async approveVendor(id) {
    const { data, error } = await supabase.from('vendors').update({ status: 'approved', verified_at: new Date().toISOString() }).eq('id', id).select().single();
    if (error) throw error;
    return data;
  },
  async getAllTravelPartners() {
    const { data, error } = await supabase.from('agents').select('*').order('created_at', { ascending: false });
    if (error) throw error;
    return data || [];
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
  async getSiteSettings() {
    const { data } = await supabase.from('site_settings').select('*').eq('id', 1).single();
    return data;
  },
  async saveSiteSettings(updates) {
    const { data, error } = await supabase.from('site_settings').upsert({ id: 1, ...updates }).select().single();
    if (error) throw error;
    return data;
  }
};

// ── NAV LOADER ───────────────────────────────────────────
export async function loadNav(activePage = '') {
  // Delegate entirely to renderNav() from main.js to avoid double-injection (Fix #7)
  // and ensure correct nav.html IDs are used (Fix #5).
  if (typeof window._zfRenderNav === 'function') {
    await window._zfRenderNav(activePage);
    return;
  }
  // Fallback: if main.js hasn't loaded yet (e.g. admin pages that import supabase.js
  // directly), do a minimal render using the correct nav.html IDs.
  const nav = document.getElementById('mainNav');
  if (!nav) return;
  try {
    const res = await fetch('/assets/nav.html');
    if (!res.ok) throw new Error('nav fetch failed');
    nav.innerHTML = await res.text();
  } catch {
    nav.innerHTML = '<nav style="background:#0C1B33;padding:14px 20px;display:flex;align-items:center;justify-content:space-between"><a href="/" style="color:#fff;font-weight:800;text-decoration:none;font-size:1.1rem">ZoomFly ✈</a></nav>';
  }
  if (activePage) {
    const link = nav.querySelector(`[data-page="${activePage}"]`);
    if (link) link.style.color = 'var(--gold-light,#E8B84B)';
  }
  const hamburger = document.getElementById('hamburger');
  const mobileMenu = document.getElementById('mobileMenu');
  if (hamburger && mobileMenu) {
    hamburger.addEventListener('click', function () {
      this.classList.toggle('open');
      mobileMenu.classList.toggle('open');
    });
  }
  // Wire data-action events using correct nav.html IDs
  nav.addEventListener('click', e => {
    const btn = e.target.closest('[data-action]');
    if (!btn) return;
    if (btn.dataset.action === 'toggle-user-menu') {
      e.stopPropagation();
      const d = document.getElementById('nav-dropdown');
      if (d) d.style.display = d.style.display === 'block' ? 'none' : 'block';
    }
    if (btn.dataset.action === 'sign-out') {
      e.preventDefault();
      signOut().then(() => { window.location.href = '/pages/login.html'; }).catch(() => {});
    }
  });
  document.addEventListener('click', e => {
    if (!e.target.closest('#nav-user-menu')) {
      const d = document.getElementById('nav-dropdown');
      if (d) d.style.display = 'none';
    }
  });
  // Auth state using correct IDs
  const user = await getUser();
  const loginBtn  = document.getElementById('nav-login-btn');
  const signupBtn = document.getElementById('nav-signup-btn');
  const userMenu  = document.getElementById('nav-user-menu');
  if (user) {
    if (loginBtn)  loginBtn.style.display  = 'none';
    if (signupBtn) signupBtn.style.display = 'none';
    if (userMenu)  userMenu.style.display  = 'block';
    const profile = await getProfile();
    const name = profile?.full_name || user.email?.split('@')[0] || 'Account';
    const avatar   = document.getElementById('nav-avatar');
    const username = document.getElementById('nav-username');
    if (avatar)   avatar.textContent   = name.charAt(0).toUpperCase();
    if (username) username.textContent = name.split(' ')[0];
  } else {
    if (loginBtn)  loginBtn.style.display  = '';
    if (signupBtn) signupBtn.style.display = '';
    if (userMenu)  userMenu.style.display  = 'none';
  }
}

// ── REALTIME ─────────────────────────────────────────────
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
