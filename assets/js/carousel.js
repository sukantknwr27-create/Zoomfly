// ============================================================
// Shared, admin-managed banner carousel.
// Used by index.html, destinations.html, packages.html, flights.html,
// cabs.html, bus.html, trains.html, hotels.html.
//
// Call initCarousel('home', 'carousel-home') etc. — if there are no
// active slides for that page_key, this does nothing and the page's
// existing static hero/banner shows through untouched.
// ============================================================
import { getCarouselSlides } from './supabase.js';

function esc(s) {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

// Only allow http(s) links through to href — an admin-authored
// javascript: URL in cta_link should never be able to execute.
function safeUrl(u) {
  if (!u) return '';
  const s = String(u).trim();
  if (/^https?:\/\//i.test(s) || s.startsWith('/')) return s;
  return '#';
}

let seq = 0;

export async function initCarousel(pageKey, containerId) {
  const el = document.getElementById(containerId);
  if (!el) return;

  let slides = [];
  try {
    slides = await getCarouselSlides(pageKey);
  } catch (e) {
    console.warn('[carousel] could not load slides for', pageKey, e.message);
    return; // leave whatever static content the page already has
  }
  if (!slides.length) return; // no active slides — static fallback shows through

  const uid = 'car' + (++seq);
  el.classList.add('zf-carousel');
  el.innerHTML = `
    <div class="zfc-track" id="${uid}-track">
      ${slides.map((s, i) => `
        <div class="zfc-slide" style="background-image:linear-gradient(180deg,rgba(12,27,51,.25),rgba(12,27,51,.65)),url('${esc(s.image_url)}')">
          <div class="zfc-content">
            ${s.title ? `<h2 class="zfc-title">${esc(s.title)}</h2>` : ''}
            ${s.subtitle ? `<p class="zfc-subtitle">${esc(s.subtitle)}</p>` : ''}
            ${s.cta_text && s.cta_link ? `<a class="zfc-cta" href="${esc(safeUrl(s.cta_link))}">${esc(s.cta_text)}</a>` : ''}
          </div>
        </div>`).join('')}
    </div>
    ${slides.length > 1 ? `
      <button class="zfc-arrow zfc-prev" aria-label="Previous slide">&#8249;</button>
      <button class="zfc-arrow zfc-next" aria-label="Next slide">&#8250;</button>
      <div class="zfc-dots">${slides.map((_, i) => `<span class="zfc-dot${i === 0 ? ' active' : ''}" data-i="${i}"></span>`).join('')}</div>
    ` : ''}
  `;

  if (!document.getElementById('zfc-styles')) {
    const style = document.createElement('style');
    style.id = 'zfc-styles';
    style.textContent = `
      .zf-carousel{position:relative;width:100%;overflow:hidden;border-radius:0}
      .zfc-track{display:flex;transition:transform .5s ease}
      .zfc-slide{flex:0 0 100%;min-height:320px;background-size:cover;background-position:center;display:flex;align-items:center;padding:0 6vw}
      .zfc-content{max-width:560px;color:#fff}
      .zfc-title{font-family:'Cormorant Garamond',serif;font-size:clamp(1.8rem,4vw,3rem);font-weight:600;margin-bottom:10px;line-height:1.15}
      .zfc-subtitle{font-size:.95rem;opacity:.88;margin-bottom:18px;line-height:1.5}
      .zfc-cta{display:inline-block;padding:.75rem 1.6rem;background:#C9922A;color:#0C1B33;border-radius:100px;font-weight:700;font-size:.88rem;text-decoration:none;transition:background .2s}
      .zfc-cta:hover{background:#E8B84B}
      .zfc-arrow{position:absolute;top:50%;transform:translateY(-50%);width:38px;height:38px;border-radius:50%;background:rgba(255,255,255,.18);border:1px solid rgba(255,255,255,.3);color:#fff;font-size:1.4rem;line-height:1;cursor:pointer;display:flex;align-items:center;justify-content:center;transition:background .2s;z-index:2}
      .zfc-arrow:hover{background:rgba(255,255,255,.32)}
      .zfc-prev{left:16px}.zfc-next{right:16px}
      .zfc-dots{position:absolute;bottom:14px;left:0;right:0;display:flex;justify-content:center;gap:7px;z-index:2}
      .zfc-dot{width:8px;height:8px;border-radius:50%;background:rgba(255,255,255,.4);cursor:pointer;transition:background .2s}
      .zfc-dot.active{background:#fff}
      @media(max-width:640px){.zfc-slide{min-height:240px;padding:0 5vw}}
    `;
    document.head.appendChild(style);
  }

  const track = document.getElementById(`${uid}-track`);
  const dots  = el.querySelectorAll('.zfc-dot');
  let current = 0;
  const go = (i) => {
    current = (i + slides.length) % slides.length;
    track.style.transform = `translateX(-${current * 100}%)`;
    dots.forEach((d, di) => d.classList.toggle('active', di === current));
  };

  el.querySelector('.zfc-prev')?.addEventListener('click', () => { go(current - 1); resetAutoplay(); });
  el.querySelector('.zfc-next')?.addEventListener('click', () => { go(current + 1); resetAutoplay(); });
  dots.forEach(d => d.addEventListener('click', () => { go(parseInt(d.dataset.i)); resetAutoplay(); }));

  // Swipe support
  let touchStartX = null;
  el.addEventListener('touchstart', e => { touchStartX = e.touches[0].clientX; }, { passive: true });
  el.addEventListener('touchend', e => {
    if (touchStartX === null) return;
    const dx = e.changedTouches[0].clientX - touchStartX;
    if (Math.abs(dx) > 40) go(dx < 0 ? current + 1 : current - 1);
    touchStartX = null;
    resetAutoplay();
  }, { passive: true });

  let autoplayTimer = null;
  function startAutoplay() {
    if (slides.length < 2) return;
    autoplayTimer = setInterval(() => go(current + 1), 5500);
  }
  function resetAutoplay() {
    clearInterval(autoplayTimer);
    startAutoplay();
  }
  el.addEventListener('mouseenter', () => clearInterval(autoplayTimer));
  el.addEventListener('mouseleave', startAutoplay);
  startAutoplay();
}
