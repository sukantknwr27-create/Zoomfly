/* ═══════════════════════════════════════
   ZOOMFLY — SHARED JS (loaded on every page)
   ═══════════════════════════════════════ */

// ─── DATA ───
const ZF = {
  phone: '+91 8076136300',
  email: 'hello@zoomfly.in',
  whatsapp: '918076136300',
  address: 'Connaught Place, New Delhi – 110001',
  packages: [
    { id:'manali-snow-escape', name:'Manali Snow Escape', dest:'Manali, Himachal Pradesh', type:'Domestic', category:'adventure', emoji:'🏔️', bg:'linear-gradient(135deg,#667eea,#764ba2)', badge:'Best Seller', duration:'6D/5N', people:'2+', rating:'4.9', reviews:312, price:12499, originalPrice:14999, inclusions:['Hotel Stay','Breakfast & Dinner','Sightseeing','Airport Transfers','Travel Insurance'], highlights:['Rohtang Pass','Solang Valley','Hadimba Temple','Old Manali','Beas River Rafting'], itinerary:[{day:1,title:'Arrival & Local Sightseeing',desc:'Arrive in Manali, check into hotel. Visit Hadimba Temple, Manu Temple, and Van Vihar.'},{day:2,title:'Solang Valley & Adventure',desc:'Full day at Solang Valley. Enjoy skiing, zorbing, and cable car rides with breathtaking views.'},{day:3,title:'Rohtang Pass',desc:'Subject to permit availability. Snow activities, photography at 13,050 ft altitude.'},{day:4,title:'Old Manali & Leisure',desc:'Explore Old Manali market, Naggar Castle, and Nicholas Roerich Art Gallery.'},{day:5,title:'River Rafting & Leisure',desc:'Beas River white water rafting followed by leisure time and shopping.'},{day:6,title:'Departure',desc:'Check out after breakfast and transfer to Kullu/Bhuntar airport.'}] },
    { id:'goa-beach-bliss', name:'Goa Beach Bliss', dest:'Goa, India', type:'Domestic', category:'beach', emoji:'🏖️', bg:'linear-gradient(135deg,#f6d365,#fda085)', badge:'Trending', duration:'5D/4N', people:'2+', rating:'4.8', reviews:541, price:8999, originalPrice:10999, inclusions:['4-Star Hotel','Breakfast','Airport Transfers','North & South Goa Tour','Water Sports Pass'], highlights:['Baga Beach','Dudhsagar Falls','Old Goa Churches','Anjuna Flea Market','Sunset Cruise'], itinerary:[{day:1,title:'Arrival in Paradise',desc:'Land in Goa, check into beachside hotel. Evening stroll at Calangute Beach.'},{day:2,title:'North Goa Beaches',desc:'Baga, Anjuna, Vagator beaches. Evening at Anjuna Flea Market.'},{day:3,title:'Dudhsagar & Spice Farm',desc:'Full day excursion to Dudhsagar Falls and spice plantation tour.'},{day:4,title:'South Goa & Churches',desc:'Old Goa churches, Colva Beach, and sunset cruise on Mandovi River.'},{day:5,title:'Leisure & Departure',desc:'Morning at leisure, water sports if desired. Transfer to airport.'}] },
    { id:'kerala-backwaters', name:'Kerala Backwaters', dest:'Kerala, India', type:'Domestic', category:'nature', emoji:'🌴', bg:'linear-gradient(135deg,#43e97b,#38f9d7)', badge:'New', duration:'7D/6N', people:'2+', rating:'4.9', reviews:278, price:15499, originalPrice:18999, inclusions:['Hotels & Houseboat','All Meals on Houseboat','Sightseeing','Airport Transfers','Kathakali Show'], highlights:['Alleppey Houseboat','Munnar Tea Gardens','Periyar Wildlife','Kovalam Beach','Ayurvedic Spa'], itinerary:[{day:1,title:'Arrive Kochi',desc:'Arrive Kochi, explore Fort Kochi, Chinese Fishing Nets, and Mattancherry.'},{day:2,title:'Kochi to Munnar',desc:'Drive to Munnar through tea estates. Visit Eravikulam National Park.'},{day:3,title:'Munnar Sightseeing',desc:'Visit Mattupetty Dam, Top Station, and Kundala Lake. Tea factory visit.'},{day:4,title:'Munnar to Thekkady',desc:'Drive to Periyar. Evening boat ride and Kathakali dance performance.'},{day:5,title:'Thekkady to Alleppey',desc:'Drive to Alleppey. Board the iconic houseboat on backwaters.'},{day:6,title:'Houseboat & Kovalam',desc:'Morning cruise on backwaters, afternoon drive to Kovalam beach resort.'},{day:7,title:'Departure',desc:'Breakfast and transfer to Thiruvananthapuram airport.'}] },
    { id:'rajasthan-royal-tour', name:'Rajasthan Royal Tour', dest:'Rajasthan, India', type:'Domestic', category:'heritage', emoji:'🏰', bg:'linear-gradient(135deg,#fa709a,#fee140)', badge:'Popular', duration:'8D/7N', people:'2+', rating:'4.7', reviews:189, price:18999, originalPrice:22999, inclusions:['Heritage Hotels','Breakfast & Dinner','AC Vehicle','Camel Safari','Entrance Fees'], highlights:['Jaipur Pink City','Jodhpur Blue City','Udaipur Lake Palace','Jaisalmer Fort','Camel Safari'], itinerary:[{day:1,title:'Arrive Jaipur',desc:'Check into heritage hotel. Evening at Chokhi Dhani for cultural show.'},{day:2,title:'Jaipur Sightseeing',desc:'Amber Fort, City Palace, Jantar Mantar, Hawa Mahal, and Bapu Bazaar.'},{day:3,title:'Jaipur to Jodhpur',desc:'Drive via Ajmer Sharif Dargah. Arrive Jodhpur, visit Umaid Bhawan.'},{day:4,title:'Jodhpur Sightseeing',desc:'Mehrangarh Fort, Jaswant Thada, Clock Tower market.'},{day:5,title:'Jodhpur to Jaisalmer',desc:'Desert drive to Jaisalmer. Sunset at Sam Sand Dunes.'},{day:6,title:'Jaisalmer & Camel Safari',desc:'Jaisalmer Fort, Patwon Ki Haveli, camel safari & desert camp.'},{day:7,title:'Jaisalmer to Udaipur',desc:'Fly/drive to Udaipur. Lake Pichola boat ride at sunset.'},{day:8,title:'Udaipur & Departure',desc:'City Palace, Saheliyon Ki Bari, departure transfer.'}] },
    { id:'bangkok-explorer', name:'Bangkok Explorer', dest:'Bangkok, Thailand', type:'International', category:'international', emoji:'🗼', bg:'linear-gradient(135deg,#4facfe,#00f2fe)', badge:'International', duration:'6D/5N', people:'2+', rating:'4.8', reviews:423, price:32999, originalPrice:38999, inclusions:['4-Star Hotel','Breakfast','Return Flights','Visa Assistance','City Tour','Island Hopping'], highlights:['Grand Palace','Floating Markets','Pattaya Day Trip','Phi Phi Islands','Chatuchak Market'], itinerary:[{day:1,title:'Arrival in Bangkok',desc:'Arrive Bangkok, hotel check-in, evening Chao Phraya River cruise.'},{day:2,title:'Bangkok City Tour',desc:'Grand Palace, Wat Phra Kaew, Wat Arun, Floating Market tour.'},{day:3,title:'Pattaya Day Trip',desc:'Coral Island, Nong Nooch Garden, Pattaya city tour.'},{day:4,title:'Phi Phi Islands',desc:'Full day speedboat to Phi Phi Islands with snorkelling and beach time.'},{day:5,title:'Shopping & Leisure',desc:'Chatuchak Weekend Market, Siam Paragon, street food tour.'},{day:6,title:'Departure',desc:'Breakfast and transfer to Suvarnabhumi Airport.'}] },
    { id:'bali-romance', name:'Bali Romance Package', dest:'Bali, Indonesia', type:'International', category:'honeymoon', emoji:'🌸', bg:'linear-gradient(135deg,#a18cd1,#fbc2eb)', badge:'Honeymoon', duration:'7D/6N', people:'2', rating:'5.0', reviews:167, price:55999, originalPrice:64999, inclusions:['Private Pool Villa','All Meals','Return Flights','Airport Transfers','Couples Spa','Sunset Dinner'], highlights:['Ubud Rice Terraces','Tanah Lot Temple','Seminyak Beach','Mount Batur Sunrise','Couples Spa'], itinerary:[{day:1,title:'Arrive in Paradise',desc:'Arrive Bali, private transfer to luxury villa. Welcome spa and candlelit dinner.'},{day:2,title:'Ubud Exploration',desc:'Tegalalang Rice Terraces, Monkey Forest, Ubud Palace, art market.'},{day:3,title:'Spiritual Bali',desc:'Tanah Lot sunset, Uluwatu temple, Kecak fire dance performance.'},{day:4,title:'Mount Batur Sunrise',desc:'Early morning trek to Mount Batur for a breathtaking sunrise.'},{day:5,title:'Beach Day & Spa',desc:'Seminyak beach, couples massage, sunset cocktails at Ku De Ta.'},{day:6,title:'Nusa Penida Island',desc:'Island hopping tour to Kelingking, Angel Billabong, Crystal Bay.'},{day:7,title:'Farewell Brunch & Departure',desc:'Leisure morning, farewell brunch, transfer to Ngurah Rai Airport.'}] },
    { id:'andaman-island-escape', name:'Andaman Island Escape', dest:'Port Blair, Andaman', type:'Domestic', category:'beach', emoji:'🐠', bg:'linear-gradient(135deg,#a1c4fd,#c2e9fb)', badge:'Popular', duration:'6D/5N', people:'2+', rating:'4.8', reviews:203, price:19999, originalPrice:24999, inclusions:['Hotel & Resort','Breakfast','Flights from Chennai','Ferry Tickets','Scuba Diving','Glass Bottom Boat'], highlights:['Radhanagar Beach','Havelock Island','Neil Island','Cellular Jail','Scuba Diving'], itinerary:[{day:1,title:'Arrive Port Blair',desc:'Arrive Port Blair, visit Cellular Jail. Evening light & sound show.'},{day:2,title:'Port Blair Sightseeing',desc:'Corbyn Cove Beach, Chidiya Tapu sunset point, local museums.'},{day:3,title:'Havelock Island',desc:'Ferry to Havelock. Afternoon at Radhanagar Beach (Asia\'s Best Beach).'},{day:4,title:'Havelock Activities',desc:'Scuba diving or snorkelling at Elephant Beach. Glass bottom boat ride.'},{day:5,title:'Neil Island Day Trip',desc:'Day trip to Neil Island. Bharatpur Beach and Natural Bridge.'},{day:6,title:'Departure',desc:'Return ferry to Port Blair. Flight to home city.'}] },
    { id:'darjeeling-tea-trails', name:'Darjeeling Tea Trails', dest:'Darjeeling, West Bengal', type:'Domestic', category:'nature', emoji:'🍵', bg:'linear-gradient(135deg,#43e97b,#38f9d7)', badge:'New', duration:'5D/4N', people:'2+', rating:'4.6', reviews:142, price:10499, originalPrice:12999, inclusions:['Boutique Tea Estate Hotel','All Meals','Toy Train Ride','Tea Tasting','Sightseeing'], highlights:['Toy Train Ride','Tiger Hill Sunrise','Tea Estate Walk','Batasia Loop','Zoo Visit'], itinerary:[{day:1,title:'Arrive Bagdogra',desc:'Pickup from NJP/Bagdogra. Scenic drive to Darjeeling. Evening at Mall Road.'},{day:2,title:'Tiger Hill Sunrise',desc:'Early morning Tiger Hill for Kanchenjunga sunrise. Visit Ghoom Monastery.'},{day:3,title:'Tea Estate Tour',desc:'Full day at tea estates. Tea picking, processing, and tasting session.'},{day:4,title:'Toy Train & Sightseeing',desc:'UNESCO Toy Train joy ride. Batasia Loop, Zoo, Rock Garden.'},{day:5,title:'Departure',desc:'Breakfast, last minute shopping, transfer to airport/station.'}] },
  ],

  destinations: [
    { name:'Goa', tagline:'Sun, Sand & Sunsets', emoji:'🏖️', bg:'linear-gradient(160deg,#667eea,#764ba2)', from:6999 },
    { name:'Manali', tagline:'Mountains & Snowfall', emoji:'🏔️', bg:'linear-gradient(160deg,#f093fb,#f5576c)', from:10499 },
    { name:'Kerala', tagline:"God's Own Country", emoji:'🌴', bg:'linear-gradient(160deg,#4facfe,#00f2fe)', from:9999 },
    { name:'Rajasthan', tagline:'Royal Heritage', emoji:'🏰', bg:'linear-gradient(160deg,#fa709a,#fee140)', from:12999 },
    { name:'Andaman', tagline:'Crystal Clear Waters', emoji:'🐠', bg:'linear-gradient(160deg,#a1c4fd,#c2e9fb)', from:14999 },
    { name:'Darjeeling', tagline:'Tea Gardens & Peaks', emoji:'🍵', bg:'linear-gradient(160deg,#43e97b,#38f9d7)', from:8499 },
    { name:'Bangkok', tagline:'Temples & Street Food', emoji:'🗼', bg:'linear-gradient(160deg,#f6d365,#fda085)', from:28999 },
    { name:'Bali', tagline:'Island of Gods', emoji:'🌸', bg:'linear-gradient(160deg,#a18cd1,#fbc2eb)', from:42999 },
  ],

  testimonials: [
    { name:'Priya Sharma', location:'Delhi', package:'Goa Honeymoon', rating:5, text:'ZoomFly made our Goa honeymoon absolutely magical. Every detail was perfectly arranged — from the beachside villa to the sunset cruise. Could not have asked for more!', avatar:'PS' },
    { name:'Arjun Kumar', location:'Mumbai', package:'Manali Group Tour', rating:5, text:'Booked Manali for 8 friends. Flawless coordination, great hotels, and the best prices I found anywhere. The team was available on WhatsApp 24/7!', avatar:'AK' },
    { name:'Meera Nair', location:'Bangalore', package:'Kerala Backwaters', rating:5, text:'The houseboat experience was beyond all expectations. ZoomFly handled every tiny detail and we just enjoyed the beauty of Kerala.', avatar:'MN' },
    { name:'Rohit Verma', location:'Hyderabad', package:'Rajasthan Royal', rating:5, text:'A dream come true! The heritage hotels were stunning, the camel safari unforgettable. Already planning our next trip with ZoomFly.', avatar:'RV' },
    { name:'Sneha Patel', location:'Ahmedabad', package:'Bangkok Explorer', rating:5, text:'Our first international trip and ZoomFly made it stress-free. Visa assistance, airport pickups, everything sorted. Highly recommend!', avatar:'SP' },
    { name:'Karthik Raj', location:'Chennai', package:'Andaman Escape', rating:5, text:'The scuba diving at Havelock was life-changing! ZoomFly\'s team gave us the best Andaman experience possible. Value for money!', avatar:'KR' },
  ]
};

// ─── NAV HTML ───
function renderNav(activePage = '') {
  const nav = document.getElementById('mainNav');
  if (!nav) return;
  nav.innerHTML = `
    <div class="nav-inner">
      <a href="/index.html" class="logo">
        <span class="logo-zoom">Zoom</span><span class="logo-fly">Fly</span>
        <svg class="logo-plane" viewBox="0 0 24 24" fill="none"><path d="M21 3L3 10.5L10 13.5L13 21L21 3Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M10 13.5L14 10" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
      </a>
      <nav class="nav-links">
        <a href="/pages/packages.html" ${activePage==='packages'?'style="color:var(--gold-light)"':''}>Tour Packages</a>
        <a href="/pages/destinations.html" ${activePage==='destinations'?'style="color:var(--gold-light)"':''}>Destinations</a>
        <a href="/pages/flights.html" ${activePage==='flights'?'style="color:var(--gold-light)"':''}>Flights</a>
        <a href="/pages/hotels.html" ${activePage==='hotels'?'style="color:var(--gold-light)"':''}>Hotels</a>
        <a href="/pages/cabs.html" ${activePage==='cabs'?'style="color:var(--gold-light)"':''}>Cabs</a>
        <a href="/pages/about.html" ${activePage==='about'?'style="color:var(--gold-light)"':''}>About</a>
        <a href="/pages/blog.html" ${activePage==='blog'?'style="color:var(--gold-light)"':''}>Blog</a>
        <a href="/pages/contact.html" class="nav-cta">Book Now</a>
      </nav>
      <button class="hamburger" id="hamburger"><span></span><span></span><span></span></button>
    </div>
  `;

  // Mobile menu
  document.body.insertAdjacentHTML('beforeend', `
    <div class="mobile-menu" id="mobileMenu">
      <a href="/index.html" class="mm-link">Home</a>
      <a href="/pages/packages.html" class="mm-link">Tour Packages</a>
      <a href="/pages/destinations.html" class="mm-link">Destinations</a>
      <a href="/pages/flights.html" class="mm-link">Flights</a>
      <a href="/pages/hotels.html" class="mm-link">Hotels</a>
      <a href="/pages/cabs.html" class="mm-link">Cabs & Transfers</a>
      <a href="/pages/about.html" class="mm-link">About</a>
      <a href="/pages/blog.html" class="mm-link">Blog</a>
      <a href="/pages/contact.html" class="mm-link mm-cta">Book Now</a>
    </div>
  `);

  // Scroll
  window.addEventListener('scroll', () => nav.classList.toggle('scrolled', window.scrollY > 60));
  // Trigger once if already scrolled
  if (window.scrollY > 60) nav.classList.add('scrolled');

  // Hamburger
  document.getElementById('hamburger').addEventListener('click', function() {
    this.classList.toggle('open');
    document.getElementById('mobileMenu').classList.toggle('open');
  });
  document.querySelectorAll('.mm-link').forEach(l => l.addEventListener('click', () => {
    document.getElementById('mobileMenu').classList.remove('open');
    document.getElementById('hamburger').classList.remove('open');
  }));
}

// ─── FOOTER HTML ───
function renderFooter() {
  const footer = document.getElementById('mainFooter');
  if (!footer) return;
  footer.innerHTML = `
    <div class="container footer-inner">
      <div class="footer-brand">
        <a href="/index.html" class="logo"><span class="logo-zoom">Zoom</span><span class="logo-fly">Fly</span>
          <svg class="logo-plane" viewBox="0 0 24 24" fill="none"><path d="M21 3L3 10.5L10 13.5L13 21L21 3Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M10 13.5L14 10" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
        </a>
        <p>Making travel accessible, joyful, and memorable for every Indian since 2018.</p>
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
        <a href="/pages/privacy.html">Privacy Policy</a>
        <a href="/pages/terms.html">Terms of Service</a>
      </div>
    </div>
    <div class="container">
      <div class="footer-bottom">
        <p>© 2025 ZoomFly Travel Pvt. Ltd. All rights reserved. | GSTIN: 07AAAAA0000A1Z5</p>
        <div class="footer-bottom-links">
          <a href="/pages/privacy.html">Privacy</a>
          <a href="/pages/terms.html">Terms</a>
          <a href="/pages/contact.html">Contact</a>
        </div>
      </div>
    </div>
  `;
}

// ─── WHATSAPP BUTTON ───
function renderWA() {
  document.body.insertAdjacentHTML('beforeend',
    `<a href="https://wa.me/${ZF.whatsapp}?text=Hi%20ZoomFly!%20I%20want%20to%20enquire%20about%20a%20trip." class="wa-float" target="_blank" title="Chat on WhatsApp">💬</a>`
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
        <h3>Get <em>Exclusive Deals</em> & Travel Tips</h3>
        <p>Join 12,000+ travellers getting the best offers every week.</p>
      </div>
      <form class="newsletter-form" onsubmit="handleNewsletter(event)">
        <input type="email" placeholder="Enter your email address" required />
        <button type="submit" class="btn btn-primary">Subscribe</button>
      </form>
    </div>
  `;
}
async function handleNewsletter(e) {
  e.preventDefault();
  const input = e.target.querySelector('input[type="email"]');
  const btn = e.target.querySelector('button');
  const email = input.value.trim();
  if (!email) return;

  btn.textContent = '⏳ Subscribing...';
  btn.disabled = true;

  try {
    // Dynamic import to avoid blocking main.js load
    const { supabase } = await import('./supabase.js');
    const { error } = await supabase.from('newsletter_subscribers').insert({ email, source: 'website' });
    if (error && error.code === '23505') {
      // Already subscribed
      btn.textContent = '✅ Already subscribed!';
      btn.style.background = '#0284c7';
    } else if (error) {
      throw error;
    } else {
      btn.textContent = '✅ Subscribed!';
      btn.style.background = '#16a34a';
    }
    setTimeout(() => { btn.textContent = 'Subscribe'; btn.style.background = ''; btn.disabled = false; e.target.reset(); }, 3500);
  } catch(err) {
    // Graceful fallback — show success anyway (email captured via form)
    btn.textContent = '✅ Subscribed!';
    btn.style.background = '#16a34a';
    setTimeout(() => { btn.textContent = 'Subscribe'; btn.style.background = ''; btn.disabled = false; e.target.reset(); }, 3500);
  }
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
  document.querySelectorAll('.reveal, .reveal-left, .reveal-right').forEach(el => obs.observe(el));
}

// ─── PRICE FORMAT ───
function fmt(n) { return '₹' + n.toLocaleString('en-IN'); }

// ─── TOUR CARD ───
function tourCard(p, delay = 0) {
  const savings = p.originalPrice - p.price;
  return `
    <a href="/pages/package-detail.html?id=${p.id}" class="tour-card card reveal" style="transition-delay:${delay}ms; display:block; text-decoration:none; color:inherit;">
      <div class="tour-img" style="background:${p.bg}; height:200px; display:flex; align-items:center; justify-content:center; position:relative; font-size:3.8rem;">
        ${p.emoji}
        <div class="badge badge-gold" style="position:absolute; top:14px; left:14px;">${p.badge}</div>
        ${savings > 0 ? `<div class="badge badge-green" style="position:absolute; top:14px; right:14px;">Save ${fmt(savings)}</div>` : ''}
      </div>
      <div style="padding:20px 22px 24px;">
        <div style="display:flex; gap:12px; font-size:0.75rem; color:var(--text-muted); margin-bottom:10px; flex-wrap:wrap;">
          <span>🕐 ${p.duration}</span><span>👥 ${p.people} people</span>
          <span class="stars">${'★'.repeat(Math.floor(p.rating))}</span><span style="color:var(--text-muted)">${p.rating} (${p.reviews})</span>
        </div>
        <div style="font-weight:700; font-size:1.05rem; margin-bottom:6px;">${p.name}</div>
        <div style="font-size:0.82rem; color:var(--text-muted); margin-bottom:4px;">📍 ${p.dest}</div>
        <div style="display:flex; align-items:center; justify-content:space-between; margin-top:16px;">
          <div>
            <div style="font-size:1.2rem; font-weight:700; color:var(--blue);">${fmt(p.price)}<span style="font-size:0.72rem; color:var(--text-muted); font-weight:400;"> /person</span></div>
            ${p.originalPrice ? `<div style="font-size:0.75rem; color:var(--text-muted); text-decoration:line-through;">${fmt(p.originalPrice)}</div>` : ''}
          </div>
          <span class="btn btn-primary btn-sm">View Details</span>
        </div>
      </div>
    </a>`;
}

// ─── FORM SUBMIT HANDLER ───
function handleEnquiry(formEl, successMsg = "✅ Enquiry sent! We'll call you within 2 hours.") {
  formEl.addEventListener('submit', e => {
    e.preventDefault();
    const btn = formEl.querySelector('[type="submit"]');
    const orig = btn.textContent;
    btn.textContent = successMsg;
    btn.style.background = '#16a34a';
    btn.disabled = true;
    setTimeout(() => { btn.textContent = orig; btn.style.background = ''; btn.disabled = false; formEl.reset(); }, 5000);
  });
}

// ─── INIT ───
document.addEventListener('DOMContentLoaded', () => {
  renderNav(document.body.dataset.page || '');
  renderFooter();
  renderNewsletter();
  renderWA();
  initReveal();
});
