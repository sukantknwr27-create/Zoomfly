// ZoomFly — Homepage JS
// Loads packages/testimonials from Supabase with static fallback

const STATIC_PKGS = [
  { id:'goa-beach',      title:'Goa Beach Escape',        bg_gradient:'linear-gradient(135deg,#667eea,#764ba2)', price:6999,  old_price:8999,  duration_days:4, nights:3, destination:'Goa' },
  { id:'manali-snow',    title:'Manali Snow Adventure',    bg_gradient:'linear-gradient(135deg,#f093fb,#f5576c)', price:10499, old_price:13999, duration_days:6, nights:5, destination:'Manali' },
  { id:'kerala-tour',    title:'Kerala Backwaters Tour',   bg_gradient:'linear-gradient(135deg,#4facfe,#00f2fe)', price:9999,  old_price:12499, duration_days:5, nights:4, destination:'Kerala' },
  { id:'rajasthan-royal',title:'Royal Rajasthan Circuit',  bg_gradient:'linear-gradient(135deg,#fa709a,#fee140)', price:12999, old_price:16999, duration_days:7, nights:6, destination:'Rajasthan' },
  { id:'bali-dream',     title:'Bali Dream Holiday',       bg_gradient:'linear-gradient(135deg,#a1c4fd,#c2e9fb)', price:42999, old_price:54999, duration_days:7, nights:6, destination:'Bali' },
  { id:'andaman-pearl',  title:'Andaman Pearl Islands',    bg_gradient:'linear-gradient(135deg,#43e97b,#38f9d7)', price:14999, old_price:18999, duration_days:5, nights:4, destination:'Andaman' },
];

// No static testimonials — only real, Supabase-sourced reviews are shown.
const STATIC_TESTIMONIALS = [];

const DEST_IMAGES = {
  'Goa':       'https://images.unsplash.com/photo-1512343879522-8a4df9a27b14?w=600&h=400&fit=crop&auto=format',
  'Manali':    'https://images.unsplash.com/photo-1582552938357-6dcb01ab3afe?w=600&h=400&fit=crop&auto=format',
  'Kerala':    'https://images.unsplash.com/photo-1602216056096-3b40cc0c9944?w=600&h=400&fit=crop&auto=format',
  'Rajasthan': 'https://images.unsplash.com/photo-1599661046827-dacff0a39b4e?w=600&h=400&fit=crop&auto=format',
  'Andaman':   'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=600&h=400&fit=crop&auto=format',
  'Darjeeling':'https://images.unsplash.com/photo-1580674684081-7617fbf3d745?w=600&h=400&fit=crop&auto=format',
  'Bangkok':   'https://images.unsplash.com/photo-1528360983277-13d401cdc186?w=600&h=400&fit=crop&auto=format',
  'Bali':      'https://images.unsplash.com/photo-1537996194471-e657df975ab4?w=600&h=400&fit=crop&auto=format',
};

document.addEventListener('DOMContentLoaded', async () => {
  // Search tabs
  document.querySelectorAll('.stab').forEach(tab => {
    tab.addEventListener('click', () => {
      document.querySelectorAll('.stab').forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
    });
  });

  // ── Packages grid ──────────────────────────────────────────
  const grid = document.getElementById('homePackages');
  if (grid) {
    // Show static packages instantly
    grid.innerHTML = STATIC_PKGS.map((p,i) => tourCard(p, i*80)).join('');
    if (typeof initReveal === 'function') initReveal();

    // Try to load from Supabase in background
    try {
      const { supabase } = await import('./supabase.js');
      const { data } = await supabase
        .from('packages').select('*').eq('is_active', true)
        .order('review_count', { ascending: false }).limit(6);
      if (data?.length) {
        grid.innerHTML = data.map((p,i) => tourCard(p, i*80)).join('');
        if (typeof initReveal === 'function') initReveal();
      }
    } catch(e) { console.warn('[home] packages fetch failed, using static list:', e?.message); }
  }

  // ── Destinations grid ──────────────────────────────────────
  // Shows the hardcoded list instantly (so the section never looks empty
  // while the network request is in flight), then swaps in whichever
  // destinations the admin has actually marked "Show in homepage featured
  // destinations grid" in Admin → Destinations, if any exist.
  const destGrid = document.getElementById('homeDestinations');
  if (destGrid && typeof ZF !== 'undefined') {
    const renderDestCard = (d, i) => {
      const imgUrl = d.image || DEST_IMAGES[d.name] || 'https://images.unsplash.com/photo-1488085061851-e0efdae7d6e3?w=600&h=400&fit=crop&auto=format';
      const href = '/pages/destinations.html';
      return `<div class="dest-card reveal ${i===0?'dest-large':''}"
        style="--bg:${d.bg};transition-delay:${i*60}ms;background-image:url('${imgUrl}');background-size:cover;background-position:center"
        onclick="window.location='${href}'">
        <div class="dest-overlay" style="background:linear-gradient(to top,rgba(0,0,0,0.7) 0%,rgba(0,0,0,0.1) 60%)"></div>
        <div class="dest-info">
          <div class="dest-name">${esc(d.name)}</div>
          <div class="dest-tagline">${esc(d.tagline||'')}</div>
          <div class="dest-price">From ₹${Number(d.from||0).toLocaleString('en-IN')}</div>
        </div>
      </div>`;
    };

    destGrid.innerHTML = ZF.destinations.map(renderDestCard).join('');
    if (typeof initReveal === 'function') initReveal();

    try {
      const { supabase } = await import('./supabase.js');
      const { data } = await supabase
        .from('destinations').select('*')
        .eq('is_active', true).eq('is_featured', true)
        .order('name').limit(8);
      if (data?.length) {
        const mapped = data.map(d => ({
          id: d.id, name: d.name, tagline: d.tagline,
          bg: d.bg_gradient || 'linear-gradient(160deg,#667eea,#764ba2)',
          from: d.from_price, image: d.image_url,
        }));
        destGrid.innerHTML = mapped.map(renderDestCard).join('');
        if (typeof initReveal === 'function') initReveal();
      }
    } catch(e) { console.warn('[home] destinations fetch failed, using static list:', e?.message); }
  }

  // ── Testimonials ───────────────────────────────────────────
  const testiGrid = document.getElementById('homeTestimonials');
  if (testiGrid) {
    let testimonials = STATIC_TESTIMONIALS;
    try {
      const { supabase } = await import('./supabase.js');
      const { data } = await supabase
        .from('reviews').select('*')
        .eq('is_featured', true).eq('is_approved', true)
        .order('rating', { ascending: false }).limit(3);
      if (data?.length) {
        testimonials = data.map(r => ({
          rating:   r.rating,
          text:     r.body || r.review_text || '',
          name:     r.reviewer_name || 'Traveller',
          location: r.reviewer_location || 'India',
          package:  r.package_name || '',
          avatar:   '',
        }));
      }
    } catch(_) { /* keep static */ }

    // Build testimonial cards safely using DOM methods (no innerHTML with user data)
    testiGrid.innerHTML = '';
    testimonials.slice(0,3).forEach((t, i) => {
      const card = document.createElement('div');
      card.className = `testi-card reveal ${i===1?'testi-featured':''}`;
      card.style.transitionDelay = `${i*80}ms`;

      const stars = document.createElement('div');
      stars.className = 'testi-stars';
      stars.textContent = '★'.repeat(Math.min(5, Math.max(0, parseInt(t.rating) || 5)));

      const quote = document.createElement('p');
      quote.textContent = `"${t.text}"`;

      const avatar = document.createElement('div');
      avatar.className = 'testi-avatar';
      avatar.textContent = t.avatar || '';

      const nameEl = document.createElement('div');
      nameEl.className = 'testi-name';
      nameEl.textContent = t.name || '';

      const sub = document.createElement('div');
      sub.className = 'testi-sub';
      sub.textContent = t.location + (t.package ? ' · ' + t.package : '');

      const authorInfo = document.createElement('div');
      authorInfo.appendChild(nameEl);
      authorInfo.appendChild(sub);

      const author = document.createElement('div');
      author.className = 'testi-author';
      author.appendChild(avatar);
      author.appendChild(authorInfo);

      card.appendChild(stars);
      card.appendChild(quote);
      card.appendChild(author);
      testiGrid.appendChild(card);
    });
    if (typeof initReveal === 'function') initReveal();
  }

  // ── FAQ ────────────────────────────────────────────────────
  const faqs = [
    { q:'How do I book a tour package?',         a:'Browse our packages, click "View Details", and fill the enquiry form. Our team calls you within 2 hours to confirm.' },
    { q:'Are the prices per person or per group?',a:'All prices are per person. Group discounts (6+ travellers) are available — contact us for a custom quote.' },
    { q:'What is included in tour packages?',    a:'Inclusions vary but typically include hotels, breakfast, sightseeing and transfers. Full inclusions are listed on each package page.' },
    { q:'Can I customise an existing itinerary?',a:'Yes! All packages can be customised — add destinations, upgrade hotels, or extend duration. Just tell us your needs.' },
  ];
  const faqEl = document.getElementById('homeFaqs');
  if (faqEl) {
    faqEl.innerHTML = faqs.map(f =>
      `<div class="faq-item">
        <div class="faq-q" onclick="toggleFaq(this)">${f.q}<span class="faq-arrow">▼</span></div>
        <div class="faq-a"><p>${f.a}</p></div>
      </div>`
    ).join('');
  }
});

function toggleFaq(el) {
  el.classList.toggle('open');
  el.nextElementSibling.classList.toggle('open');
}
