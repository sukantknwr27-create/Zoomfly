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
    const destImages = {
      'Goa': 'https://images.unsplash.com/photo-1512343879522-8a4df9a27b14?w=600&h=400&fit=crop&auto=format',
      'Manali': 'https://images.unsplash.com/photo-1582552938357-6dcb01ab3afe?w=600&h=400&fit=crop&auto=format',
      'Kerala': 'https://images.unsplash.com/photo-1602216056096-3b40cc0c9944?w=600&h=400&fit=crop&auto=format',
      'Rajasthan': 'https://images.unsplash.com/photo-1599661046827-dacff0a39b4e?w=600&h=400&fit=crop&auto=format',
      'Andaman': 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=600&h=400&fit=crop&auto=format',
      'Darjeeling': 'https://images.unsplash.com/photo-1580674684081-7617fbf3d745?w=600&h=400&fit=crop&auto=format',
      'Bangkok': 'https://images.unsplash.com/photo-1528360983277-13d401cdc186?w=600&h=400&fit=crop&auto=format',
      'Bali': 'https://images.unsplash.com/photo-1537996194471-e657df975ab4?w=600&h=400&fit=crop&auto=format',
    };
    destGrid.innerHTML = ZF.destinations.map((d,i)=>{
      const imgUrl = destImages[d.name] || `https://images.unsplash.com/photo-1488085061851-e0efdae7d6e3?w=600&h=400&fit=crop&auto=format`;
      return `<div class="dest-card reveal ${i===0?'dest-large':''}" style="--bg:${d.bg};transition-delay:${i*60}ms;background-image:url('${imgUrl}');background-size:cover;background-position:center" onclick="window.location='/pages/packages.html'">
        <div class="dest-overlay" style="background:linear-gradient(to top,rgba(0,0,0,0.7) 0%,rgba(0,0,0,0.1) 60%)"></div>
        <div class="dest-info"><div class="dest-name">${d.name}</div><div class="dest-tagline">${d.tagline}</div><div class="dest-price">From ₹${d.from.toLocaleString('en-IN')}</div></div>
      </div>`;
    }).join('');
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
