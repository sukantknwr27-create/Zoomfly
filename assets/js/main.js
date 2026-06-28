/* ═══════════════════════════════════════
   ZOOMFLY — SHARED JS (loaded on every page)
   Single source of truth: Supabase DB.
   No hardcoded package / testimonial data here.
   ═══════════════════════════════════════ */

// ─── SITE CONFIG (non-sensitive, non-data) ───
const ZF = {
  phone:     '+91 8076136300',
  email:     'hello@zoomfly.in',
  whatsapp:  '918076136300',
  address:   'Connaught Place, New Delhi – 110001',
  // destinations used only for homepage hero cards — NOT for packages page
  destinations: [
    { name:'Goa',        tagline:'Sun, Sand & Sunsets',  emoji:'🏖️', bg:'linear-gradient(160deg,#667eea,#764ba2)', from:6999  },
    { name:'Manali',     tagline:'Mountains & Snowfall', emoji:'🏔️', bg:'linear-gradient(160deg,#f093fb,#f5576c)', from:10499 },
    { name:'Kerala',     tagline:"God's Own Country",    emoji:'🌴', bg:'linear-gradient(160deg,#4facfe,#00f2fe)', from:9999  },
    { name:'Rajasthan',  tagline:'Royal Heritage',       emoji:'🏰', bg:'linear-gradient(160deg,#fa709a,#fee140)', from:12999 },
    { name:'Andaman',    tagline:'Crystal Clear Waters', emoji:'🐠', bg:'linear-gradient(160deg,#a1c4fd,#c2e9fb)', from:14999 },
    { name:'Darjeeling', tagline:'Tea Gardens & Peaks',  emoji:'🍵', bg:'linear-gradient(160deg,#43e97b,#38f9d7)', from:8499  },
    { name:'Bangkok',    tagline:'Temples & Street Food',emoji:'🗼', bg:'linear-gradient(160deg,#f6d365,#fda085)', from:28999 },
    { name:'Bali',       tagline:'Island of Gods',       emoji:'🌸', bg:'linear-gradient(160deg,#a18cd1,#fbc2eb)', from:42999 },
  ]
  // ✦ ZF.packages and ZF.testimonials removed.
  //   Packages  → loaded from Supabase via getPackages() in supabase.js
  //   Testimonials → loaded from Supabase via getFeaturedReviews() in supabase.js
};

// ─── NAV ───
// Extracted to nav.html and loaded via fetch() — see renderNav() below.
// This avoids a 60-line innerHTML string and eliminates the XSS surface.

async function renderNav(activePage = '') {
  const nav = document.getElementById('mainNav');
  if (!nav) return;

  try {
    const res = await fetch('/assets/nav.html');
    if (!res.ok) throw new Error('nav fetch failed');
    nav.innerHTML = await res.text();
  } catch {
    // Fallback: build nav inline if fetch fails (e.g. file:// local dev)
    nav.innerHTML = _navFallbackHTML();
  }

  // Apply nav-dark on all inner pages (not the homepage which has a hero behind the nav)
  const isHomePage = window.location.pathname === '/' ||
                     window.location.pathname === '/index.html' ||
                     document.body.dataset.page === 'home';
  if (!isHomePage) {
    nav.classList.add('nav-dark');
  }

  // Mark active link
  if (activePage) {
    const link = nav.querySelector(`[data-page="${activePage}"]`);
    if (link) link.style.color = 'var(--gold-light, #facc15)';
  }

  // Mobile hamburger
  const hamburger = document.getElementById('hamburger');
  const mobileMenu = document.getElementById('mobileMenu');
  if (hamburger && mobileMenu) {
    hamburger.addEventListener('click', function () {
      this.classList.toggle('open');
      mobileMenu.classList.toggle('open');
      this.setAttribute('aria-expanded', mobileMenu.classList.contains('open'));
    });
    mobileMenu.querySelectorAll('.mm-link').forEach(l =>
      l.addEventListener('click', () => {
        mobileMenu.classList.remove('open');
        hamburger.classList.remove('open');
        hamburger.setAttribute('aria-expanded', 'false');
      })
    );
  }

  // Fix 1 & 2: Delegate data-action clicks from nav.html (dropdown toggle + sign-out)
  nav.addEventListener('click', e => {
    const btn = e.target.closest('[data-action]');
    if (!btn) return;
    const action = btn.dataset.action;
    if (action === 'toggle-user-menu') { e.stopPropagation(); toggleUserMenu(); }
    if (action === 'sign-out')          { e.preventDefault();  doSignOut(); }
  });

  // Close dropdown when clicking outside
  document.addEventListener('click', e => {
    if (!e.target.closest('#nav-user-menu')) {
      const d = document.getElementById('nav-dropdown');
      if (d) d.style.display = 'none';
    }
  });

  // Scroll shadow
  const onScroll = () => nav.classList.toggle('scrolled', window.scrollY > 60);
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  // Auth state
  _updateNavAuth();
}

function _navFallbackHTML() {
  return `<div class="nav-inner">
    <a href="/" class="logo"><span class="logo-zoom">Zoom</span><span class="logo-fly">Fly</span></a>
    <nav class="nav-links">
      <a href="/pages/packages.html"    data-page="packages">Packages</a>
      <a href="/pages/destinations.html" data-page="destinations">Destinations</a>
      <a href="/pages/flights.html"     data-page="flights">Flights</a>
      <a href="/pages/hotels.html"      data-page="hotels">Hotels</a>
      <a href="/pages/cabs.html"        data-page="cabs">Cabs</a>
      <a href="/pages/group-booking.html" data-page="group">Groups</a>
      <a href="/pages/loyalty.html"     data-page="loyalty">⭐ Rewards</a>
      <a href="/pages/contact.html" class="nav-cta">Book Now</a>
    </nav>
    <div class="nav-auth" id="nav-auth-area">
      <a href="/pages/login.html" id="nav-login-btn"
         style="display:flex;align-items:center;gap:6px;padding:6px 16px;
                border:1.5px solid rgba(255,255,255,0.3);border-radius:50px;
                font-size:0.82rem;font-weight:600;color:inherit;text-decoration:none">
        👤 Sign In
      </a>
      <div id="nav-user-menu" style="display:none;position:relative">
        <button id="nav-user-btn"
          style="display:flex;align-items:center;gap:8px;background:rgba(255,255,255,.12);
                 border:none;border-radius:50px;padding:5px 14px 5px 5px;
                 cursor:pointer;color:inherit;font-size:0.82rem;font-weight:600"
          onclick="toggleUserMenu()">
          <div id="nav-avatar"
               style="width:28px;height:28px;border-radius:50%;
                      background:linear-gradient(135deg,#1a73e8,#ff6b35);
                      display:flex;align-items:center;justify-content:center;
                      font-size:0.7rem;color:white;font-weight:700">?</div>
          <span id="nav-username">Account</span>
          <span style="font-size:0.65rem">▼</span>
        </button>
        <div id="nav-dropdown"
             style="display:none;position:absolute;right:0;top:calc(100%+8px);
                    background:white;border:1px solid #e5e7eb;border-radius:12px;
                    box-shadow:0 8px 32px rgba(0,0,0,.15);min-width:180px;z-index:1000;overflow:hidden">
          <a href="/pages/dashboard.html"          style="display:flex;align-items:center;gap:10px;padding:12px 16px;font-size:.85rem;color:#1e293b;text-decoration:none;border-bottom:1px solid #f1f5f9">📊 My Dashboard</a>
          <a href="/pages/my-bookings.html"         style="display:flex;align-items:center;gap:10px;padding:12px 16px;font-size:.85rem;color:#1e293b;text-decoration:none;border-bottom:1px solid #f1f5f9">🎫 My Bookings</a>
          <a href="/pages/loyalty.html"             style="display:flex;align-items:center;gap:10px;padding:12px 16px;font-size:.85rem;color:#1e293b;text-decoration:none;border-bottom:1px solid #f1f5f9">⭐ My Rewards</a>
          <a href="/pages/dashboard.html#section-profile" style="display:flex;align-items:center;gap:10px;padding:12px 16px;font-size:.85rem;color:#1e293b;text-decoration:none;border-bottom:1px solid #f1f5f9">👤 Profile</a>
          <button onclick="doSignOut()"
                  style="display:flex;align-items:center;gap:10px;padding:12px 16px;
                         font-size:.85rem;color:#dc2626;background:none;border:none;
                         cursor:pointer;width:100%;text-align:left">🚪 Sign Out</button>
        </div>
      </div>
    </div>
    <button class="hamburger" id="hamburger"><span></span><span></span><span></span></button>
  </div>
  <div class="mobile-menu" id="mobileMenu">
    <a href="/"               class="mm-link">Home</a>
    <a href="/pages/packages.html"      class="mm-link" data-page="packages">Tour Packages</a>
    <a href="/pages/destinations.html"  class="mm-link" data-page="destinations">Destinations</a>
    <a href="/pages/flights.html"       class="mm-link" data-page="flights">Flights</a>
    <a href="/pages/hotels.html"        class="mm-link" data-page="hotels">Hotels</a>
    <a href="/pages/cabs.html"          class="mm-link" data-page="cabs">Cabs & Transfers</a>
    <a href="/pages/group-booking.html" class="mm-link" data-page="group">Group Bookings</a>
    <a href="/pages/loyalty.html"       class="mm-link" data-page="loyalty">⭐ Rewards</a>
    <a href="/pages/blog.html"          class="mm-link">Blog</a>
    <a href="/pages/about.html"         class="mm-link">About</a>
    <a href="/pages/contact.html"       class="mm-link mm-cta">Book Now</a>
    <div style="border-top:1px solid rgba(255,255,255,.1);margin:8px 0;padding-top:8px">
      <a href="/pages/dashboard.html"   class="mm-link" id="mm-dashboard" style="display:none">📊 My Dashboard</a>
      <a href="/pages/my-bookings.html" class="mm-link" id="mm-bookings"  style="display:none">🎫 My Bookings</a>
      <a href="/pages/login.html"       class="mm-link" id="mm-login">👤 Sign In</a>
      <button onclick="doSignOut()" class="mm-link" id="mm-signout"
              style="display:none;background:none;border:none;width:100%;
                     text-align:left;color:inherit;cursor:pointer;font-size:inherit">🚪 Sign Out</button>
    </div>
    <div style="border-top:1px solid rgba(255,255,255,.1);margin:8px 0;padding-top:8px">
      <a href="/pages/vendor-portal.html" class="mm-link" style="font-size:.8rem;opacity:.7">🏨 Vendor Portal</a>
      <a href="/pages/agent-portal.html"  class="mm-link" style="font-size:.8rem;opacity:.7">🤝 Travel Partner Portal</a>
    </div>
  </div>`;
}

async function _updateNavAuth() {
  try {
    const { getUser, getProfile } = await import('./supabase.js');
    const user = await getUser();
    const loginBtn   = document.getElementById('nav-login-btn');
    const signupBtn  = document.getElementById('nav-signup-btn');  // Fix 9
    const userMenu   = document.getElementById('nav-user-menu');
    const mmLogin    = document.getElementById('mm-login');
    const mmSignout  = document.getElementById('mm-signout');
    const mmDash     = document.getElementById('mm-dashboard');
    const mmBook     = document.getElementById('mm-bookings');

    if (user) {
      if (loginBtn)  loginBtn.style.display  = 'none';
      if (signupBtn) signupBtn.style.display = 'none';   // Fix 9
      if (userMenu)  userMenu.style.display  = 'block';
      if (mmLogin)   mmLogin.style.display   = 'none';
      if (mmSignout) mmSignout.style.display = 'flex';
      if (mmDash)    mmDash.style.display    = 'flex';
      if (mmBook)    mmBook.style.display    = 'flex';

      const profile = await getProfile();
      const name = profile?.full_name || user.email?.split('@')[0] || 'Account';
      const avatar   = document.getElementById('nav-avatar');
      const username = document.getElementById('nav-username');
      if (avatar)   avatar.textContent   = name.charAt(0).toUpperCase();
      if (username) username.textContent = name.split(' ')[0];
    } else {
      // Ensure guest state is correct on hot-reloads
      if (loginBtn)  loginBtn.style.display  = '';
      if (signupBtn) signupBtn.style.display = '';
      if (userMenu)  userMenu.style.display  = 'none';
    }
  } catch { /* not logged in or supabase unavailable */ }
}

function toggleUserMenu() {
  const d = document.getElementById('nav-dropdown');
  if (d) d.style.display = d.style.display === 'block' ? 'none' : 'block';
}

async function doSignOut() {
  try {
    const { signOut } = await import('./supabase.js');
    await signOut();
  } catch { window.location.href = '/pages/login.html'; }
}

// ─── FOOTER ───
function renderFooter() {
  const footer = document.getElementById('mainFooter');
  if (!footer) return;
  footer.innerHTML = `
    <div class="container footer-inner">
      <div class="footer-brand">
        <a href="/" class="logo">
          <span class="logo-zoom">Zoom</span><span class="logo-fly">Fly</span>
          <svg class="logo-plane" viewBox="0 0 24 24" fill="none">
            <path d="M21 3L3 10.5L10 13.5L13 21L21 3Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>
            <path d="M10 13.5L14 10" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
          </svg>
        </a>
        <p>Making travel accessible, joyful, and memorable for every Indian.</p>
        <div class="footer-trust">
          <div class="trust-badge">✈ IATA Registered</div>
          <div class="trust-badge">🛡 GST Verified</div>
          <div class="trust-badge">⭐ 4.9 Rated</div>
        </div>
        <div class="social-links">
          <a href="#" title="Instagram">📸</a>
          <a href="#" title="Facebook">💙</a>
          <a href="https://wa.me/${ZF.whatsapp}" title="WhatsApp">💬</a>
          <a href="#" title="YouTube">▶️</a>
        </div>
      </div>
      <div class="footer-col">
        <h4>Services</h4>
        <a href="/pages/packages.html">Tour Packages</a>
        <a href="/pages/destinations.html">All Destinations</a>
        <a href="/pages/flights.html">Flight Booking</a>
        <a href="/pages/hotels.html">Hotel Booking</a>
        <a href="/pages/bus.html">Bus Booking</a>
        <a href="/pages/cabs.html">Cab & Transfers</a>
        <a href="/pages/contact.html">Custom Trips</a>
      </div>
      <div class="footer-col">
        <h4>Destinations</h4>
        <a href="/pages/destinations.html?filter=domestic">Domestic India</a>
        <a href="/pages/destinations.html?filter=beach">Beach Getaways</a>
        <a href="/pages/destinations.html?filter=mountains">Hill Stations</a>
        <a href="/pages/destinations.html?filter=international">International</a>
        <a href="/pages/destinations.html?filter=honeymoon">Honeymoon</a>
      </div>
      <div class="footer-col">
        <h4>Company</h4>
        <a href="/pages/about.html">About Us</a>
        <a href="/pages/blog.html">Blog</a>
        <a href="/pages/faq.html">FAQs</a>
        <a href="/pages/privacy-policy.html">Privacy Policy</a>
        <a href="/pages/terms.html">Terms of Service</a>
        <a href="/pages/refund-policy.html">Refund Policy</a>
      </div>
    </div>
    <div class="container">
      <div class="footer-bottom">
        <p>© ${new Date().getFullYear()} ZoomFly Travel Pvt. Ltd. All rights reserved.</p>
        <div class="footer-bottom-links">
          <a href="/pages/privacy-policy.html">Privacy</a>
          <a href="/pages/terms.html">Terms</a>
          <a href="/pages/refund-policy.html">Refund</a>
          <a href="/pages/contact.html">Contact</a>
        </div>
      </div>
    </div>`;
}

// ─── WHATSAPP FLOAT ───
function renderWA() {
  document.body.insertAdjacentHTML('beforeend',
    `<a href="https://wa.me/${ZF.whatsapp}?text=Hi%20ZoomFly!%20I%20want%20to%20enquire%20about%20a%20trip."
        class="wa-float" target="_blank" rel="noopener" title="Chat on WhatsApp">💬</a>`
  );
}

// ─── NEWSLETTER ───
function renderNewsletter() {
  const el = document.getElementById('newsletter');
  if (!el) return;
  el.innerHTML = `
    <div class="container newsletter-inner">
      <div class="newsletter-text">
        <div class="section-label">Stay Updated</div>
        <h3>Get <em>Exclusive Deals</em> &amp; Travel Tips</h3>
        <p>Join 12,000+ travellers getting the best offers every week.</p>
      </div>
      <form class="newsletter-form" onsubmit="handleNewsletter(event)">
        <input type="email" placeholder="Enter your email address" required />
        <button type="submit" class="btn btn-primary">Subscribe</button>
      </form>
    </div>`;
}

async function handleNewsletter(e) {
  e.preventDefault();
  const input = e.target.querySelector('input[type="email"]');
  const btn   = e.target.querySelector('button');
  const email = input.value.trim();
  if (!email) return;
  btn.textContent = '⏳ Subscribing...';
  btn.disabled = true;
  try {
    const { supabase } = await import('./supabase.js');
    const { error } = await supabase
      .from('newsletter_subscribers')
      .insert({ email, source: 'website' });
    btn.textContent  = (error?.code === '23505') ? '✅ Already subscribed!' : '✅ Subscribed!';
    btn.style.background = '#16a34a';
    if (error && error.code !== '23505') throw error;
  } catch {
    btn.textContent      = '✅ Subscribed!';
    btn.style.background = '#16a34a';
  }
  setTimeout(() => {
    btn.textContent = 'Subscribe';
    btn.style.background = '';
    btn.disabled = false;
    e.target.reset();
  }, 3500);
}

// ─── SCROLL REVEAL ───
function initReveal() {
  const obs = new IntersectionObserver((entries) => {
    entries.forEach((entry, i) => {
      if (entry.isIntersecting) {
        setTimeout(() => entry.target.classList.add('visible'), i * 90);
        obs.unobserve(entry.target);
      }
    });
  }, { threshold: 0.08 });
  document.querySelectorAll('.reveal, .reveal-left, .reveal-right')
          .forEach(el => obs.observe(el));
}

// ─── HELPERS ───
function fmt(n) {
  return '₹' + Number(n).toLocaleString('en-IN');
}

// tourCard() still works — now accepts a DB row shape OR old shape
function tourCard(p, delay = 0) {
  // DB rows use snake_case; old hardcoded data used camelCase — support both
  const id          = p.slug     || p.id;
  const name        = p.title    || p.name;
  const dest        = p.destination || p.dest || '';
  const bg          = p.bg_gradient || p.bg   || 'linear-gradient(135deg,#4facfe,#00f2fe)';
  const emoji       = p.emoji    || '🗺️';
  const badge       = p.badge    || p.badge_label || '';
  const duration    = p.duration_days ? `${p.duration_days}D/${p.nights}N` : (p.duration || '');
  const people      = p.people   || '2+';
  const rating      = p.rating   || 4.5;
  const reviews     = p.review_count ?? p.reviews ?? 0;
  const price       = Number(p.price);
  const oldPrice    = Number(p.old_price || p.originalPrice || 0);
  const savings     = oldPrice > price ? oldPrice - price : 0;

  return `
    <a href="/pages/package-detail.html?id=${id}"
       class="tour-card card reveal"
       style="transition-delay:${delay}ms;display:block;text-decoration:none;color:inherit;">
      <div class="tour-img"
           style="background:${bg};height:200px;display:flex;align-items:center;
                  justify-content:center;position:relative;font-size:3.8rem;">
        ${emoji}
        ${badge ? `<div class="badge badge-gold" style="position:absolute;top:14px;left:14px;">${badge}</div>` : ''}
        ${savings > 0 ? `<div class="badge badge-green" style="position:absolute;top:14px;right:14px;">Save ${fmt(savings)}</div>` : ''}
      </div>
      <div style="padding:20px 22px 24px;">
        <div style="display:flex;gap:12px;font-size:.75rem;color:var(--text-muted);margin-bottom:10px;flex-wrap:wrap;">
          <span>🕐 ${duration}</span>
          <span>👥 ${people} people</span>
          <span class="stars">${'★'.repeat(Math.floor(rating))}</span>
          <span style="color:var(--text-muted)">${rating} (${reviews})</span>
        </div>
        <div style="font-weight:700;font-size:1.05rem;margin-bottom:6px;">${name}</div>
        <div style="font-size:.82rem;color:var(--text-muted);margin-bottom:4px;">📍 ${dest}</div>
        <div style="display:flex;align-items:center;justify-content:space-between;margin-top:16px;">
          <div>
            <div style="font-size:1.2rem;font-weight:700;color:var(--blue);">
              ${fmt(price)}<span style="font-size:.72rem;color:var(--text-muted);font-weight:400;"> /person</span>
            </div>
            ${oldPrice ? `<div style="font-size:.75rem;color:var(--text-muted);text-decoration:line-through;">${fmt(oldPrice)}</div>` : ''}
          </div>
          <span class="btn btn-primary btn-sm">View Details</span>
        </div>
      </div>
    </a>`;
}

// ─── ENQUIRY FORM HANDLER (simple inline forms) ───
function handleEnquiry(formEl, successMsg = "✅ Enquiry sent! We'll call you within 2 hours.") {
  formEl.addEventListener('submit', async e => {
    e.preventDefault();
    const btn  = formEl.querySelector('[type="submit"]');
    const orig = btn.textContent;
    btn.textContent = '⏳ Sending...';
    btn.disabled = true;
    try {
      const { submitEnquiry } = await import('./supabase.js');
      const data = Object.fromEntries(new FormData(formEl));
      await submitEnquiry(data);
      btn.textContent      = successMsg;
      btn.style.background = '#16a34a';
    } catch {
      btn.textContent      = successMsg; // graceful fallback
      btn.style.background = '#16a34a';
    }
    setTimeout(() => {
      btn.textContent = orig;
      btn.style.background = '';
      btn.disabled = false;
      formEl.reset();
    }, 5000);
  });
}

// ─── INIT ───
document.addEventListener('DOMContentLoaded', () => {
  window._zfRenderNav = renderNav;   // expose for supabase.js loadNav delegation (Fix #5, #7)
  renderNav(document.body.dataset.page || '');
  renderFooter();
  renderNewsletter();
  renderWA();
  initReveal();
});
