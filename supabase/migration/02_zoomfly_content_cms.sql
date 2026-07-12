-- ================================================================
-- ZoomFly — 02_zoomfly_content_cms.sql
-- Run AFTER 00_zoomfly_master_schema.sql and 01_zoomfly_growth_features.sql,
-- against STAGING first.
--
-- What this file does (each block is idempotent/safe to re-run):
--   1. blog_posts   — the entire blog (blog.html + blog-post.html) was
--      100% hardcoded HTML/JS with zero database backing. Adding or
--      editing a post meant editing code and redeploying. This table
--      lets admin manage posts like every other content type.
--   2. faqs         — every question/answer on faq.html was hardcoded
--      inline HTML, grouped under hardcoded section headers. Moved to
--      a real table with a `section` + `section_label` pair so the
--      existing section-grouped layout can be reproduced dynamically.
--   3. job_openings — careers.html's 6 job cards were hardcoded HTML.
--      Moved to a table so postings can be added/closed without a
--      code change.
--
-- All three follow the same RLS shape already used everywhere else
-- in this schema: public (anon + authenticated) can only read
-- published/active rows; only admins (public.is_admin()) can do
-- anything else, including reading unpublished/inactive rows for
-- preview purposes in the admin panel.
-- ================================================================

-- ----------------------------------------------------------------
-- 1. BLOG POSTS
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.blog_posts (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  slug          TEXT NOT NULL UNIQUE,          -- used in /pages/blog-post.html?id=<slug>
  title         TEXT NOT NULL,
  excerpt       TEXT,                          -- shown on the blog listing card
  body          TEXT NOT NULL,                 -- HTML content, rendered into .post-body
  emoji         TEXT DEFAULT '🗺️',              -- hero/card icon (site has no image upload yet)
  bg_gradient   TEXT DEFAULT 'linear-gradient(135deg,#667eea,#764ba2)',
  category      TEXT DEFAULT 'Guide',
  badge_class   TEXT DEFAULT 'badge-gold',      -- matches existing badge-gold/badge-blue/badge-green classes
  author        TEXT DEFAULT 'ZoomFly Team',
  read_time     TEXT DEFAULT '5 min read',
  tags          TEXT[] DEFAULT '{}',
  is_featured   BOOLEAN NOT NULL DEFAULT FALSE, -- featured post gets the large card on blog.html
  is_published  BOOLEAN NOT NULL DEFAULT TRUE,
  published_at  TIMESTAMPTZ DEFAULT NOW(),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_blog_posts_slug        ON public.blog_posts(slug);
CREATE INDEX IF NOT EXISTS idx_blog_posts_published    ON public.blog_posts(is_published, published_at DESC);

ALTER TABLE public.blog_posts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS blog_posts_public_read ON public.blog_posts;
CREATE POLICY blog_posts_public_read ON public.blog_posts
  FOR SELECT USING (is_published = TRUE OR public.is_admin());

DROP POLICY IF EXISTS blog_posts_admin_all ON public.blog_posts;
CREATE POLICY blog_posts_admin_all ON public.blog_posts
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ----------------------------------------------------------------
-- 2. FAQS
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.faqs (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  section        TEXT NOT NULL,                 -- e.g. 'booking', 'payments' — groups questions
  section_label  TEXT NOT NULL,                 -- e.g. '📋 Booking Process' — the h2 shown above the group
  question       TEXT NOT NULL,
  answer         TEXT NOT NULL,
  sort_order     INTEGER NOT NULL DEFAULT 0,    -- controls order within a section
  is_published   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_faqs_section ON public.faqs(section, sort_order);

ALTER TABLE public.faqs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS faqs_public_read ON public.faqs;
CREATE POLICY faqs_public_read ON public.faqs
  FOR SELECT USING (is_published = TRUE OR public.is_admin());

DROP POLICY IF EXISTS faqs_admin_all ON public.faqs;
CREATE POLICY faqs_admin_all ON public.faqs
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ----------------------------------------------------------------
-- 3. JOB OPENINGS
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.job_openings (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title           TEXT NOT NULL,
  department      TEXT NOT NULL DEFAULT 'General',
  department_icon TEXT DEFAULT '💼',
  location        TEXT DEFAULT 'Delhi',
  job_type        TEXT DEFAULT 'Full-time',
  salary_range    TEXT,                          -- free text, e.g. '₹18–28 LPA'
  description     TEXT,
  sort_order      INTEGER NOT NULL DEFAULT 0,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_job_openings_active ON public.job_openings(is_active, sort_order);

ALTER TABLE public.job_openings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS job_openings_public_read ON public.job_openings;
CREATE POLICY job_openings_public_read ON public.job_openings
  FOR SELECT USING (is_active = TRUE OR public.is_admin());

DROP POLICY IF EXISTS job_openings_admin_all ON public.job_openings;
CREATE POLICY job_openings_admin_all ON public.job_openings
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ----------------------------------------------------------------
-- 4. SEED DATA — migrate the existing hardcoded content so the site
--    doesn't go blank the moment the frontend switches to reading
--    from these tables. Admin can edit/delete any of this afterward.
-- ----------------------------------------------------------------
INSERT INTO public.blog_posts (slug, title, excerpt, body, emoji, bg_gradient, category, badge_class, author, read_time, tags, is_featured, published_at)
VALUES
('manali-guide',
 'The Ultimate Manali Travel Guide 2025 — Everything You Need to Know',
 'Planning a trip to Manali? We cover the best time to visit, top attractions, where to stay, what to eat, how to get there and everything in between.',
 '<p>Manali is Himachal Pradesh''s crown jewel — a Himalayan town that blends adventure, romance, and natural beauty like nowhere else in India.</p><h2>Best Time to Visit</h2><p>October to February for snow, March to June for pleasant weather and river activities.</p>',
 '🏔️', 'linear-gradient(135deg,#667eea,#764ba2)', 'Guide', 'badge-gold', 'Aakash Kumar', '8 min read',
 ARRAY['Manali','Himachal','Guide','Snow','Adventure'], TRUE, '2025-03-15'::timestamptz),

('goa-off-season',
 'Why You Should Visit Goa in the Off-Season (May–Sep)',
 'Fewer crowds, lower prices and lush green landscapes make monsoon Goa a hidden gem.',
 '<p>Everyone visits Goa in winter. Here''s why the monsoon season is Goa''s best-kept secret.</p>',
 '🏖️', 'linear-gradient(135deg,#f6d365,#fda085)', 'Tips', 'badge-blue', 'ZoomFly Team', '5 min read',
 ARRAY['Goa','Monsoon','Budget'], FALSE, '2025-02-28'::timestamptz),

('budget-travel',
 '10 Ways to Travel India on a Budget Without Compromising Fun',
 'From train passes to homestays — smart tricks that seasoned travellers swear by.',
 '<p>Travelling India doesn''t have to be expensive. Here are 10 proven ways to stretch your rupee further.</p>',
 '💰', 'linear-gradient(135deg,#43e97b,#38f9d7)', 'Budget', 'badge-green', 'ZoomFly Team', '6 min read',
 ARRAY['Budget','Backpacking','India'], FALSE, '2025-02-10'::timestamptz),

('kerala-honeymoon',
 'Kerala Honeymoon Guide: Backwaters, Beaches & Bliss',
 'Everything you need to plan a romantic Kerala honeymoon — from houseboat bookings to the best resorts.',
 '<p>Kerala — "God''s Own Country" — is arguably India''s most romantic destination.</p><h2>The Perfect Itinerary</h2><p>Kochi, Munnar, Alleppey houseboat, and Kovalam beach.</p>',
 '💕', 'linear-gradient(135deg,#a18cd1,#fbc2eb)', 'Honeymoon', 'badge-gold', 'ZoomFly Team', '7 min read',
 ARRAY['Kerala','Honeymoon','Backwaters'], FALSE, '2025-01-22'::timestamptz),

('rajasthan-winter',
 'Best Time to Visit Rajasthan — A Month-by-Month Breakdown',
 'Rajasthan is a year-round destination, but each season offers a dramatically different experience.',
 '<p>Here''s the definitive month-by-month guide to visiting Rajasthan.</p><h2>October–February: Peak Season</h2><p>Pleasantly warm days, cool nights, perfect photography light.</p>',
 '🏰', 'linear-gradient(135deg,#fa709a,#fee140)', 'Seasonal', 'badge-blue', 'Aakash Kumar', '5 min read',
 ARRAY['Rajasthan','Best Time','Seasonal','Heritage','Desert'], FALSE, '2025-01-05'::timestamptz),

('bangkok-tips',
 'Bangkok for First-Timers: The Only Guide You''ll Ever Need',
 'Bangkok is overwhelming, exhilarating, and utterly unforgettable — here''s everything you need for your first visit.',
 '<p>Bangkok is a city of contradictions — ancient temples next to gleaming malls.</p><h2>Essential Experiences</h2><p>Grand Palace, Chatuchak Market, and the floating markets.</p>',
 '🗼', 'linear-gradient(135deg,#4facfe,#00f2fe)', 'International', 'badge-gold', 'Rajiv Gupta', '9 min read',
 ARRAY['Bangkok','Thailand','International','First-Timer','Asia'], FALSE, '2024-12-18'::timestamptz)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO public.faqs (section, section_label, question, answer, sort_order) VALUES
('booking','📋 Booking Process','How do I book a tour package?','Browse our packages, click "View Details" to explore the itinerary and pricing, then click "Book This Package" or submit the enquiry form. Our travel expert will call you within 2 hours to confirm availability and walk you through the booking process.',1),
('booking','📋 Booking Process','How far in advance should I book?','We recommend booking at least 2–4 weeks in advance for domestic packages and 4–8 weeks for international ones. However, we can often arrange last-minute trips within 48–72 hours depending on availability.',2),
('booking','📋 Booking Process','Can I customise any package?','Absolutely! Every package can be customised. You can change hotels, extend/shorten duration, add or remove activities, modify the itinerary, and adjust for group size. Just mention your requirements when you contact us.',3),
('booking','📋 Booking Process','Do you offer group bookings?','Yes! We specialise in group bookings for families, friends, corporate teams, and school trips. Groups of 10+ get special pricing and a dedicated coordinator. Contact us for a group quote.',4),
('payments','💳 Payments & EMI','What payment methods do you accept?','We accept all major credit/debit cards, UPI (GPay, PhonePe, Paytm), net banking, and bank transfers. International payments can be made via bank wire or card.',1),
('payments','💳 Payments & EMI','Is EMI available?','Yes! EMI is available through select credit cards (HDFC, ICICI, SBI, Axis) for packages above ₹15,000. 3, 6, and 12-month EMI options are available. Contact us for details on your specific bank and card.',2),
('payments','💳 Payments & EMI','How much advance do I need to pay to confirm?','A 30% advance confirms your booking. The balance is due 15 days before your travel date. For bookings made within 15 days of travel, full payment is required at the time of booking.',3),
('cancellation','🔄 Cancellation & Refund','What is your cancellation policy?','Cancellations 30+ days before travel: 90% refund. 15–30 days: 50% refund. Within 15 days: no refund (we recommend travel insurance). Refunds are processed within 7–10 business days.',1),
('cancellation','🔄 Cancellation & Refund','Can I reschedule my trip?','Yes, rescheduling is allowed up to 15 days before travel at no extra charge (subject to availability). Rescheduling within 15 days may incur a fee depending on hotel and transport policies.',2),
('cancellation','🔄 Cancellation & Refund','Is travel insurance included?','Basic travel insurance is included in select packages. We strongly recommend comprehensive insurance for all trips, which we can arrange at a nominal cost. This covers trip cancellation, medical emergencies, and baggage loss.',3),
('packages','🗺️ Tour Packages','Are meals included in tour packages?','Meal inclusions vary by package — each package page clearly lists what''s included (breakfast, half-board, or all-inclusive). You can always upgrade meal plans when enquiring.',1),
('packages','🗺️ Tour Packages','Do you arrange visa for international tours?','We provide visa assistance for all our international tour packages. This includes document checklists, form filling guidance, and application submission support. Visa fees are paid directly by you to the consulate/embassy.',2),
('support','📞 Support','Is support available during the trip?','Yes! Our team is available 24/7 during your trip via WhatsApp and phone. You''ll receive a dedicated trip coordinator''s number before departure who you can reach any time for assistance.',1),
('support','📞 Support','What if something goes wrong during my trip?','We handle all on-trip emergencies — hotel issues, transport breakdowns, medical needs, or itinerary changes. Our local partners and 24/7 support team ensure you''re never stranded. Your satisfaction is our responsibility.',2)
ON CONFLICT DO NOTHING;

INSERT INTO public.job_openings (title, department, department_icon, location, job_type, salary_range, description, sort_order) VALUES
('Senior Full-Stack Developer','Technology','🛠','Delhi / Remote','Full-time','₹18–28 LPA','Build and scale ZoomFly''s booking platform using modern JavaScript frameworks. Work on high-impact features used by thousands daily.',1),
('Senior Travel Consultant','Travel','✈','Delhi / Hybrid','Full-time','₹6–10 LPA','Curate personalised itineraries for high-value clients. Leverage deep destination knowledge to deliver exceptional travel experiences.',2),
('Performance Marketing Manager','Marketing','📣','Delhi','Full-time','₹10–16 LPA','Own acquisition across Google, Meta, and programmatic channels. Drive down CAC while scaling revenue for India''s fastest-growing travel brand.',3),
('UI/UX Product Designer','Design','🎨','Remote','Full-time','₹8–14 LPA','Design intuitive, beautiful travel booking experiences. Own the design system and collaborate closely with engineering on shipping features.',4),
('Customer Experience Lead','Operations','🤝','Delhi','Full-time','₹5–8 LPA','Champion traveller satisfaction. Handle escalations, optimise support flows, and ensure every ZoomFly customer has a 5-star experience.',5),
('Data Analyst — Growth','Data','📊','Delhi / Remote','Full-time','₹8–14 LPA','Turn booking data into actionable insights. Build dashboards, run experiments, and drive growth decisions across product and marketing teams.',6)
ON CONFLICT DO NOTHING;

-- ----------------------------------------------------------------
-- 5. FULL BLOG BODY CONTENT — the seed insert above used short
--    placeholder bodies; these updates replace them with the full,
--    detailed article content that was already live on blog-post.html
--    (extracted programmatically from that file, not retyped, to
--    avoid transcription errors).
-- ----------------------------------------------------------------
-- Auto-generated: replace short placeholder bodies with full article content
UPDATE public.blog_posts SET body = '
      <p>Manali is one of India''s most beloved hill stations — and for good reason. Nestled in the Kullu Valley of Himachal Pradesh at an altitude of 2,050 metres, it offers dramatic mountain scenery, adventure sports, ancient temples, and a culture unlike anywhere else in India.</p>
      <h2>When to Visit Manali</h2>
      <p>The best time to visit Manali depends on what you''re looking for:</p>
      <ul>
        <li><strong>October – February:</strong> Snow season. Ideal if you want snowfall and winter sports. Rohtang Pass is often closed.</li>
        <li><strong>March – June:</strong> Pleasant weather, Rohtang Pass opens. Best overall time. Very popular — book in advance.</li>
        <li><strong>July – September:</strong> Monsoon season. Landslides are common but the valley is lush green. Budget-friendly.</li>
      </ul>
      <div class="tip-box"><p>💡 <strong>Pro Tip:</strong> Book your Manali trip at least 3–4 weeks in advance if you''re going between April–June — hotels fill up fast during peak season.</p></div>
      <h2>Top Things to Do in Manali</h2>
      <h3>1. Rohtang Pass</h3>
      <p>At 13,050 feet, Rohtang Pass is one of the most accessible high-altitude passes in India. You need a permit (arranged by your hotel or taxi), and it''s only open from May to November. The snow views and the drive up are simply breathtaking.</p>
      <h3>2. Solang Valley</h3>
      <p>Just 14 km from Manali, Solang Valley is the adventure hub. In winter, it''s all about skiing and snowboarding. In summer, paragliding, zorbing, and a spectacular ropeway await. Don''t miss the cable car to the top.</p>
      <h3>3. Hadimba Temple</h3>
      <p>This ancient wooden temple dedicated to goddess Hadimba is set in a cedar forest — a stunning contrast of dark timber architecture against the Himalayan backdrop. One of Manali''s most iconic sights.</p>
      <h3>4. Old Manali</h3>
      <p>Cross the Manalsu river bridge and you''re in a different world. Hippie cafes, handicraft shops, colorful streets and a laid-back vibe make Old Manali a must-visit, especially for solo travellers.</p>
      <h3>5. Beas River Rafting</h3>
      <p>For white water thrill seekers, the Beas River offers rafting through grade II–IV rapids depending on the season. Sessions typically run 2–3 hours and go through stunning gorges.</p>
      <h2>Where to Stay</h2>
      <p>Manali has accommodation for every budget. Budget guesthouses start at ₹800/night in Old Manali. Mid-range hotels on Mall Road run ₹2,500–₹5,000. For luxury, try The Himalayan or Span Resort from ₹8,000/night.</p>
      <div class="tip-box"><p>💡 <strong>ZoomFly Tip:</strong> Our Manali Snow Escape package includes handpicked accommodation, sightseeing and transfers starting at just ₹12,499/person. <a href="/pages/package-detail.html?id=manali-snow-escape" style="color:var(--blue);font-weight:600;">Check it out →</a></p></div>
      <h2>How to Get to Manali</h2>
      <p>The nearest airport is Bhuntar (Kullu-Manali Airport), 50 km from town. Volvo overnight buses from Delhi take 12–14 hours and are the most popular option. Private taxis from Delhi cost ₹5,000–₹8,000 one way.</p>
    ', tags = ARRAY['Manali','Himachal Pradesh','Adventure','Mountains','Road Trip'], author = 'Aakash Kumar', read_time = '8 min read' WHERE slug = 'manali-guide';

UPDATE public.blog_posts SET body = '
      <p>Everyone knows about peak-season Goa — crowded beaches, premium prices, and queues everywhere. But here''s the secret that frequent Goa visitors know: the off-season (May to September) is actually one of the best times to visit.</p>
      <h2>Why Off-Season Goa is Brilliant</h2>
      <p>The monsoon transforms Goa into a lush, green, almost unrecognisably beautiful destination. The crowds thin dramatically, prices drop by 40–60%, and you get to experience the real Goa that locals actually love.</p>
      <h3>Massive Price Drops</h3>
      <p>Hotels that charge ₹8,000/night in December often drop to ₹2,500–₹3,500 in July. Flights become significantly cheaper too. You can have a genuinely luxurious Goa experience for a fraction of the peak-season cost.</p>
      <h3>Dramatic Waterfalls</h3>
      <p>Dudhsagar Falls — one of India''s tallest waterfalls — is at its most spectacular during monsoon. The falls transform from a trickle to a roaring cascade that takes your breath away.</p>
      <div class="tip-box"><p>💡 <strong>Note:</strong> Some beach shacks and water sports are closed during monsoon. The vibe is quieter, which many travellers actually prefer.</p></div>
      <h2>What to Do in Monsoon Goa</h2>
      <ul>
        <li>Explore the spice plantations — lush and fragrant in the rains</li>
        <li>Visit Old Goa''s churches — UNESCO heritage sites that are always open</li>
        <li>Enjoy empty beaches with dramatic moody skies</li>
        <li>Eat at local tava restaurants serving fresh Goan seafood</li>
        <li>Visit Dudhsagar Falls before October when it starts to recede</li>
      </ul>
    ', tags = ARRAY['Goa','Monsoon','Budget','Beach','Off-Season'], author = 'Priyanka Singh', read_time = '5 min read' WHERE slug = 'goa-off-season';

UPDATE public.blog_posts SET body = '
      <p>India is one of the most incredible countries to travel on a budget. From ₹1,500-a-day backpacker trips to well-managed ₹5,000-a-day mid-range journeys, it''s possible to have unforgettable experiences without draining your savings.</p>
      <h2>1. Book Trains, Not Flights (for Short Routes)</h2>
      <p>India''s rail network is world-class and incredibly affordable. A Sleeper Class train ticket from Delhi to Jaipur costs under ₹300. Even AC3 tier — with comfortable berths and AC — is a fraction of flight prices.</p>
      <h2>2. Travel in the Off-Season</h2>
      <p>Prices for hotels and packages drop 30–50% outside peak season. Goa in July, Manali in September, Rajasthan in June — all significantly cheaper with fewer tourists.</p>
      <h2>3. Book Package Deals</h2>
      <p>Tour packages often include accommodation, transport and meals at prices cheaper than booking each separately. ZoomFly''s packages are specifically designed to offer maximum value.</p>
      <div class="tip-box"><p>💡 Our Goa Beach Bliss package starts at ₹8,999 — that''s hotel, breakfast, transfers and a North Goa tour included. Try booking that yourself for less!</p></div>
      <h2>4. Eat Where Locals Eat</h2>
      <p>Thali restaurants, Udupi joints, and local dhabas serve delicious, filling meals for ₹80–₹200. These are often tastier than tourist-facing restaurants that charge 5x more.</p>
      <h2>5. Use Government Buses for Long Hauls</h2>
      <p>HRTC (Himachal), KSRTC (Karnataka/Kerala), and MSRTC (Maharashtra) run excellent, affordable bus services. Volvo overnight sleeper options are particularly good value.</p>
      <h2>6. Stay in Hostels for Solo Travel</h2>
      <p>India''s hostel scene has exploded. Backpacker hostels in Manali, Goa, Jaipur and Rishikesh offer dormitory beds from ₹500–₹800/night — often with breakfast included and a great social atmosphere.</p>
    ', tags = ARRAY['Budget','India','Tips','Backpacking','Save Money'], author = 'Rajiv Gupta', read_time = '6 min read' WHERE slug = 'budget-travel';

UPDATE public.blog_posts SET body = '
      <p>Kerala — "God''s Own Country" — is arguably India''s most romantic destination. From misty hill stations and tea gardens to tranquil backwaters and pristine beaches, it offers the perfect backdrop for a honeymoon.</p>
      <h2>The Perfect Kerala Honeymoon Itinerary</h2>
      <p>Most Kerala honeymoon packages span 7 nights and cover 3–4 regions. Here''s the ideal flow:</p>
      <h3>Day 1–2: Kochi</h3>
      <p>Start your honeymoon in the charming port city of Kochi. Explore the historic Fort Kochi area, Chinese Fishing Nets at sunset, the Dutch Palace, and enjoy candlelit dinner by the sea.</p>
      <h3>Day 3–4: Munnar</h3>
      <p>Drive up to the tea capital of South India. The rolling green hills, misty mornings and the fragrance of fresh tea create an impossibly romantic setting. Stay at a tea estate resort for the full experience.</p>
      <h3>Day 5: Alleppey Houseboat</h3>
      <p>The iconic Kerala houseboat experience — your private floating villa on the backwaters. Champagne, fresh seafood and watching the sunset over still waters while a cook prepares your dinner on board.</p>
      <div class="tip-box"><p>💡 <strong>Book in Advance:</strong> Premium houseboats with AC bedrooms and private decks get booked months in advance, especially in October–February. Don''t leave this to last minute.</p></div>
      <h3>Day 6–7: Kovalam Beach</h3>
      <p>End with 2 days at Kovalam''s lighthouse beach. Ayurvedic spa sessions, sunset dinners at clifftop restaurants, and lazy beach walks make for the perfect romantic finale.</p>
      <h2>Best Time for a Kerala Honeymoon</h2>
      <p>October to March is ideal — cool and dry. Monsoon (June–September) is romantic in its own misty way and significantly cheaper, but the houseboat experience is affected by heavy rains.</p>
    ', tags = ARRAY['Kerala','Honeymoon','Backwaters','Romance','Beach'], author = 'Sneha Mehta', read_time = '7 min read' WHERE slug = 'kerala-honeymoon';

UPDATE public.blog_posts SET body = '
      <p>Rajasthan is a year-round destination, but each season offers a dramatically different experience. Here''s the definitive month-by-month guide to help you plan.</p>
      <h2>October – February: Peak Season</h2>
      <p>This is the most popular time and for good reason. Days are pleasantly warm (15–25°C), nights are cool, and the light is perfect for photography. Jaipur''s Diwali celebrations (October–November) are spectacular.</p>
      <p>Expect higher prices and bigger crowds at major attractions. Book accommodation 2–3 months in advance for Jaipur and Jodhpur.</p>
      <h2>March – April: Shoulder Season</h2>
      <p>Temperatures start rising (25–35°C) but it''s still manageable and crowds thin significantly. Prices drop 20–30%. Holi in March is a fantastic time to experience Rajasthan''s festivities. Highly recommended.</p>
      <div class="tip-box"><p>💡 <strong>Best Value Month:</strong> March is our top pick — Holi festival, comfortable weather, reasonable prices and manageable crowds. Our Rajasthan Royal package is especially popular in March.</p></div>
      <h2>May – June: Summer</h2>
      <p>Hot and dry (35–45°C). Not for the faint-hearted, but almost no tourists mean extremely cheap rates and an authentic local experience. Stay indoors midday, explore early morning and evening.</p>
      <h2>July – September: Monsoon</h2>
      <p>Rajasthan is a desert and receives limited rainfall. The landscape turns surprisingly green, the lakes fill up, and Udaipur looks particularly magical during monsoon. Fewer tourists and great prices.</p>
    ', tags = ARRAY['Rajasthan','Best Time','Seasonal','Heritage','Desert'], author = 'Aakash Kumar', read_time = '5 min read' WHERE slug = 'rajasthan-winter';

UPDATE public.blog_posts SET body = '
      <p>Bangkok is overwhelming, exhilarating, and utterly unforgettable. It''s a city of contradictions — ancient temples next to gleaming malls, street food that rivals Michelin-starred restaurants, and a nightlife scene that never sleeps. Here''s everything you need for your first visit.</p>
      <h2>Essential Bangkok Experiences</h2>
      <h3>Grand Palace & Wat Phra Kaew</h3>
      <p>This is non-negotiable for first-timers. The Grand Palace complex is breathtaking — golden spires, intricate mosaics and the famous Emerald Buddha. Go early (8 AM opening) to beat the heat and crowds. Dress code is strict: shoulders and knees covered.</p>
      <h3>Chatuchak Weekend Market</h3>
      <p>One of the world''s largest markets with 15,000 stalls selling everything imaginable. Go on Saturday or Sunday, wear comfortable shoes, bring cash and a sense of adventure. Budget 3–4 hours minimum.</p>
      <h3>Floating Markets</h3>
      <p>Damnoen Saduak is the most famous but heavily touristic. Amphawa is more authentic and especially magical on weekend evenings with fireflies. Day trips are easily arranged from Bangkok.</p>
      <div class="tip-box"><p>💡 <strong>Transport Tip:</strong> Bangkok''s BTS Skytrain and MRT are air-conditioned and cover most tourist areas. Avoid tuk-tuks for long distances — they''re expensive. Use Grab (like Uber) for fair-metered rides.</p></div>
      <h2>Food You Must Try</h2>
      <ul>
        <li><strong>Pad Thai:</strong> The classic — best from street stalls at night markets</li>
        <li><strong>Som Tum:</strong> Green papaya salad, refreshing and spicy</li>
        <li><strong>Mango Sticky Rice:</strong> The best dessert in Southeast Asia</li>
        <li><strong>Tom Yum Goong:</strong> Spicy prawn soup, order from any mid-range restaurant</li>
        <li><strong>Khao Man Gai:</strong> Poached chicken rice — Thais eat it for breakfast</li>
      </ul>
      <h2>Day Trips from Bangkok</h2>
      <p>Pattaya (2 hrs), Ayutthaya ancient capital (1.5 hrs), Kanchanaburi Death Railway (2.5 hrs), and Ko Samet island (3.5 hrs) are all excellent day trip options arranged through any hotel or tour operator.</p>
    ', tags = ARRAY['Bangkok','Thailand','International','First-Timer','Asia'], author = 'Rajiv Gupta', read_time = '9 min read' WHERE slug = 'bangkok-tips';

