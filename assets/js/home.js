document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('.stab').forEach(tab => {
    tab.addEventListener('click', () => {
      document.querySelectorAll('.stab').forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
    });
  });

  const grid = document.getElementById('homePackages');
  if (grid) { grid.innerHTML = ZF.packages.slice(0,6).map((p,i)=>tourCard(p,i*80)).join(''); initReveal(); }

  const destGrid = document.getElementById('homeDestinations');
  if (destGrid) {
    destGrid.innerHTML = ZF.destinations.map((d,i)=>`
      <div class="dest-card reveal ${i===0?'dest-large':''}" style="--bg:${d.bg};transition-delay:${i*60}ms;" onclick="window.location='pages/packages.html'">
        <div class="dest-overlay"></div><span class="dest-emoji">${d.emoji}</span>
        <div class="dest-info"><div class="dest-name">${d.name}</div><div class="dest-tagline">${d.tagline}</div><div class="dest-price">From ₹${d.from.toLocaleString('en-IN')}</div></div>
      </div>`).join('');
    initReveal();
  }

  const testiGrid = document.getElementById('homeTestimonials');
  if (testiGrid) {
    testiGrid.innerHTML = ZF.testimonials.slice(0,3).map((t,i)=>`
      <div class="testi-card reveal ${i===1?'testi-featured':''}" style="transition-delay:${i*80}ms;">
        <div class="testi-stars">${'★'.repeat(t.rating)}</div>
        <p>"${t.text}"</p>
        <div class="testi-author">
          <div class="testi-avatar">${t.avatar}</div>
          <div><div class="testi-name">${t.name}</div><div class="testi-sub">${t.location} · ${t.package}</div></div>
        </div>
      </div>`).join('');
    initReveal();
  }

  const faqs=[
    {q:'How do I book a tour package?',a:'Browse our packages, click "View Details", and fill the enquiry form. Our team calls you within 2 hours to confirm.'},
    {q:'Are the prices per person or per group?',a:'All prices are per person. Group discounts (6+ travellers) are available — contact us for a custom quote.'},
    {q:'What is included in tour packages?',a:'Inclusions vary but typically include hotels, breakfast, sightseeing and transfers. Full inclusions are listed on each package page.'},
    {q:'Can I customise an existing itinerary?',a:'Yes! All packages can be customised — add destinations, upgrade hotels, or extend duration. Just tell us your needs.'},
  ];
  const faqEl=document.getElementById('homeFaqs');
  if(faqEl) faqEl.innerHTML=faqs.map(f=>`<div class="faq-item"><div class="faq-q" onclick="toggleFaq(this)">${f.q}<span class="faq-arrow">▼</span></div><div class="faq-a"><p>${f.a}</p></div></div>`).join('');
});
function toggleFaq(el){el.classList.toggle('open');el.nextElementSibling.classList.toggle('open');}
