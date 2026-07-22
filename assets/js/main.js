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
  faviconUrl: '',
  companyName: '',
  logoUrl: '',
  gstin: '',
  social: { instagram: '', facebook: '', twitter: '', youtube: '' },
  heroImages: [],
  // destinations used only for homepage hero cards — NOT for packages page
  destinations: [
    { name:'Goa',        tagline:'Sun, Sand & Sunsets',  emoji:'', bg:'linear-gradient(160deg,#667eea,#764ba2)', from:6999  },
    { name:'Manali',     tagline:'Mountains & Snowfall', emoji:'', bg:'linear-gradient(160deg,#f093fb,#f5576c)', from:10499 },
    { name:'Kerala',     tagline:"God's Own Country",    emoji:'', bg:'linear-gradient(160deg,#4facfe,#00f2fe)', from:9999  },
    { name:'Rajasthan',  tagline:'Royal Heritage',       emoji:'', bg:'linear-gradient(160deg,#fa709a,#fee140)', from:12999 },
    { name:'Andaman',    tagline:'Crystal Clear Waters', emoji:'', bg:'linear-gradient(160deg,#a1c4fd,#c2e9fb)', from:14999 },
    { name:'Darjeeling', tagline:'Tea Gardens & Peaks',  emoji:'', bg:'linear-gradient(160deg,#43e97b,#38f9d7)', from:8499  },
    { name:'Bangkok',    tagline:'Temples & Street Food',emoji:'', bg:'linear-gradient(160deg,#f6d365,#fda085)', from:28999 },
    { name:'Bali',       tagline:'Island of Gods',       emoji:'', bg:'linear-gradient(160deg,#a18cd1,#fbc2eb)', from:42999 },
  ]
  // ✦ ZF.packages and ZF.testimonials removed.
  //   Packages  → loaded from Supabase via getPackages() in supabase.js
  //   Testimonials → loaded from Supabase via getFeaturedReviews() in supabase.js
};
// Exposed on window so other modules (booking.js, booking-ui.js,
// whatsapp-templates.js) can read the admin-configured WhatsApp
// number instead of each keeping their own hardcoded copy.
// _loadSiteSettingsIntoZF() below mutates this same object in place,
// so anything holding a reference to window.ZF sees the live values
// once that fetch resolves.
window.ZF = ZF;

// ─── LIVE SITE SETTINGS ───
// Pulls admin-managed contact/social/branding info from site_settings
// and overlays it onto ZF before nav/footer render, so editing these in
// Admin → Site Settings actually takes effect across the whole site
// instead of only being saved to a table nothing reads from.
async function _loadSiteSettingsIntoZF() {
  try {
    const { supabase } = await import('./supabase.js');
    const { data } = await supabase.from('site_settings').select('*').eq('id', 1).single();
    if (!data) return;
    if (data.support_phone)   ZF.phone    = data.support_phone;
    if (data.support_email)   ZF.email    = data.support_email;
    if (data.whatsapp_number) ZF.whatsapp = data.whatsapp_number;
    if (data.address)         ZF.address  = data.address;
    if (data.favicon_url)     ZF.faviconUrl = data.favicon_url;
    if (data.company_name)    ZF.companyName = data.company_name;
    if (data.logo_url)        ZF.logoUrl = data.logo_url;
    if (data.gstin)           ZF.gstin = data.gstin;
    if (Array.isArray(data.homepage_hero_images)) ZF.heroImages = data.homepage_hero_images.filter(Boolean);
    ZF.social = {
      instagram: data.social_instagram || '',
      facebook:  data.social_facebook  || '',
      twitter:   data.social_twitter   || '',
      youtube:   data.social_youtube   || '',
    };
    if (ZF.faviconUrl) {
      document.querySelectorAll('link[rel*="icon"]').forEach(l => { l.href = ZF.faviconUrl; });
    }
  } catch (_) {
    // Non-fatal — page just uses the ZF defaults above, same as before this existed.
  }
}

// ─── NAV ───
// Extracted to nav.html and loaded via fetch() — see renderNav() below.
// This avoids a 60-line innerHTML string and eliminates the XSS surface.

// Small transient toast — used for phone-copy feedback etc.
function _showPhoneToast(msg) {
  let t = document.getElementById('_zf-toast');
  if (!t) {
    t = document.createElement('div');
    t.id = '_zf-toast';
    t.style.cssText = 'position:fixed;bottom:28px;left:50%;transform:translateX(-50%) translateY(20px);background:#0C1B33;color:#fff;padding:11px 22px;border-radius:100px;font-family:"Space Grotesk",system-ui;font-size:.82rem;font-weight:600;box-shadow:0 8px 32px rgba(0,0,0,.3);z-index:99999;opacity:0;transition:opacity .25s,transform .25s;pointer-events:none';
    document.body.appendChild(t);
  }
  t.textContent = msg;
  requestAnimationFrame(() => {
    t.style.opacity = '1';
    t.style.transform = 'translateX(-50%) translateY(0)';
  });
  clearTimeout(t._hideTimer);
  t._hideTimer = setTimeout(() => {
    t.style.opacity = '0';
    t.style.transform = 'translateX(-50%) translateY(20px)';
  }, 2200);
}

// Guards the nav/document/window-level listeners below from being
// attached more than once if renderNav() ever runs a second time on
// the same page (e.g. a page that calls it again after some
// page-specific state change) — #mainNav and document/window persist
// across a renderNav() re-run (only nav.innerHTML gets replaced), so
// without this each re-run would pile on another duplicate listener.
let _navListenersBound = false;

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

  // Nav is ALWAYS dark navy — matches reference design on all pages
  nav.classList.add('nav-dark');

  // Mark active link
  if (activePage) {
    const link = nav.querySelector(`[data-page="${activePage}"]`);
    if (link) link.style.color = 'var(--gold-light, #E8B84B)';
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

  if (!_navListenersBound) {
    _navListenersBound = true;

    // Fix 1 & 2: Delegate data-action clicks from nav.html (dropdown toggle + sign-out)
    nav.addEventListener('click', e => {
      const btn = e.target.closest('[data-action]');
      if (!btn) return;
      const action = btn.dataset.action;
      if (action === 'toggle-user-menu')     { e.stopPropagation(); toggleUserMenu(); }
      if (action === 'sign-out')             { e.preventDefault();  doSignOut(); }
      if (action === 'toggle-services-menu') {
        e.stopPropagation();
        const m = document.getElementById('services-menu');
        if (m) m.style.display = m.style.display === 'block' ? 'none' : 'block';
      }
      if (action === 'call-phone') {
        // On desktop browsers with no tel: handler registered, the OS shows an
        // ugly "no app found" dialog. Detect that case and copy the number
        // to clipboard instead, with a friendly toast.
        const isMobile = /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
        if (!isMobile) {
          e.preventDefault();
          const number = btn.getAttribute('href').replace('tel:', '');
          navigator.clipboard?.writeText(number).then(() => {
            _showPhoneToast(`${number} copied to clipboard`);
          }).catch(() => {
            _showPhoneToast(`Call us: ${number}`);
          });
        }
        // On mobile, let the tel: link work normally (don't preventDefault)
      }
    });

    // Close Services dropdown when clicking outside it
    document.addEventListener('click', e => {
      if (!e.target.closest('.nav-dropdown-wrap')) {
        const m = document.getElementById('services-menu');
        if (m) m.style.display = 'none';
      }
    });

    // Close dropdown when clicking outside
    document.addEventListener('click', e => {
      if (!e.target.closest('#nav-user-menu')) {
        const d = document.getElementById('nav-dropdown');
        if (d) d.style.display = 'none';
      }
    });

    // Scroll shadow — reads the *current* #mainNav each time since this
    // listener now outlives any single renderNav() call.
    window.addEventListener('scroll', () => {
      document.getElementById('mainNav')?.classList.toggle('scrolled', window.scrollY > 60);
    }, { passive: true });
    nav.classList.toggle('scrolled', window.scrollY > 60);
  } else {
    // Listeners are already bound from a previous renderNav() call —
    // still need the scroll-shadow class applied once for this run.
    nav.classList.toggle('scrolled', window.scrollY > 60);
  }

  // Auth state
  _updateNavAuth();
}

function _navFallbackHTML() {
  return `<div class="nav-inner">
    <a href="/" class="logo" style="display:flex;align-items:center;gap:5px;text-decoration:none;color:inherit;flex-shrink:0">
      <span class="logo-zoom">Zoom</span><span class="logo-fly">Fly</span>
      <svg viewBox="0 0 24 24" fill="none" style="width:17px;height:17px;margin-left:2px;color:#E8B84B" class="logo-plane">
        <path d="M21 3L3 10.5L10 13.5L13 21L21 3Z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/>
        <path d="M10 13.5L14 10" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
      </svg>
    </a>
    <nav class="nav-links" style="display:flex;align-items:center;gap:2px">
      <a href="/pages/packages.html"    data-page="packages"    style="padding:6px 9px;font-family:'Space Grotesk',system-ui;font-size:.8rem;font-weight:600;color:inherit;text-decoration:none;white-space:nowrap">Packages</a>
      <a href="/pages/destinations.html" data-page="destinations" style="padding:6px 9px;font-family:'Space Grotesk',system-ui;font-size:.8rem;font-weight:600;color:inherit;text-decoration:none;white-space:nowrap">Destinations</a>
      <a href="/pages/flights.html"     data-page="flights"     style="padding:6px 9px;font-family:'Space Grotesk',system-ui;font-size:.8rem;font-weight:600;color:inherit;text-decoration:none;white-space:nowrap">Flights</a>
      <a href="/pages/hotels.html"      data-page="hotels"      style="padding:6px 9px;font-family:'Space Grotesk',system-ui;font-size:.8rem;font-weight:600;color:inherit;text-decoration:none;white-space:nowrap">Hotels</a>
      <a href="/pages/bus.html"         data-page="bus"         style="padding:6px 9px;font-family:'Space Grotesk',system-ui;font-size:.8rem;font-weight:600;color:inherit;text-decoration:none;white-space:nowrap">Bus</a>
      <a href="/pages/cabs.html"        data-page="cabs"        style="padding:6px 9px;font-family:'Space Grotesk',system-ui;font-size:.8rem;font-weight:600;color:inherit;text-decoration:none;white-space:nowrap">Cabs</a>
      <a href="/pages/trains.html"      data-page="trains"      style="padding:6px 9px;font-family:'Space Grotesk',system-ui;font-size:.8rem;font-weight:600;color:inherit;text-decoration:none;white-space:nowrap;display:flex;align-items:center;gap:4px">Trains <span style="font-size:.52rem;font-weight:800;background:#E8B84B;color:#0C1B33;padding:1px 5px;border-radius:4px">NEW</span></a>
      <a href="/pages/blog.html"        data-page="blog"        style="padding:6px 9px;font-family:'Space Grotesk',system-ui;font-size:.8rem;font-weight:600;color:inherit;text-decoration:none;white-space:nowrap">Blog</a>
      <a href="/pages/contact.html"     data-page="services"    style="padding:6px 9px;font-family:'Space Grotesk',system-ui;font-size:.8rem;font-weight:600;color:inherit;text-decoration:none;white-space:nowrap">Services</a>
    </nav>
    <div style="display:flex;align-items:center;gap:10px;flex-shrink:0;min-width:fit-content">
      <a href="tel:+918076136300" style="display:flex;align-items:center;gap:5px;font-family:'Space Grotesk',system-ui;font-size:.75rem;font-weight:600;color:rgba(255,255,255,.82);text-decoration:none;white-space:nowrap"><span aria-hidden="true"></span><span class="tel-text">+91 8076136300</span></a>
      <div id="nav-auth-area" style="display:flex;align-items:center;gap:8px">
        <a href="/pages/login.html" id="nav-login-btn"
           style="display:flex;align-items:center;gap:5px;padding:7px 16px;border:1.5px solid rgba(255,255,255,0.32);border-radius:50px;font-family:'Space Grotesk',system-ui;font-size:.78rem;font-weight:600;color:rgba(255,255,255,.88);text-decoration:none;white-space:nowrap">
          Sign In
        </a>
        <a href="/pages/login.html?tab=signup" id="nav-signup-btn" style="display:none"></a>
        <div id="nav-user-menu" style="display:none;position:relative">
          <button id="nav-user-btn" data-action="toggle-user-menu"
            style="display:flex;align-items:center;gap:7px;background:rgba(255,255,255,.1);border:1px solid rgba(255,255,255,.2);border-radius:50px;padding:5px 12px 5px 5px;cursor:pointer;color:inherit;font-family:'Space Grotesk',system-ui;font-size:.78rem;font-weight:600;white-space:nowrap">
            <div id="nav-avatar" style="width:26px;height:26px;border-radius:50%;background:linear-gradient(135deg,#C9922A,#E8B84B);display:flex;align-items:center;justify-content:center;font-size:.68rem;color:#0C1B33;font-weight:800">?</div>
            <span id="nav-username">Account</span>
            <span style="font-size:.6rem;opacity:.7">▼</span>
          </button>
          <div id="nav-dropdown" role="menu"
               style="display:none;position:absolute;right:0;top:calc(100%+8px);background:white;border:1px solid #E4E8EF;border-radius:14px;box-shadow:0 12px 40px rgba(12,27,51,.18);min-width:200px;z-index:1000;padding:6px">
            <a href="/pages/dashboard.html"          role="menuitem" style="display:flex;align-items:center;gap:9px;padding:10px 12px;font-size:.84rem;color:#1C2340;text-decoration:none;border-radius:8px">My Dashboard</a>
            <a href="/pages/my-bookings.html"        role="menuitem" style="display:flex;align-items:center;gap:9px;padding:10px 12px;font-size:.84rem;color:#1C2340;text-decoration:none;border-radius:8px">My Bookings</a>
            <a href="/pages/loyalty.html"            role="menuitem" style="display:flex;align-items:center;gap:9px;padding:10px 12px;font-size:.84rem;color:#1C2340;text-decoration:none;border-radius:8px">My Rewards</a>
            <a href="/pages/dashboard.html#section-profile" role="menuitem" style="display:flex;align-items:center;gap:9px;padding:10px 12px;font-size:.84rem;color:#1C2340;text-decoration:none;border-radius:8px">Profile</a>
            <div style="border-top:1px solid #E4E8EF;margin:4px 0"></div>
            <button data-action="sign-out" role="menuitem"
                    style="display:flex;align-items:center;gap:9px;padding:10px 12px;font-size:.84rem;color:#E53E3E;background:none;border:none;cursor:pointer;width:100%;text-align:left;border-radius:8px">Sign Out</button>
          </div>
        </div>
      </div>
      <a href="/pages/contact.html"
         style="display:inline-flex;align-items:center;gap:5px;padding:8px 18px;background:#C9922A;color:#0C1B33;border-radius:50px;font-family:'Space Grotesk',system-ui;font-size:.78rem;font-weight:700;text-decoration:none;white-space:nowrap;box-shadow:0 4px 14px rgba(201,146,42,.35);flex-shrink:0">
        Book Now
      </a>
    </div>
    <button class="hamburger" id="hamburger" aria-label="Open menu" aria-expanded="false"><span></span><span></span><span></span></button>
  </div>
  <div class="mobile-menu" id="mobileMenu">
    <a href="/"                          class="mm-link">Home</a>
    <a href="/pages/packages.html"       class="mm-link" data-page="packages">Tour Packages</a>
    <a href="/pages/destinations.html"   class="mm-link" data-page="destinations">Destinations</a>
    <a href="/pages/flights.html"        class="mm-link" data-page="flights">Flights</a>
    <a href="/pages/hotels.html"         class="mm-link" data-page="hotels">Hotels</a>
    <a href="/pages/bus.html"            class="mm-link" data-page="bus">Buses</a>
    <a href="/pages/cabs.html"           class="mm-link" data-page="cabs">Cabs</a>
    <a href="/pages/trains.html"         class="mm-link" data-page="trains">Trains</a>
    <a href="/pages/blog.html"           class="mm-link">Blog</a>
    <a href="/pages/customize.html"      class="mm-link">Customize Trip</a>
    <a href="/pages/group-booking.html"  class="mm-link">Group Bookings</a>
    <a href="/pages/referral.html"       class="mm-link">Refer &amp; Earn</a>
    <a href="/pages/about.html"          class="mm-link">About Us</a>
    <a href="/pages/contact.html"        class="mm-link mm-cta">Book Now</a>
    <div style="border-top:1px solid rgba(255,255,255,.12);margin:12px 0;padding-top:12px">
      <a href="/pages/dashboard.html"    class="mm-link" id="mm-dashboard" style="display:none">Dashboard</a>
      <a href="/pages/my-bookings.html"  class="mm-link" id="mm-bookings"  style="display:none">My Bookings</a>
      <a href="/pages/trip-tracker.html" class="mm-link" id="mm-trips"     style="display:none">Trip Tracker</a>
      <a href="/pages/co-travellers.html" class="mm-link" id="mm-cotrav"   style="display:none">Co-Travellers</a>
      <a href="/pages/login.html"        class="mm-link" id="mm-login">Sign In</a>
      <button data-action="sign-out"     class="mm-link" id="mm-signout"
              style="display:none;background:none;border:none;width:100%;text-align:left;color:inherit;cursor:pointer;font-size:inherit">Sign Out</button>
    </div>
    <div style="border-top:1px solid rgba(255,255,255,.1);margin:8px 0;padding-top:8px">
      <a href="/pages/vendor-portal.html" class="mm-link" style="font-size:.82rem;opacity:.7">Vendor Portal</a>
      <a href="/pages/agent-portal.html"  class="mm-link" style="font-size:.82rem;opacity:.7">Agent Portal</a>
    </div>
    <div style="margin-top:16px;text-align:center">
      <a href="tel:+918076136300" style="font-family:'Space Grotesk',system-ui;font-size:.85rem;font-weight:600;color:rgba(255,255,255,.75);text-decoration:none">+91 8076136300</a>
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
  const yr = new Date().getFullYear();
  footer.innerHTML = `
<div class="zf-footer-wrap">

  <!-- MAIN FOOTER GRID -->
  <div class="zf-footer-grid">

    <!-- COL 1: Brand -->
    <div class="zf-footer-brand">
      <a href="/" class="logo" style="margin-bottom:14px;display:inline-flex">
        ${ZF.logoUrl ? `<img src="${ZF.logoUrl}" alt="${ZF.companyName||'ZoomFly'}" style="height:28px;width:auto;display:block">` : `
        <span class="logo-zoom">Zoom</span><span class="logo-fly">Fly</span>
        <svg class="logo-plane" viewBox="0 0 24 24" fill="none" style="width:16px;height:16px;margin-left:4px;color:var(--gold-light,#E8B84B)">
          <path d="M21 3L3 10.5L10 13.5L13 21L21 3Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>
          <path d="M10 13.5L14 10" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
        </svg>`}
      </a>
      <p style="color:rgba(255,255,255,0.48);font-size:.82rem;line-height:1.75;max-width:220px;margin-bottom:18px;">
        India's newest travel platform, crafting unforgettable journeys tailored to how you want to explore.
      </p>
      <!-- Trust badges -->
      <div style="display:flex;flex-direction:column;gap:7px;margin-bottom:20px;">
        <div style="display:flex;align-items:center;gap:8px;font-size:.75rem;color:rgba(255,255,255,0.55);">
          <span style="color:#F59E0B">✦</span> <strong style="color:rgba(255,255,255,0.75)">Verified Payments</strong> Powered by Razorpay
        </div>
        <div style="display:flex;align-items:center;gap:8px;font-size:.75rem;color:rgba(255,255,255,0.55);">
          <span style="display:flex"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#C9922A" stroke-width="2"><path d="M3 18v-6a9 9 0 0 1 18 0v6"/><path d="M21 19a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3zM3 19a2 2 0 0 0 2 2h1a2 2 0 0 0 2-2v-3a2 2 0 0 0-2-2H3z"/></svg></span> <strong style="color:rgba(255,255,255,0.75)">24/7 Support</strong> Always here to help
        </div>
        <div style="display:flex;align-items:center;gap:8px;font-size:.75rem;color:rgba(255,255,255,0.55);">
          <span style="display:flex"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#C9922A" stroke-width="2"><path d="M21 8 12 3 3 8l9 5 9-5z"/><path d="M3 8v8l9 5 9-5V8"/></svg></span> <strong style="color:rgba(255,255,255,0.75)">200+ Tour Packages</strong> Handpicked experiences
        </div>
        <div style="display:flex;align-items:center;gap:8px;font-size:.75rem;color:rgba(255,255,255,0.55);">
          <span style="display:flex"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#C9922A" stroke-width="2"><path d="M12 21s-7-6.5-7-11a7 7 0 0 1 14 0c0 4.5-7 11-7 11z"/><circle cx="12" cy="10" r="2.5"/></svg></span> <strong style="color:rgba(255,255,255,0.75)">50+ Destinations</strong> India &amp; International
        </div>
        <div style="display:flex;align-items:center;gap:8px;font-size:.75rem;color:rgba(255,255,255,0.55);">
          <span style="display:flex"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#C9922A" stroke-width="2"><path d="M12 2l1.6 5.5L19 9l-5.4 1.5L12 16l-1.6-5.5L5 9l5.4-1.5z"/></svg></span> <strong style="color:rgba(255,255,255,0.75)">Launched 2026</strong> Built for the modern traveller
        </div>
      </div>
      <!-- Social links -->
      <div style="margin-bottom:4px;font-family:'Space Grotesk',system-ui;font-size:.68rem;font-weight:600;text-transform:uppercase;letter-spacing:.1em;color:rgba(255,255,255,.28);margin-bottom:10px;">Follow Us</div>
      <div style="display:flex;gap:8px;">
        <a href="${ZF.social.instagram || '#'}" ${ZF.social.instagram ? 'target="_blank" rel="noopener"' : 'onclick="return false" style="opacity:.35;cursor:default"'} title="Instagram" style="width:34px;height:34px;border-radius:50%;background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.1);display:flex;align-items:center;justify-content:center;transition:all .2s;text-decoration:none;" onmouseover="this.style.background='#C9922A';this.style.borderColor='#C9922A'" onmouseout="this.style.background='rgba(255,255,255,0.08)';this.style.borderColor='rgba(255,255,255,0.1)'"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="1.8"><rect x="2" y="2" width="20" height="20" rx="5"/><circle cx="12" cy="12" r="4"/><circle cx="17.5" cy="6.5" r="1"/></svg></a>
        <a href="${ZF.social.facebook || '#'}" ${ZF.social.facebook ? 'target="_blank" rel="noopener"' : 'onclick="return false" style="opacity:.35;cursor:default"'} title="Facebook"  style="width:34px;height:34px;border-radius:50%;background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.1);display:flex;align-items:center;justify-content:center;transition:all .2s;text-decoration:none;" onmouseover="this.style.background='#C9922A'" onmouseout="this.style.background='rgba(255,255,255,0.08)'"><svg width="16" height="16" viewBox="0 0 24 24" fill="#fff"><path d="M13.5 21v-8h2.7l.4-3.1h-3.1V8c0-.9.25-1.5 1.55-1.5H17V3.7C16.7 3.66 15.7 3.57 14.5 3.57c-2.4 0-4 1.46-4 4.15V10H7.8v3.1h2.7V21z"/></svg></a>
        <a href="https://wa.me/${ZF.whatsapp}" title="WhatsApp" style="width:34px;height:34px;border-radius:50%;background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.1);display:flex;align-items:center;justify-content:center;transition:all .2s;text-decoration:none;" onmouseover="this.style.background='#25D366'" onmouseout="this.style.background='rgba(255,255,255,0.08)'"><svg width="16" height="16" viewBox="0 0 24 24" fill="#fff"><path d="M12 2a10 10 0 0 0-8.5 15.2L2 22l4.9-1.5A10 10 0 1 0 12 2zm0 18.2c-1.6 0-3.1-.4-4.4-1.2l-.3-.2-2.9.9.9-2.8-.2-.3A8.2 8.2 0 1 1 12 20.2zm4.5-6.1c-.2-.1-1.4-.7-1.7-.8-.2-.1-.4-.1-.6.1-.2.2-.7.8-.8.9-.2.2-.3.2-.5.1-.2-.1-1-.4-1.9-1.2-.7-.6-1.2-1.4-1.3-1.6-.1-.2 0-.4.1-.5l.4-.4c.1-.2.2-.3.2-.5.1-.2 0-.4 0-.5-.1-.1-.6-1.4-.8-1.9-.2-.5-.4-.4-.6-.4h-.5c-.2 0-.5.1-.7.3-.2.2-.9.9-.9 2.2s.9 2.5 1 2.7c.1.2 1.8 2.7 4.3 3.8.6.3 1.1.4 1.4.5.6.2 1.2.2 1.6.1.5-.1 1.4-.6 1.6-1.1.2-.5.2-1 .1-1.1-.1-.1-.2-.2-.4-.3z"/></svg></a>
        <a href="${ZF.social.youtube || '#'}" ${ZF.social.youtube ? 'target="_blank" rel="noopener"' : 'onclick="return false" style="opacity:.35;cursor:default"'} title="YouTube"   style="width:34px;height:34px;border-radius:50%;background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.1);display:flex;align-items:center;justify-content:center;transition:all .2s;text-decoration:none;" onmouseover="this.style.background='#C9922A'" onmouseout="this.style.background='rgba(255,255,255,0.08)'"><svg width="16" height="16" viewBox="0 0 24 24" fill="#fff"><path d="M23 12s0-3.6-.5-5.2c-.3-1-1-1.7-2-2C18.5 4.3 12 4.3 12 4.3s-6.5 0-8.5.5c-1 .3-1.7 1-2 2C1 8.4 1 12 1 12s0 3.6.5 5.2c.3 1 1 1.7 2 2 2 .5 8.5.5 8.5.5s6.5 0 8.5-.5c1-.3 1.7-1 2-2 .5-1.6.5-5.2.5-5.2z"/><path d="M9.8 15.3 15.8 12 9.8 8.7z" fill="#0f172a"/></svg></a>
        <a href="${ZF.social.twitter || '#'}" ${ZF.social.twitter ? 'target="_blank" rel="noopener"' : 'onclick="return false" style="opacity:.35;cursor:default"'} title="Twitter/X" style="width:34px;height:34px;border-radius:50%;background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.1);display:flex;align-items:center;justify-content:center;font-size:.85rem;font-weight:700;color:rgba(255,255,255,.65);transition:all .2s;text-decoration:none;" onmouseover="this.style.background='#C9922A'" onmouseout="this.style.background='rgba(255,255,255,0.08)'">𝕏</a>
      </div>
    </div>

    <!-- COL 2: Travel -->
    <div class="zf-footer-col">
      <h4>TRAVEL</h4>
      <a href="/pages/packages.html">Tour Packages</a>
      <a href="/pages/flights.html">Flights</a>
      <a href="/pages/hotels.html">Hotels</a>
      <a href="/pages/bus.html">Bus Booking</a>
      <a href="/pages/packages.html?filter=honeymoon">Honeymoon Packages</a>
      <a href="/pages/packages.html?filter=group">Group Tours</a>
      <a href="/pages/destinations.html?filter=weekend">Weekend Getaways</a>
      <a href="/pages/cabs.html">Visa Assistance</a>
    </div>

    <!-- COL 3: Company -->
    <div class="zf-footer-col">
      <h4>COMPANY</h4>
      <a href="/pages/about.html">About Us</a>
      <a href="/pages/contact.html">Contact Us</a>
      <a href="/pages/vendor.html">Partner With Us</a>
      <a href="/pages/about.html#careers">Careers</a>
      <a href="/pages/dashboard.html">My Account</a>
      <a href="/pages/terms.html">Terms &amp; Conditions</a>
      <a href="/pages/privacy-policy.html">Privacy Policy</a>
      <a href="/pages/refund-policy.html">Refund Policy</a>
    </div>

    <!-- COL 4: Partner Zone -->
    <div class="zf-footer-col">
      <h4>PARTNER ZONE</h4>
      <a href="/pages/vendor-portal.html">Vendor Login</a>
      <a href="/pages/agent-portal.html">Agent Login</a>
      <a href="/pages/login.html?tab=signup">Create Account</a>
      <a href="/pages/referral.html">Refer &amp; Earn</a>
      <div style="margin-top:18px;padding:14px;background:rgba(201,146,42,0.12);border:1px solid rgba(201,146,42,0.22);border-radius:10px;">
        <div style="font-family:'Space Grotesk',system-ui;font-size:.75rem;font-weight:700;color:var(--gold-light,#E8B84B);margin-bottom:6px;">Refer &amp; Earn</div>
        <div style="font-size:.72rem;color:rgba(255,255,255,0.52);line-height:1.6;">Invite friends &amp; earn exciting rewards. Get early access to best deals.</div>
        <a href="/pages/referral.html" style="display:inline-block;margin-top:10px;font-family:'Space Grotesk',system-ui;font-size:.72rem;font-weight:700;color:var(--gold-light,#E8B84B);">Learn More →</a>
      </div>
    </div>

    <!-- COL 5: Contact Us -->
    <div class="zf-footer-col">
      <h4>CONTACT US</h4>
      <div style="display:flex;flex-direction:column;gap:12px;">
        <div>
          <a href="tel:${ZF.phone.replace(/\s+/g,'')}" style="display:flex;align-items:center;gap:7px;color:rgba(255,255,255,0.7);font-size:.82rem;text-decoration:none;margin-bottom:3px;">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#C9922A" stroke-width="2" style="flex-shrink:0"><path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.3 1.8.6 2.7a2 2 0 0 1-.5 2.1L8 9.7a16 16 0 0 0 6 6l1.2-1.2a2 2 0 0 1 2.1-.5c.9.3 1.8.5 2.7.6a2 2 0 0 1 1.7 2.1z"/></svg> ${ZF.phone}
          </a>
          <div style="font-size:.72rem;color:rgba(255,255,255,0.35);padding-left:22px;">Mon – Sat (9 AM – 8 PM)</div>
        </div>
        <div>
          <a href="mailto:${ZF.email}" style="display:flex;align-items:center;gap:7px;color:rgba(255,255,255,0.7);font-size:.82rem;text-decoration:none;margin-bottom:3px;">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#C9922A" stroke-width="2" style="flex-shrink:0"><rect x="2" y="4" width="20" height="16" rx="2"/><path d="M2 6l10 7 10-7"/></svg> ${ZF.email}
          </a>
          <div style="font-size:.72rem;color:rgba(255,255,255,0.35);padding-left:22px;">We reply within 30 mins</div>
        </div>
        <div style="display:flex;align-items:flex-start;gap:7px;font-size:.79rem;color:rgba(255,255,255,0.55);line-height:1.6;">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#C9922A" stroke-width="2" style="flex-shrink:0;margin-top:2px"><path d="M12 21s-7-6.5-7-11a7 7 0 0 1 14 0c0 4.5-7 11-7 11z"/><circle cx="12" cy="10" r="2.5"/></svg>
          <span>${ZF.address}</span>
        </div>
        ${ZF.gstin ? `<div style="font-size:.72rem;color:rgba(255,255,255,0.35);">GSTIN: ${ZF.gstin}</div>` : ''}
        <div>
          <a href="https://wa.me/${ZF.whatsapp}" style="display:flex;align-items:center;gap:7px;color:rgba(255,255,255,0.7);font-size:.82rem;text-decoration:none;">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="#25D366" style="flex-shrink:0"><path d="M12 2a10 10 0 0 0-8.5 15.2L2 22l4.9-1.5A10 10 0 1 0 12 2zm0 18.2c-1.6 0-3.1-.4-4.4-1.2l-.3-.2-2.9.9.9-2.8-.2-.3A8.2 8.2 0 1 1 12 20.2zm4.5-6.1c-.2-.1-1.4-.7-1.7-.8-.2-.1-.4-.1-.6.1-.2.2-.7.8-.8.9-.2.2-.3.2-.5.1-.2-.1-1-.4-1.9-1.2-.7-.6-1.2-1.4-1.3-1.6-.1-.2 0-.4.1-.5l.4-.4c.1-.2.2-.3.2-.5.1-.2 0-.4 0-.5-.1-.1-.6-1.4-.8-1.9-.2-.5-.4-.4-.6-.4h-.5c-.2 0-.5.1-.7.3-.2.2-.9.9-.9 2.2s.9 2.5 1 2.7c.1.2 1.8 2.7 4.3 3.8.6.3 1.1.4 1.4.5.6.2 1.2.2 1.6.1.5-.1 1.4-.6 1.6-1.1.2-.5.2-1 .1-1.1-.1-.1-.2-.2-.4-.3z"/></svg> WhatsApp Chat
          </a>
          <div style="font-size:.72rem;color:rgba(255,255,255,0.35);padding-left:22px;">Quick support on WhatsApp</div>
        </div>
        <!-- Newsletter mini -->
        <div style="margin-top:8px;">
          <div style="font-family:'Space Grotesk',system-ui;font-size:.72rem;font-weight:600;color:rgba(255,255,255,.4);text-transform:uppercase;letter-spacing:.08em;margin-bottom:8px;">Stay Updated</div>
          <div style="font-size:.72rem;color:rgba(255,255,255,0.38);margin-bottom:8px;line-height:1.55;">Get exclusive travel deals, offers and new destination updates.</div>
          <form onsubmit="handleNewsletter(event)" style="display:flex;gap:6px;">
            <input type="email" placeholder="Enter your email" required
              style="flex:1;padding:8px 12px;border:1px solid rgba(255,255,255,0.15);border-radius:6px;background:rgba(255,255,255,0.06);color:#fff;font-size:.78rem;font-family:'Inter',sans-serif;min-width:0;"/>
            <button type="submit"
              style="padding:8px 14px;background:var(--gold,#C9922A);color:#0C1B33;border:none;border-radius:6px;font-family:'Space Grotesk',system-ui;font-size:.75rem;font-weight:700;cursor:pointer;white-space:nowrap;">
              Subscribe
            </button>
          </form>
        </div>
      </div>
    </div>

  </div>

  <!-- DIVIDER -->
  <div style="border-top:1px solid rgba(255,255,255,0.07);margin:0;"></div>

  <!-- PAYMENT + TRUST ROW -->
  <div style="padding:20px 28px;display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:16px;">
    <div>
      <div style="font-family:'Space Grotesk',system-ui;font-size:.65rem;font-weight:600;text-transform:uppercase;letter-spacing:.1em;color:rgba(255,255,255,.25);margin-bottom:8px;">We Accept</div>
      <div style="display:flex;align-items:center;gap:6px;flex-wrap:wrap;">
        ${['VISA','MC','RuPay','UPI','PayTM','PhonePe','GPay'].map(p =>
          `<div style="background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.12);border-radius:5px;padding:4px 10px;font-family:'Space Grotesk',system-ui;font-size:.65rem;font-weight:700;color:rgba(255,255,255,0.55);">${p}</div>`
        ).join('')}
      </div>
    </div>
    <div style="display:flex;align-items:center;gap:16px;flex-wrap:wrap;">
      <div style="text-align:center;">
        <div style="font-size:1.1rem;margin-bottom:2px;"></div>
        <div style="font-family:'Space Grotesk',system-ui;font-size:.62rem;color:rgba(255,255,255,.35);font-weight:600;">SSL Secured<br>256-bit SSL</div>
      </div>
      <div style="text-align:center;">
        <div style="font-size:1.1rem;margin-bottom:2px;"></div>
        <div style="font-family:'Space Grotesk',system-ui;font-size:.62rem;color:rgba(255,255,255,.35);font-weight:600;">Payments by<br>Razorpay</div>
      </div>
      <div style="text-align:center;">
        <div style="font-size:1.1rem;margin-bottom:2px;"></div>
        <div style="font-family:'Space Grotesk',system-ui;font-size:.62rem;color:rgba(255,255,255,.35);font-weight:600;">Data Protected<br>Privacy First</div>
      </div>
      <div style="text-align:center;">
        <div style="font-size:1.1rem;margin-bottom:2px;"></div>
        <div style="font-family:'Space Grotesk',system-ui;font-size:.62rem;color:rgba(255,255,255,.35);font-weight:600;">24/7<br>Customer Support</div>
      </div>
    </div>
  </div>

  <!-- DIVIDER -->
  <div style="border-top:1px solid rgba(255,255,255,0.06);"></div>

  <!-- BOTTOM BAR -->
  <div style="padding:16px 28px;display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:10px;">
    <div style="display:flex;align-items:center;gap:6px;">
      <span style="font-size:.78rem;color:rgba(255,255,255,0.28);">${yr} ${ZF.companyName || 'ZoomFly'}. All rights reserved.</span>
      <span style="color:rgba(255,255,255,0.15);margin:0 2px">·</span>
      <span style="font-size:.75rem;color:rgba(255,255,255,0.22);">Made with  in India</span>
    </div>
    <div style="display:flex;align-items:center;gap:18px;">
      <a href="/pages/privacy-policy.html" style="font-size:.75rem;color:rgba(255,255,255,.28);text-decoration:none;transition:color .2s" onmouseover="this.style.color='rgba(255,255,255,.6)'" onmouseout="this.style.color='rgba(255,255,255,.28)'">Privacy Policy</a>
      <a href="/pages/terms.html"          style="font-size:.75rem;color:rgba(255,255,255,.28);text-decoration:none;transition:color .2s" onmouseover="this.style.color='rgba(255,255,255,.6)'" onmouseout="this.style.color='rgba(255,255,255,.28)'">Terms &amp; Conditions</a>
      <a href="/pages/refund-policy.html"  style="font-size:.75rem;color:rgba(255,255,255,.28);text-decoration:none;transition:color .2s" onmouseover="this.style.color='rgba(255,255,255,.6)'" onmouseout="this.style.color='rgba(255,255,255,.28)'">Refund Policy</a>
      <a href="/pages/contact.html"        style="font-size:.75rem;color:rgba(255,255,255,.28);text-decoration:none;transition:color .2s" onmouseover="this.style.color='rgba(255,255,255,.6)'" onmouseout="this.style.color='rgba(255,255,255,.28)'">Cookies Policy</a>
      <a href="/sitemap.xml"               style="font-size:.75rem;color:rgba(255,255,255,.28);text-decoration:none;transition:color .2s" onmouseover="this.style.color='rgba(255,255,255,.6)'" onmouseout="this.style.color='rgba(255,255,255,.28)'">Sitemap</a>
    </div>
    <div style="font-size:1.2rem;color:rgba(255,255,255,.12);"></div>
  </div>

</div>`;
}

// ─── HOMEPAGE HERO PHOTO CAROUSEL ───
// Only does anything on index.html (the only page with #heroCarousel), and
// only if Admin → Site Settings → Hero Background Photos has photos set.
// Otherwise the existing gradient/mountain background shows through untouched.
function initHeroCarousel() {
  const el = document.getElementById('heroCarousel');
  if (!el || !ZF.heroImages || !ZF.heroImages.length) return;

  el.innerHTML = ZF.heroImages.map((src, i) => `
    <img src="${src}" alt="" style="position:absolute;inset:0;width:100%;height:100%;
         object-fit:cover;opacity:${i===0?1:0};transition:opacity 1.6s ease;"
         onerror="this.style.display='none'"/>
  `).join('') + `
    <div style="position:absolute;inset:0;background:linear-gradient(160deg,rgba(6,21,37,.72) 0%,rgba(13,37,69,.55) 40%,rgba(45,100,148,.35) 70%,rgba(196,122,43,.4) 100%);"></div>
  `;

  const imgs = el.querySelectorAll('img');
  if (imgs.length < 2) return; // nothing to rotate with just one photo

  let current = 0;
  setInterval(() => {
    const next = (current + 1) % imgs.length;
    imgs[current].style.opacity = 0;
    imgs[next].style.opacity = 1;
    current = next;
  }, 6000);
}


function renderWA() {
  document.body.insertAdjacentHTML('beforeend',
    `<a href="https://wa.me/${ZF.whatsapp}?text=Hi%20ZoomFly!%20I%20want%20to%20enquire%20about%20a%20trip."
        class="wa-float" target="_blank" rel="noopener" title="Chat on WhatsApp"><svg width="30" height="30" viewBox="0 0 24 24" fill="#fff"><path d="M12 2a10 10 0 0 0-8.5 15.2L2 22l4.9-1.5A10 10 0 1 0 12 2zm0 18.2c-1.6 0-3.1-.4-4.4-1.2l-.3-.2-2.9.9.9-2.8-.2-.3A8.2 8.2 0 1 1 12 20.2zm4.5-6.1c-.2-.1-1.4-.7-1.7-.8-.2-.1-.4-.1-.6.1-.2.2-.7.8-.8.9-.2.2-.3.2-.5.1-.2-.1-1-.4-1.9-1.2-.7-.6-1.2-1.4-1.3-1.6-.1-.2 0-.4.1-.5l.4-.4c.1-.2.2-.3.2-.5.1-.2 0-.4 0-.5-.1-.1-.6-1.4-.8-1.9-.2-.5-.4-.4-.6-.4h-.5c-.2 0-.5.1-.7.3-.2.2-.9.9-.9 2.2s.9 2.5 1 2.7c.1.2 1.8 2.7 4.3 3.8.6.3 1.1.4 1.4.5.6.2 1.2.2 1.6.1.5-.1 1.4-.6 1.6-1.1.2-.5.2-1 .1-1.1-.1-.1-.2-.2-.4-.3z"/></svg></a>`
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
        <p>Get the best offers delivered straight to your inbox every week.</p>
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
  btn.textContent = 'Subscribing...';
  btn.disabled = true;
  try {
    const { supabase } = await import('./supabase.js');
    const { error } = await supabase
      .from('newsletter_subscribers')
      .insert({ email, source: 'website' });
    btn.textContent  = (error?.code === '23505') ? 'Already subscribed!' : 'Subscribed!';
    btn.style.background = '#16a34a';
    if (error && error.code !== '23505') throw error;
  } catch {
    btn.textContent      = 'Subscribed!';
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
function esc(s) { return String(s??'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;'); }

function tourCard(p, delay = 0) {
  // DB rows use snake_case; old hardcoded data used camelCase — support both
  const id          = p.slug     || p.id;
  const name        = p.title    || p.name;
  const dest        = p.destination || p.dest || '';
  const bg          = p.bg_gradient || p.bg   || 'linear-gradient(135deg,#4facfe,#00f2fe)';
  const photo       = (p.photos && p.photos[0]) || p.image_url || '';
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
                  justify-content:center;position:relative;font-size:3.8rem;overflow:hidden;">
        ${photo ? `<img src="${esc(photo)}" alt="${esc(name)}" style="width:100%;height:100%;object-fit:cover" onerror="this.remove()"/>` : ''}
        ${badge ? `<div class="badge badge-gold" style="position:absolute;top:14px;left:14px;">${esc(badge)}</div>` : ''}
        ${savings > 0 ? `<div class="badge badge-green" style="position:absolute;top:14px;right:14px;">Save ${fmt(savings)}</div>` : ''}
      </div>
      <div style="padding:20px 22px 24px;">
        <div style="display:flex;gap:12px;font-size:.75rem;color:var(--text-muted);margin-bottom:10px;flex-wrap:wrap;">
          <span>${esc(duration)}</span>
          <span>${esc(people)} people</span>
          <span class="stars">${'★'.repeat(Math.floor(rating))}</span>
          <span style="color:var(--text-muted)">${rating} (${reviews})</span>
        </div>
        <div style="font-weight:700;font-size:1.05rem;margin-bottom:6px;">${esc(name)}</div>
        <div style="font-size:.82rem;color:var(--text-muted);margin-bottom:4px;">${esc(dest)}</div>
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
function handleEnquiry(formEl, successMsg = "Enquiry sent! We'll call you within 2 hours.") {
  formEl.addEventListener('submit', async e => {
    e.preventDefault();
    const btn  = formEl.querySelector('[type="submit"]');
    const orig = btn.textContent;
    btn.textContent = 'Sending...';
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

// ─── REFERRAL CODE CAPTURE ───
// Shared referral links point at the homepage (https://www.zoomfly.in/?ref=CODE),
// but only referral.html itself was capturing the ?ref= param into
// sessionStorage — meaning a friend who actually clicked a shared link
// and landed here never had their referrer's code recorded, so
// signUp()'s referral bonus (assets/js/supabase.js) never had anything
// to read at signup time. main.js loads on every page, so capture it
// here regardless of which page the link actually lands on.
(function captureReferralCode() {
  const ref = new URLSearchParams(location.search).get('ref');
  if (ref) sessionStorage.setItem('zf_ref', ref);
})();

// ─── INIT ───
document.addEventListener('DOMContentLoaded', async () => {
  window._zfRenderNav = renderNav;   // expose for supabase.js loadNav delegation (Fix #5, #7)
  await _loadSiteSettingsIntoZF();   // pull admin-managed phone/whatsapp/social/favicon before rendering
  await renderNav(document.body.dataset.page || '');
  // nav.html itself hardcodes a tel: link (static fragment, not JS-templated
  // like the footer) — patch it in place so the admin-managed phone number
  // takes effect there too, without having to convert nav.html into a
  // template just for one field.
  document.querySelectorAll('#mainNav a[href^="tel:"]').forEach(a => {
    a.href = 'tel:' + ZF.phone.replace(/\s+/g, '');
    const telText = a.querySelector('.tel-text');
    if (telText) telText.textContent = ZF.phone; else a.textContent = '' + ZF.phone;
  });
  // nav.html hardcodes a text/SVG logo mark too — swap it for the
  // admin-uploaded logo image if one has been set in Site Settings.
  if (ZF.logoUrl) {
    document.querySelectorAll('#mainNav a.logo').forEach(a => {
      a.innerHTML = `<img src="${ZF.logoUrl}" alt="${ZF.companyName || 'ZoomFly'}" style="height:28px;width:auto;display:block">`;
    });
  }
  renderFooter();
  renderNewsletter();
  renderWA();
  initHeroCarousel();
  initReveal();
});
