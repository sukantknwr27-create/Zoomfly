// ZoomFly — Homepage JS
// Loads packages/testimonials from Supabase with static fallback

const STATIC_PKGS = [
  { id:'goa-beach',      title:'Goa Beach Escape',        emoji:'🏖️', bg_gradient:'linear-gradient(135deg,#667eea,#764ba2)', price:6999,  old_price:8999,  rating:4.8, review_count:324, duration_days:4, nights:3, destination:'Goa',       badge:'Best Seller'   },
  { id:'manali-snow',    title:'Manali Snow Adventure',    emoji:'🏔️', bg_gradient:'linear-gradient(135deg,#f093fb,#f5576c)', price:10499, old_price:13999, rating:4.9, review_count:218, duration_days:6, nights:5, destination:'Manali',    badge:'Top Rated'     },
  { id:'kerala-tour',    title:'Kerala Backwaters Tour',   emoji:'🌴', bg_gradient:'linear-gradient(135deg,#4facfe,#00f2fe)', price:9999,  old_price:12499, rating:4.7, review_count:189, duration_days:5, nights:4, destination:'Kerala',    badge:'Trending'      },
  { id:'rajasthan-royal',title:'Royal Rajasthan Circuit',  emoji:'🏰', bg_gradient:'linear-gradient(135deg,#fa709a,#fee140)', price:12999, old_price:16999, rating:4.8, review_count:156, duration_days:7, nights:6, destination:'Rajasthan', badge:'Heritage'      },
  { id:'bali-dream',     title:'Bali Dream Holiday',       emoji:'🌸', bg_gradient:'linear-gradient(135deg,#a1c4fd,#c2e9fb)', price:42999, old_price:54999, rating:4.9, review_count:412, duration_days:7, nights:6, destination:'Bali',      badge:'International' },
  { id:'andaman-pearl',  title:'Andaman Pearl Islands',    emoji:'🐠', bg_gradient:'linear-gradient(135deg,#43e97b,#38f9d7)', price:14999, old_price:18999, rating:4.7, review_count:203, duration_days:5, nights:4, destination:'Andaman',   badge:'Island Life'   },
];

const STATIC_TESTIMONIALS = [
  { rating:5, text:'Absolutely amazing experience! ZoomFly organised everything perfectly. Our Manali trip was a dream come true. Will book again!', name:'Priya Sharma', location:'Delhi', package:'Manali Snow Adventure', avatar:'🙋‍♀️' },
  { rating:5, text:'Best travel agency in India. The Goa package was spot on — hotel, transfers, sightseeing, everything was seamless. Thank you ZoomFly!', name:'Rahul Mehta', location:'Mumbai', package:'Goa Beach Escape', avatar:'🙋‍♂️' },
  { rating:5, text:'Booked Kerala trip for our honeymoon through ZoomFly. The team was so helpful and the experience was magical. Highly recommended!', name:'Anjali & Vikram', location:'Bangalore', package:'Kerala Backwaters', avatar:'👫' },
];

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
    } catch(_) { /* keep static */ }
  }

  // ── Destinations grid ──────────────────────────────────────
  const destGrid = document.getElementById('homeDestinations');
  if (destGrid && typeof ZF !== 'undefined') {
    destGrid.innerHTML = ZF.destinations.map((d, i) => {
      const imgUrl = DEST_IMAGES[d.name] || 'https://images.unsplash.com/photo-1488085061851-e0efdae7d6e3?w=600&h=400&fit=crop&auto=format';
      return `<div class="dest-card reveal ${i===0?'dest-large':''}"
        style="--bg:${d.bg};transition-delay:${i*60}ms;background-image:url('${imgUrl}');background-size:cover;background-position:center"
        onclick="window.location='/pages/packages.html'">
        <div class="dest-overlay" style="background:linear-gradient(to top,rgba(0,0,0,0.7) 0%,rgba(0,0,0,0.1) 60%)"></div>
        <div class="dest-info">
          <div class="dest-name">${d.name}</div>
          <div class="dest-tagline">${d.tagline}</div>
          <div class="dest-price">From ₹${d.from.toLocaleString('en-IN')}</div>
        </div>
      </div>`;
    }).join('');
    if (typeof initReveal === 'function') initReveal();
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
          avatar:   '⭐',
        }));
      }
    } catch(_) { /* keep static */ }

    testiGrid.innerHTML = testimonials.slice(0,3).map((t,i) => `
      <div class="testi-card reveal ${i===1?'testi-featured':''}" style="transition-delay:${i*80}ms">
        <div class="testi-stars">${'★'.repeat(t.rating)}</div>
        <p>"${t.text}"</p>
        <div class="testi-author">
          <div class="testi-avatar">${t.avatar}</div>
          <div>
            <div class="testi-name">${t.name}</div>
            <div class="testi-sub">${t.location}${t.package ? ' · ' + t.package : ''}</div>
          </div>
        </div>
      </div>`).join('');
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
