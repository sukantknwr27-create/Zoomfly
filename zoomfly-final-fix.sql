-- ============================================================
-- ZoomFly — FINAL FIX SQL (v4)
-- Fixes: guest_email column, RLS recursion, admin user, 
--        testimonials table, packages/hotels seed data
-- Run in: Supabase → SQL Editor → New Query → Run
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. FIX BOOKINGS TABLE — add missing columns if needed
-- ────────────────────────────────────────────────────────────
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS guest_name TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS guest_email TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS guest_phone TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS num_guests INTEGER DEFAULT 1;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS special_requests TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS base_amount NUMERIC;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS discount NUMERIC DEFAULT 0;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS taxes NUMERIC DEFAULT 0;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS total_amount NUMERIC;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'INR';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS payment_method TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'pending';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS razorpay_payment_id TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS booking_ref TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS booking_type TEXT;

-- ────────────────────────────────────────────────────────────
-- 2. FIX VENDORS TABLE
-- ────────────────────────────────────────────────────────────
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS extra_data JSONB DEFAULT '{}';

-- ────────────────────────────────────────────────────────────
-- 3. FIX RLS — infinite recursion on profiles table
-- ────────────────────────────────────────────────────────────
-- Drop ALL existing policies on profiles to clear recursion
DO $$ DECLARE r RECORD;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies WHERE tablename = 'profiles' AND schemaname = 'public'
  LOOP
    EXECUTE 'DROP POLICY IF EXISTS "' || r.policyname || '" ON public.profiles';
  END LOOP;
END $$;

-- Recreate clean non-recursive policies
CREATE POLICY "profiles_read_all"   ON public.profiles FOR SELECT USING (TRUE);
CREATE POLICY "profiles_insert_own" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "profiles_update_own" ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- ────────────────────────────────────────────────────────────
-- 4. FIX ENQUIRIES RLS — allow public insert (contact form)
-- ────────────────────────────────────────────────────────────
DO $$ DECLARE r RECORD;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies WHERE tablename = 'enquiries' AND schemaname = 'public'
  LOOP EXECUTE 'DROP POLICY IF EXISTS "' || r.policyname || '" ON public.enquiries'; END LOOP;
END $$;

CREATE POLICY "enquiries_public_insert" ON public.enquiries FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "enquiries_select" ON public.enquiries FOR SELECT USING (
  guest_email = (SELECT email FROM auth.users WHERE id = auth.uid())
  OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
);
CREATE POLICY "enquiries_admin_update" ON public.enquiries FOR UPDATE USING (
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
);

-- ────────────────────────────────────────────────────────────
-- 5. FIX VENDORS RLS
-- ────────────────────────────────────────────────────────────
DO $$ DECLARE r RECORD;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies WHERE tablename = 'vendors' AND schemaname = 'public'
  LOOP EXECUTE 'DROP POLICY IF EXISTS "' || r.policyname || '" ON public.vendors'; END LOOP;
END $$;

CREATE POLICY "vendors_public_insert" ON public.vendors FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "vendors_select" ON public.vendors FOR SELECT USING (
  user_id = auth.uid()
  OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
);
CREATE POLICY "vendors_admin_all" ON public.vendors FOR ALL USING (
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
);

-- ────────────────────────────────────────────────────────────
-- 6. FIX BOOKINGS RLS — allow guest bookings (no login needed)
-- ────────────────────────────────────────────────────────────
DO $$ DECLARE r RECORD;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies WHERE tablename = 'bookings' AND schemaname = 'public'
  LOOP EXECUTE 'DROP POLICY IF EXISTS "' || r.policyname || '" ON public.bookings'; END LOOP;
END $$;

CREATE POLICY "bookings_public_insert" ON public.bookings FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "bookings_select" ON public.bookings FOR SELECT USING (
  user_id = auth.uid()
  OR guest_email = (SELECT email FROM auth.users WHERE id = auth.uid())
  OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
);
CREATE POLICY "bookings_admin_all" ON public.bookings FOR ALL USING (
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
);

-- ────────────────────────────────────────────────────────────
-- 7. FIX PACKAGES RLS
-- ────────────────────────────────────────────────────────────
DO $$ DECLARE r RECORD;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies WHERE tablename = 'packages' AND schemaname = 'public'
  LOOP EXECUTE 'DROP POLICY IF EXISTS "' || r.policyname || '" ON public.packages'; END LOOP;
END $$;

CREATE POLICY "packages_public_read" ON public.packages FOR SELECT USING (TRUE);
CREATE POLICY "packages_admin_write" ON public.packages FOR ALL USING (
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
);

-- ────────────────────────────────────────────────────────────
-- 8. FIX HOTELS RLS
-- ────────────────────────────────────────────────────────────
DO $$ DECLARE r RECORD;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies WHERE tablename = 'hotels' AND schemaname = 'public'
  LOOP EXECUTE 'DROP POLICY IF EXISTS "' || r.policyname || '" ON public.hotels'; END LOOP;
END $$;

CREATE POLICY "hotels_public_read" ON public.hotels FOR SELECT USING (TRUE);
CREATE POLICY "hotels_admin_write" ON public.hotels FOR ALL USING (
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
);

-- ────────────────────────────────────────────────────────────
-- 9. NEWSLETTER SUBSCRIBERS TABLE
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.newsletter_subscribers (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email      TEXT UNIQUE NOT NULL,
  status     TEXT DEFAULT 'active' CHECK (status IN ('active','unsubscribed')),
  source     TEXT DEFAULT 'website',
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.newsletter_subscribers ENABLE ROW LEVEL SECURITY;

DO $$ DECLARE r RECORD;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies WHERE tablename = 'newsletter_subscribers' AND schemaname = 'public'
  LOOP EXECUTE 'DROP POLICY IF EXISTS "' || r.policyname || '" ON public.newsletter_subscribers'; END LOOP;
END $$;
CREATE POLICY "newsletter_public_insert" ON public.newsletter_subscribers FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "newsletter_admin_read"    ON public.newsletter_subscribers FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
);

-- ────────────────────────────────────────────────────────────
-- 10. TESTIMONIALS TABLE
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.testimonials (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name       TEXT NOT NULL,
  city       TEXT,
  trip       TEXT,
  stars      INTEGER DEFAULT 5 CHECK (stars BETWEEN 1 AND 5),
  text       TEXT NOT NULL,
  avatar     TEXT DEFAULT '#0057FF',
  initials   TEXT,
  is_active  BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.testimonials ENABLE ROW LEVEL SECURITY;

DO $$ DECLARE r RECORD;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies WHERE tablename = 'testimonials' AND schemaname = 'public'
  LOOP EXECUTE 'DROP POLICY IF EXISTS "' || r.policyname || '" ON public.testimonials'; END LOOP;
END $$;
CREATE POLICY "testimonials_public_read" ON public.testimonials FOR SELECT USING (is_active = TRUE);
CREATE POLICY "testimonials_admin_all"   ON public.testimonials FOR ALL USING (
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
);

-- Seed testimonials
INSERT INTO public.testimonials (name, city, trip, stars, text, avatar, initials) VALUES
('Rohit Verma',          'Hyderabad', 'Manali Snow Escape',   5, 'Booked the Manali package — everything was perfect. Hotel, transfers, the Rohtang trip — ZoomFly handled every detail flawlessly.',             '#0057FF', 'RV'),
('Priya & Arjun Singh',  'Mumbai',    'Bali Honeymoon',       5, 'Our Bali honeymoon was an absolute dream. The private villa, couples spa and romantic beach dinner — all arranged perfectly.',                    '#f77062', 'PA'),
('Kavita Nair',          'Bengaluru', 'Kerala Backwaters',    5, 'Incredible value for money. Kerala backwaters on a private houseboat was a bucket-list experience. Team was available on WhatsApp throughout.',    '#43e97b', 'KN'),
('Aditya Sharma',        'Delhi',     'Ladakh Grand Tour',    5, 'Ladakh Grand Tour was life-changing. The permits, camping, jeep safari — flawlessly organised. Will book again for Spiti!',                       '#764ba2', 'AS'),
('Sunita & Rakesh Gupta','Pune',      'Rajasthan Royal Tour', 5, 'Rajasthan package exceeded all expectations. Heritage hotels, camel safari, amazing food — worth every rupee.',                                   '#fa709a', 'SR'),
('Manish Patel',         'Ahmedabad', 'Goa Beach Bliss',      4, 'Great Goa package for our group of 8. All transfers on time, hotel was excellent and the water sports were amazing!',                             '#f6d365', 'MP')
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────
-- 11. PROMO CODES TABLE
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.promo_codes (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  code           TEXT UNIQUE NOT NULL,
  description    TEXT,
  discount_type  TEXT DEFAULT 'percentage' CHECK (discount_type IN ('percentage','fixed')),
  discount_value NUMERIC NOT NULL,
  min_order      NUMERIC DEFAULT 0,
  is_active      BOOLEAN DEFAULT TRUE,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);
INSERT INTO public.promo_codes (code, description, discount_type, discount_value, min_order, is_active) VALUES
  ('ZOOMFLY10', '10% off on all bookings',          'percentage', 10,  5000,  TRUE),
  ('FIRST15',   '15% off for first-time bookers',   'percentage', 15,  5000,  TRUE),
  ('SUMMER500', 'Flat ₹500 off on summer packages', 'fixed',     500, 10000,  TRUE)
ON CONFLICT (code) DO NOTHING;

-- ────────────────────────────────────────────────────────────
-- 12. SEED PACKAGES (with slug)
-- ────────────────────────────────────────────────────────────
INSERT INTO public.packages (slug, title, type, category, emoji, bg_gradient, badge, badge_label, duration_days, nights, price, old_price, rating, review_count, is_active, is_featured, description, inclusions) VALUES
('manali-snow-escape',   'Manali Snow Escape',      'domestic',      'adventure',     '🏔️', 'linear-gradient(135deg,#667eea,#764ba2)', 'bestseller',    'Best Seller',   6, 5, 12499, 14999, 4.9, 312, TRUE, TRUE,  'Snow, adventure & mountain magic in the lap of the Himalayas.',              ARRAY['Hotel Stay','Breakfast & Dinner','Sightseeing','Airport Transfers','Travel Insurance']),
('goa-beach-bliss',      'Goa Beach Bliss',         'domestic',      'beach',         '🏖️', 'linear-gradient(135deg,#f6d365,#fda085)', 'trending',      'Trending',      5, 4,  8999, 10999, 4.8, 541, TRUE, TRUE,  'Sun, sand & sunsets — Goa at its vibrant best.',                            ARRAY['4-Star Hotel','Breakfast','Airport Transfers','North & South Goa Tour','Water Sports Pass']),
('kerala-backwaters',    'Kerala Backwaters',        'domestic',      'nature',        '🌴', 'linear-gradient(135deg,#43e97b,#38f9d7)', 'new',           'New',           7, 6, 15499, 18999, 4.9, 278, TRUE, TRUE,  'God''s Own Country — backwaters, beaches & wildlife.',                      ARRAY['Hotels & Houseboat','All Meals on Houseboat','Sightseeing','Airport Transfers','Kathakali Show']),
('rajasthan-royal-tour', 'Rajasthan Royal Tour',    'domestic',      'heritage',      '🏰', 'linear-gradient(135deg,#fa709a,#fee140)', 'popular',       'Popular',       8, 7, 18999, 22999, 4.7, 189, TRUE, TRUE,  'Forts, palaces & golden deserts of Royal Rajasthan.',                       ARRAY['Heritage Hotels','Breakfast & Dinner','AC Vehicle','Camel Safari','Entrance Fees']),
('bangkok-explorer',     'Bangkok Explorer',        'international', 'international', '🗼', 'linear-gradient(135deg,#4facfe,#00f2fe)', 'international', 'International', 6, 5, 32999, 38999, 4.8, 423, TRUE, TRUE,  'Temples, street food & islands — Bangkok & beyond.',                        ARRAY['4-Star Hotel','Breakfast','Return Flights','Visa Assistance','City Tour','Island Hopping']),
('bali-romance',         'Bali Romance Package',    'international', 'honeymoon',     '🌸', 'linear-gradient(135deg,#a18cd1,#fbc2eb)', 'honeymoon',     'Honeymoon',     7, 6, 55999, 64999, 5.0, 167, TRUE, TRUE,  'Private pool villas, couples spa & Bali magic.',                            ARRAY['Private Pool Villa','All Meals','Return Flights','Airport Transfers','Couples Spa','Sunset Dinner']),
('andaman-island-escape','Andaman Island Escape',   'domestic',      'beach',         '🐠', 'linear-gradient(135deg,#a1c4fd,#c2e9fb)', 'popular',       'Popular',       6, 5, 19999, 24999, 4.8, 203, TRUE, FALSE, 'Crystal-clear waters & coral reefs of the Andamans.',                       ARRAY['Hotel & Resort','Breakfast','Flights from Chennai','Ferry Tickets','Scuba Diving','Glass Bottom Boat']),
('darjeeling-tea-trails','Darjeeling Tea Trails',   'domestic',      'nature',        '🍵', 'linear-gradient(135deg,#43e97b,#38f9d7)', 'new',           'New',           5, 4, 10499, 12999, 4.6, 142, TRUE, FALSE, 'Toy trains, tea gardens & Himalayan sunrises.',                             ARRAY['Boutique Tea Estate Hotel','All Meals','Toy Train Ride','Tea Tasting','Sightseeing']),
('ladakh-grand-tour',    'Ladakh Grand Tour',       'domestic',      'adventure',     '⛰️', 'linear-gradient(135deg,#fccb90,#d57eeb)', 'popular',       'Popular',       9, 8, 24999, 29999, 4.9, 231, TRUE, TRUE,  'Land of High Passes — Pangong Lake, monasteries and Himalayan magic.',      ARRAY['Hotel & Camping','All Meals','Jeep Safari','Monastery Visits','Permits Included']),
('singapore-family-fun', 'Singapore Family Fun',   'international', 'family',        '🦁', 'linear-gradient(135deg,#f6d365,#fda085)', 'family',        'Family',        6, 5, 45999, 52999, 4.7, 389, TRUE, FALSE, 'Universal Studios, Gardens by the Bay & more — perfect for families.',      ARRAY['4-Star Hotel','Breakfast','Return Flights','Universal Studios','Night Safari','Airport Transfers'])
ON CONFLICT (slug) DO NOTHING;

-- ────────────────────────────────────────────────────────────
-- 13. SEED HOTELS (with slug)
-- ────────────────────────────────────────────────────────────
INSERT INTO public.hotels (slug, name, location, city, state, emoji, bg_gradient, type, stars, price_per_night, old_price, badge, badge_label, description, amenities, rating, review_count, rating_label, is_active, is_featured) VALUES
('leela-palace-delhi',       'The Leela Palace',          'Chanakyapuri, New Delhi',         'New Delhi',     'Delhi',           '🏰', 'linear-gradient(135deg,#667eea,#764ba2)', 'hotel',    5, 12500, 15000, 'luxury',    'Luxury Pick', 'An iconic palace hotel with world-class luxury in the heart of New Delhi.',          ARRAY['Pool','Spa','Gym','Restaurant','Bar','WiFi','Parking','Room Service'], 4.9, 2341, 'Exceptional', TRUE, TRUE),
('taj-mahal-palace-mumbai',  'Taj Mahal Palace',          'Apollo Bunder, Colaba',           'Mumbai',        'Maharashtra',     '🏛️', 'linear-gradient(135deg,#f6d365,#fda085)', 'heritage', 5, 18000, 22000, 'heritage',  'Heritage',    'Mumbai''s most iconic hotel, a symbol of Indian hospitality since 1903.',           ARRAY['Pool','Spa','Multiple Restaurants','Bar','WiFi','Parking','Butler Service'], 4.9, 3120, 'Exceptional', TRUE, TRUE),
('kumarakom-lake-resort',    'Kumarakom Lake Resort',     'Kumarakom, Kottayam',             'Kumarakom',     'Kerala',          '🌴', 'linear-gradient(135deg,#43e97b,#38f9d7)', 'resort',   5,  9500, 12000, 'trending',  'Trending',    'A heritage luxury resort on the banks of Vembanad Lake.',                          ARRAY['Pool','Ayurvedic Spa','Restaurant','Yoga','WiFi','Boat Rides','Nature Walks'], 4.8, 1876, 'Excellent', TRUE, TRUE),
('aman-i-khas-ranthambore',  'Aman-i-Khas Ranthambore',  'Near Ranthambore National Park', 'Sawai Madhopur', 'Rajasthan',       '🦁', 'linear-gradient(135deg,#fa709a,#fee140)', 'resort',   5, 45000, 52000, 'exclusive', 'Exclusive',   'Luxury tented camp on the edge of Ranthambore.',                                   ARRAY['Pool','Spa','Safari','Restaurant','Bar','WiFi','Bonfire','Library'], 5.0, 432, 'Exceptional', TRUE, FALSE),
('himalayan-village-manali', 'The Himalayan Village',     'Old Manali Road, Manali',         'Manali',        'Himachal Pradesh','🏔️', 'linear-gradient(135deg,#a1c4fd,#c2e9fb)', 'villa',    4,  4500,  6000, 'new',       'New',         'Charming boutique property in Manali''s pine forests with Himalayan views.',       ARRAY['Restaurant','Bonfire','WiFi','Mountain View','Guided Hikes','Parking'], 4.7, 654, 'Excellent', TRUE, FALSE),
('zostel-goa',               'Zostel Goa',                'Anjuna Beach Road',               'Goa',           'Goa',             '🏖️', 'linear-gradient(135deg,#f093fb,#f5576c)', 'homestay', 3,  1200,  1800, 'budget',    'Budget Pick', 'Popular backpacker hostel steps from Anjuna Beach.',                               ARRAY['WiFi','Common Kitchen','Bar','Bicycle Rental','Tour Desk'], 4.5, 1203, 'Very Good', TRUE, FALSE),
('taj-lake-palace-udaipur',  'Taj Lake Palace',           'Lake Pichola, Udaipur',           'Udaipur',       'Rajasthan',       '🏯', 'linear-gradient(135deg,#ffecd2,#fcb69f)', 'heritage', 5, 28000, 35000, 'iconic',    'Iconic',      'A floating marble palace on Lake Pichola — one of the world''s most romantic hotels.',ARRAY['Pool','Spa','Boat Transfer','Heritage Restaurant','Bar','WiFi','Sundowner Deck'], 5.0, 1876, 'Exceptional', TRUE, TRUE),
('club-mahindra-coorg',      'Club Mahindra Coorg',       'Galibeedu, Madikeri',             'Coorg',         'Karnataka',       '☕', 'linear-gradient(135deg,#134e5e,#71b280)', 'resort',   4,  6500,  8500, 'popular',   'Popular',     'Lush coffee estate resort in the misty hills of Coorg.',                           ARRAY['Pool','Restaurant','Trekking','WiFi','Kids Club','Bonfire','Coffee Estate Tour'], 4.6, 987, 'Excellent', TRUE, FALSE)
ON CONFLICT (slug) DO NOTHING;

-- ────────────────────────────────────────────────────────────
-- 14. SET ADMIN USER
-- Admin email: s.admin  → actual Supabase email used to sign up
-- You MUST sign up at /pages/login.html with email s.admin@zoomfly.in
-- first, then this will grant admin role to that account.
-- ────────────────────────────────────────────────────────────

-- Remove admin from ALL other users first (no other user should be admin)
UPDATE public.profiles SET role = 'user' WHERE role = 'admin';

-- Grant admin to s.admin email
-- IMPORTANT: Replace 's.admin@zoomfly.in' with the EXACT email 
-- you will use to sign up as admin on the login page
UPDATE public.profiles
SET role = 'admin'
WHERE email IN ('s.admin@zoomfly.in', 's.admin', 'casukant0711@gmail.com');

-- Check result
SELECT id, email, role, full_name FROM public.profiles WHERE role = 'admin';
SELECT 'Final fix v4 applied successfully ✅' AS status;
