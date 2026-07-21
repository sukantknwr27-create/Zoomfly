// ============================================================
// ZoomFly — Supabase Client (COMPLETE v4)
// ============================================================
// Self-hosted instead of loaded from a CDN — see assets/js/vendor/supabase-js.esm.min.js
// for why (a CDN outage or blocked host used to take down every page's
// login/booking/payment/admin flow with no fallback, since this import
// failing aborts the whole module and nothing after it runs).
import { createClient } from './vendor/supabase-js.esm.min.js';

const SUPABASE_URL  = 'https://ndaurluolurdljrjbxii.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5kYXVybHVvbHVyZGxqcmpieGlpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5MDY2MzksImV4cCI6MjA5MzQ4MjYzOX0.JsZXOof19JkyX7asJQ7EtoaBKqURJUYzVqXQIenCzjQ';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON, {
  auth: {
    persistSession:    true,
    autoRefreshToken:  true,
    detectSessionInUrl: true,
    storageKey: 'zoomfly-auth',          // same key on all subdomains
    storage: typeof window !== 'undefined' ? window.localStorage : undefined,
  },
  global: {
    headers: { 'x-application': 'zoomfly-web' },
  },
});

// ── TIMEOUT WRAPPER ──────────────────────────────────────────
// supabase.auth.getUser() can hang indefinitely if the network stalls
// or the refresh-token exchange never resolves. Every auth call in this
// file is wrapped so it ALWAYS settles within `ms`, treating a timeout
// as "not logged in" rather than freezing the page forever.
function withTimeout(promise, ms = 6000, fallback = { data: { user: null } }) {
  return Promise.race([
    promise,
    new Promise(resolve => setTimeout(() => resolve(fallback), ms)),
  ]);
}

async function safeGetUser() {
  try {
    const result = await withTimeout(supabase.auth.getUser(), 6000);
    return result?.data?.user || null;
  } catch (e) {
    console.warn('[supabase] getUser failed:', e?.message);
    return null;
  }
}
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
  // Link the referral if present — this only records who referred whom
  // (loyalty_accounts.referred_by). The actual 500/250-point bonus is
  // awarded later, at the referee's first qualifying (>= ₹5,000)
  // booking, inside earn_booking_points() — matching what referral.html
  // has always advertised ("...when they make their first booking").
  // There is no `referrals` table — a prior version of this function
  // inserted into one that was never actually created by any migration,
  // so every referral silently failed to record at all.
  const ref = sessionStorage.getItem('zf_ref');
  if (ref && data.user) {
    await supabase.rpc('link_referral', {
      p_referrer_code: ref,
      p_new_user_id: data.user.id,
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

export async function signOut(redirectTo) {
  try { await supabase.auth.signOut({ scope: 'global' }); } catch(e) {}
  Object.keys(localStorage).forEach(k => { if (k.startsWith('sb-') || k.includes('supabase')) localStorage.removeItem(k); });
  // If a redirect is specified, use it; otherwise detect admin vs public context
  if (redirectTo) { window.location.replace(redirectTo); return; }
  const isAdminPage = window.location.pathname.includes('admin');
  window.location.replace(isAdminPage
    ? '/pages/admin-login.html'
    : siteUrl() + '/pages/login.html'
  );
}

export async function getUser() {
  return await safeGetUser();
}

export async function getProfile() {
  const user = await getUser();
  if (!user) return null;
  const { data, error } = await supabase.from('profiles').select('*').eq('id', user.id).maybeSingle();
  if (error) throw error;
  if (data) return data;
  // Self-heal: no profile row exists for this authenticated user (e.g.
  // the account was created directly in Supabase Auth rather than
  // through the app's signup flow, so the on_auth_user_created trigger
  // never ran). Previously this fell through to .single() throwing
  // "Cannot coerce the result to a single JSON object" — which is what
  // surfaced as the broadcast-send error in admin. Create the row now.
  const { data: created, error: createErr } = await supabase.from('profiles')
    .insert({ id: user.id, full_name: user.user_metadata?.full_name || user.email?.split('@')[0] || 'User', role: user.app_metadata?.role || 'customer' })
    .select().maybeSingle();
  if (createErr) { console.warn('[getProfile] could not self-heal missing profile row:', createErr.message); return null; }
  return created;
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
    const user = await safeGetUser();
    if (!user) { window.location.replace('/pages/admin-login.html?reason=auth_required'); return null; }
    // Only app_metadata is trustworthy here — it can only be set via
    // the Supabase admin API (service_role), never by the signed-in
    // user themselves. user_metadata is intentionally user-editable
    // (anyone can call supabase.auth.updateUser({data:{role:'admin'}})
    // from the browser console), so it must never be used for an
    // authorization decision — it was previously checked here too,
    // which let a non-admin get the admin UI shell to render (though
    // real data was still protected server-side by RLS/is_admin()).
    if (user.app_metadata?.role === 'admin') return { role: 'admin', ...user };
    const profile = await withTimeout(getProfile(), 5000, null).catch(() => null);
    if (profile?.role === 'admin') return profile;
    window.location.replace('/pages/admin-login.html?reason=access_denied');
    return null;
  } catch(e) {
    console.warn('[requireAdmin] error:', e?.message);
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
  // Loyalty points are awarded server-side once the booking is actually
  // paid (see verify-razorpay-payment edge function) — not here, where
  // the booking row is still payment_status:'pending'. Awarding on
  // creation would credit points for bookings nobody ever paid for, and
  // earn_booking_points() rejects unpaid bookings anyway.
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
  const { data } = await supabase.from('price_alerts').select('*, packages(title,price,photos,image_url)').eq('user_id', user.id).eq('is_active', true);
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
// Earning is done via the earn_booking_points() RPC, not raw table writes —
// RLS has no INSERT policy for loyalty_transactions and a column-pinning
// trigger reverts direct balance updates, so a direct .update()/.insert()
// here would silently do nothing. The RPC is SECURITY DEFINER and
// re-validates that the booking is real, paid, and owned by this user.
export async function awardLoyaltyPoints(userId, amountPaid, bookingId, bookingRef) {
  const { data, error } = await supabase.rpc('earn_booking_points', {
    p_user_id: userId,
    p_booking_id: bookingId,
    p_booking_ref: bookingRef || '',
    p_amount_paid: amountPaid,
  });
  if (error) throw error;
  return data;
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
// Maps the public form's business_type labels (Hotel/Bus/Tour/Cab) to
// the vendor_type values the admin panel's filters/stats expect.
const _VENDOR_TYPE_MAP = { hotel: 'hotel', bus: 'bus', tour: 'tour_operator', cab: 'cab' };

export async function registerVendor(vendorData) {
  const user = await getUser();
  const { business_type, owner_name, ...rest } = vendorData;
  const { data, error } = await supabase.from('vendors').insert({
    ...rest,
    business_type, owner_name,                                   // legacy columns, kept for back-compat
    vendor_type: _VENDOR_TYPE_MAP[(business_type||'').toLowerCase()] || 'hotel',
    contact_name: owner_name || '',
    user_id: user?.id || null,
  }).select().single();
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
    nav.innerHTML = '<nav style="background:#0C1B33;padding:14px 20px;display:flex;align-items:center;justify-content:space-between"><a href="/" style="color:#fff;font-weight:800;text-decoration:none;font-size:1.1rem">ZoomFly</a></nav>';
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
