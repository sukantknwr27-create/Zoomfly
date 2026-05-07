-- ============================================================
-- ZoomFly — Complete Supabase Database Schema
-- Run this in: Supabase Dashboard → SQL Editor → Run
-- ============================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. USERS (extends Supabase auth.users)
-- ============================================================
CREATE TABLE public.profiles (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name       TEXT,
  phone           TEXT,
  avatar_url      TEXT,
  role            TEXT NOT NULL DEFAULT 'customer' CHECK (role IN ('customer','admin','vendor')),
  is_active       BOOLEAN DEFAULT TRUE,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 2. PACKAGES
-- ============================================================
CREATE TABLE public.packages (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title           TEXT NOT NULL,
  slug            TEXT UNIQUE NOT NULL,
  type            TEXT NOT NULL CHECK (type IN ('domestic','international')),
  category        TEXT NOT NULL,
  emoji           TEXT DEFAULT '🗺️',
  bg_gradient     TEXT DEFAULT 'linear-gradient(135deg,#4facfe,#00f2fe)',
  duration_days   INT NOT NULL,
  nights          INT NOT NULL,
  price           NUMERIC(10,2) NOT NULL,
  old_price       NUMERIC(10,2),
  badge           TEXT,
  badge_label     TEXT,
  description     TEXT,
  tags            TEXT[],
  highlights      TEXT[],
  inclusions      TEXT[],
  exclusions      TEXT[],
  itinerary       JSONB,  -- [{day, title, desc}]
  rating          NUMERIC(3,2) DEFAULT 4.5,
  review_count    INT DEFAULT 0,
  is_active       BOOLEAN DEFAULT TRUE,
  is_featured     BOOLEAN DEFAULT FALSE,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 3. HOTELS
-- ============================================================
CREATE TABLE public.hotels (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name            TEXT NOT NULL,
  slug            TEXT UNIQUE NOT NULL,
  location        TEXT NOT NULL,
  city            TEXT NOT NULL,
  state           TEXT,
  emoji           TEXT DEFAULT '🏨',
  bg_gradient     TEXT,
  type            TEXT NOT NULL CHECK (type IN ('hotel','resort','villa','homestay','heritage')),
  stars           INT CHECK (stars BETWEEN 1 AND 5),
  price_per_night NUMERIC(10,2) NOT NULL,
  old_price       NUMERIC(10,2),
  badge           TEXT,
  badge_label     TEXT,
  description     TEXT,
  amenities       TEXT[],
  rating          NUMERIC(3,2) DEFAULT 4.0,
  review_count    INT DEFAULT 0,
  rating_label    TEXT DEFAULT 'Good',
  rooms           JSONB,  -- [{name, info, price}]
  is_active       BOOLEAN DEFAULT TRUE,
  is_featured     BOOLEAN DEFAULT FALSE,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 4. ENQUIRIES
-- ============================================================
CREATE TABLE public.enquiries (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  name            TEXT NOT NULL,
  email           TEXT NOT NULL,
  phone           TEXT NOT NULL,
  interest        TEXT[],
  travel_date     DATE,
  travellers      TEXT,
  budget          TEXT,
  destination     TEXT,
  message         TEXT,
  status          TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new','contacted','confirmed','closed')),
  assigned_to     UUID REFERENCES public.profiles(id),
  notes           TEXT,
  source          TEXT DEFAULT 'website',
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 5. BOOKINGS
-- ============================================================
CREATE TABLE public.bookings (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_ref     TEXT UNIQUE NOT NULL DEFAULT 'ZF-' || UPPER(SUBSTRING(gen_random_uuid()::TEXT FROM 1 FOR 6)),
  user_id         UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  -- What was booked
  booking_type    TEXT NOT NULL CHECK (booking_type IN ('package','hotel','flight','bus')),
  package_id      UUID REFERENCES public.packages(id),
  hotel_id        UUID REFERENCES public.hotels(id),
  -- Guest details
  guest_name      TEXT NOT NULL,
  guest_email     TEXT NOT NULL,
  guest_phone     TEXT NOT NULL,
  -- Trip details
  checkin_date    DATE,
  checkout_date   DATE,
  travel_date     DATE,
  num_guests      INT DEFAULT 1,
  num_rooms       INT DEFAULT 1,
  room_type       TEXT,
  special_requests TEXT,
  -- Pricing
  base_amount     NUMERIC(10,2) NOT NULL,
  discount        NUMERIC(10,2) DEFAULT 0,
  taxes           NUMERIC(10,2) DEFAULT 0,
  total_amount    NUMERIC(10,2) NOT NULL,
  currency        TEXT DEFAULT 'INR',
  -- Payment
  payment_status  TEXT DEFAULT 'pending' CHECK (payment_status IN ('pending','partial','paid','refunded','failed')),
  payment_method  TEXT,
  razorpay_order_id   TEXT,
  razorpay_payment_id TEXT,
  razorpay_signature  TEXT,
  paid_amount     NUMERIC(10,2) DEFAULT 0,
  paid_at         TIMESTAMPTZ,
  -- Status
  status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','confirmed','cancelled','completed')),
  cancelled_at    TIMESTAMPTZ,
  cancel_reason   TEXT,
  confirmed_at    TIMESTAMPTZ,
  -- Meta
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 6. PAYMENTS
-- ============================================================
CREATE TABLE public.payments (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id          UUID REFERENCES public.bookings(id) ON DELETE CASCADE,
  user_id             UUID REFERENCES public.profiles(id),
  razorpay_order_id   TEXT NOT NULL,
  razorpay_payment_id TEXT,
  razorpay_signature  TEXT,
  amount              NUMERIC(10,2) NOT NULL,
  currency            TEXT DEFAULT 'INR',
  status              TEXT DEFAULT 'created' CHECK (status IN ('created','authorized','captured','refunded','failed')),
  method              TEXT,
  webhook_payload     JSONB,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 7. VENDORS
-- ============================================================
CREATE TABLE public.vendors (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID REFERENCES public.profiles(id),
  business_name   TEXT NOT NULL,
  business_type   TEXT NOT NULL CHECK (business_type IN ('Hotel','Bus','Tour','Cab','Activity')),
  owner_name      TEXT NOT NULL,
  email           TEXT NOT NULL,
  phone           TEXT NOT NULL,
  city            TEXT NOT NULL,
  gstin           TEXT,
  capacity        TEXT,
  description     TEXT,
  bank_account    TEXT,
  bank_ifsc       TEXT,
  bank_name       TEXT,
  commission_rate NUMERIC(5,2) DEFAULT 12.00,
  status          TEXT DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','suspended')),
  verified_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 8. REVIEWS
-- ============================================================
CREATE TABLE public.reviews (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  booking_id      UUID REFERENCES public.bookings(id),
  package_id      UUID REFERENCES public.packages(id),
  hotel_id        UUID REFERENCES public.hotels(id),
  rating          INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  title           TEXT,
  body            TEXT,
  is_verified     BOOLEAN DEFAULT FALSE,
  is_published    BOOLEAN DEFAULT TRUE,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 9. WISHLIST
-- ============================================================
CREATE TABLE public.wishlists (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  package_id  UUID REFERENCES public.packages(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, package_id)
);

-- ============================================================
-- 10. PROMO CODES
-- ============================================================
CREATE TABLE public.promo_codes (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  code            TEXT UNIQUE NOT NULL,
  description     TEXT,
  discount_type   TEXT CHECK (discount_type IN ('percentage','fixed')),
  discount_value  NUMERIC(10,2) NOT NULL,
  min_order       NUMERIC(10,2) DEFAULT 0,
  max_discount    NUMERIC(10,2),
  usage_limit     INT,
  used_count      INT DEFAULT 0,
  valid_from      DATE DEFAULT CURRENT_DATE,
  valid_until     DATE,
  is_active       BOOLEAN DEFAULT TRUE,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- INDEXES (performance)
-- ============================================================
CREATE INDEX idx_bookings_user ON public.bookings(user_id);
CREATE INDEX idx_bookings_status ON public.bookings(status);
CREATE INDEX idx_bookings_ref ON public.bookings(booking_ref);
CREATE INDEX idx_enquiries_status ON public.enquiries(status);
CREATE INDEX idx_enquiries_email ON public.enquiries(email);
CREATE INDEX idx_packages_active ON public.packages(is_active);
CREATE INDEX idx_packages_type ON public.packages(type);
CREATE INDEX idx_hotels_city ON public.hotels(city);
CREATE INDEX idx_reviews_package ON public.reviews(package_id);
CREATE INDEX idx_wishlists_user ON public.wishlists(user_id);

-- ============================================================
-- TRIGGERS — auto update updated_at
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_profiles_updated    BEFORE UPDATE ON public.profiles    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_packages_updated    BEFORE UPDATE ON public.packages    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_hotels_updated      BEFORE UPDATE ON public.hotels      FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_bookings_updated    BEFORE UPDATE ON public.bookings    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_enquiries_updated   BEFORE UPDATE ON public.enquiries   FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_vendors_updated     BEFORE UPDATE ON public.vendors     FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- TRIGGER — auto create profile when user signs up
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (NEW.id, NEW.raw_user_meta_data->>'full_name', 
          COALESCE(NEW.raw_user_meta_data->>'role', 'customer'));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- TRIGGER — update package rating when review added
CREATE OR REPLACE FUNCTION update_package_rating()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.packages SET
    rating = (SELECT ROUND(AVG(rating)::NUMERIC, 2) FROM public.reviews WHERE package_id = NEW.package_id AND is_published = TRUE),
    review_count = (SELECT COUNT(*) FROM public.reviews WHERE package_id = NEW.package_id AND is_published = TRUE)
  WHERE id = NEW.package_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_package_rating AFTER INSERT OR UPDATE ON public.reviews FOR EACH ROW EXECUTE FUNCTION update_package_rating();

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================
ALTER TABLE public.profiles    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookings    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enquiries   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wishlists   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.packages    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hotels      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendors     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promo_codes ENABLE ROW LEVEL SECURITY;

-- PROFILES
CREATE POLICY "Users can view own profile"   ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Admins can view all profiles" ON public.profiles FOR SELECT USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

-- PACKAGES (public read, admin write)
CREATE POLICY "Packages are public"          ON public.packages FOR SELECT USING (is_active = TRUE);
CREATE POLICY "Admins manage packages"       ON public.packages FOR ALL USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

-- HOTELS (public read, admin write)
CREATE POLICY "Hotels are public"            ON public.hotels FOR SELECT USING (is_active = TRUE);
CREATE POLICY "Admins manage hotels"         ON public.hotels FOR ALL USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

-- BOOKINGS
CREATE POLICY "Users view own bookings"      ON public.bookings FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Users create bookings"        ON public.bookings FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "Admins view all bookings"     ON public.bookings FOR ALL USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

-- ENQUIRIES
CREATE POLICY "Anyone can create enquiry"    ON public.enquiries FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "Users view own enquiries"     ON public.enquiries FOR SELECT USING (email = (SELECT email FROM auth.users WHERE id = auth.uid()));
CREATE POLICY "Admins manage enquiries"      ON public.enquiries FOR ALL USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

-- WISHLISTS
CREATE POLICY "Users manage own wishlist"    ON public.wishlists FOR ALL USING (user_id = auth.uid());

-- REVIEWS
CREATE POLICY "Reviews are public"           ON public.reviews FOR SELECT USING (is_published = TRUE);
CREATE POLICY "Users create reviews"         ON public.reviews FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "Admins manage reviews"        ON public.reviews FOR ALL USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

-- VENDORS
CREATE POLICY "Vendors view own record"      ON public.vendors FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Anyone can apply as vendor"   ON public.vendors FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "Admins manage vendors"        ON public.vendors FOR ALL USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

-- PROMO CODES (public read of active codes)
CREATE POLICY "Active promo codes are readable" ON public.promo_codes FOR SELECT USING (is_active = TRUE);
CREATE POLICY "Admins manage promo codes"    ON public.promo_codes FOR ALL USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

-- ============================================================
-- SEED DATA — Insert default promo code
-- ============================================================
INSERT INTO public.promo_codes (code, description, discount_type, discount_value, min_order, valid_until, is_active)
VALUES ('ZOOMFLY10', '10% off all packages', 'percentage', 10, 5000, '2025-12-31', TRUE);

-- ============================================================
-- SEED DATA — Sample packages (6)
-- ============================================================
INSERT INTO public.packages (title, slug, type, category, emoji, bg_gradient, duration_days, nights, price, old_price, badge, badge_label, description, tags, highlights, inclusions, exclusions, itinerary, rating, review_count, is_active, is_featured) VALUES
('Manali Snow Escape', 'manali-snow-escape', 'domestic', 'adventure', '🏔️', 'linear-gradient(135deg,#4facfe,#00f2fe)', 5, 4, 12499, 15000, 'bestseller', 'Best Seller', 'Experience the magic of Manali — snow-capped peaks, Rohtang Pass, Solang Valley & cosy mountain stays.', ARRAY['Adventure','Snow','Mountains'], ARRAY['4N/5D','Flights incl.','Hotel + Meals'], ARRAY['Return flights from Delhi','4-star hotel (4 nights)','Daily breakfast & dinner','Rohtang Pass day trip','Solang Valley visit','Airport transfers'], ARRAY['Personal expenses','Skiing charges','Travel insurance'], '[{"day":"Day 1","title":"Arrive Manali","desc":"Pick-up from airport, check-in, welcome dinner."},{"day":"Day 2","title":"Rohtang Pass","desc":"Full-day excursion to Rohtang Pass, snow activities."},{"day":"Day 3","title":"Solang Valley","desc":"Zorbing, paragliding, cable car ride."},{"day":"Day 4","title":"Old Manali","desc":"Hadimba Temple, riverside cafes, Mall Road shopping."},{"day":"Day 5","title":"Departure","desc":"Breakfast, check-out, drop to airport."}]', 4.9, 342, TRUE, TRUE),

('Goa Beach Bliss', 'goa-beach-bliss', 'domestic', 'beach', '🏖️', 'linear-gradient(135deg,#f093fb,#f5576c)', 4, 3, 8999, 11000, 'trending', 'Trending', 'Sun, sand, and seafood. Explore North & South Goa beaches, heritage churches, and vibrant nightlife.', ARRAY['Beach','Party','Heritage'], ARRAY['3N/4D','Beach resort','Breakfast incl.'], ARRAY['3-star beach resort (3 nights)','Daily breakfast','North & South Goa tour','Water sports session','Airport transfers','Welcome drink'], ARRAY['Flights','Lunch & dinner','Personal expenses','Alcohol'], '[{"day":"Day 1","title":"Arrive & Unwind","desc":"Check-in, welcome drink, evening at Baga Beach."},{"day":"Day 2","title":"North Goa Tour","desc":"Calangute, Anjuna, Chapora Fort, Vagator Beach."},{"day":"Day 3","title":"South Goa & Water Sports","desc":"Colva Beach, Basilica of Bom Jesus, water sports."},{"day":"Day 4","title":"Departure","desc":"Morning leisure, check-out, airport drop."}]', 4.8, 589, TRUE, TRUE),

('Kerala Backwaters', 'kerala-backwaters', 'domestic', 'nature', '🌴', 'linear-gradient(135deg,#43e97b,#38f9d7)', 6, 5, 15499, 18000, 'new', 'New', 'Glide through Kerala''s legendary backwaters on a private houseboat, explore spice plantations & Ayurvedic retreats.', ARRAY['Nature','Houseboat','Ayurveda'], ARRAY['5N/6D','Houseboat stay','All meals incl.'], ARRAY['Private houseboat (1 night)','Resort stays (4 nights)','All meals','Alleppey cruise','Munnar tea estate tour','Ayurvedic massage','All transfers'], ARRAY['Flights','Personal shopping','Travel insurance'], '[{"day":"Day 1","title":"Arrive Kochi","desc":"Fort Kochi, Chinese fishing nets, Kathakali show."},{"day":"Day 2","title":"Munnar","desc":"Tea estates, Mattupetty Dam, Echo Point."},{"day":"Day 3","title":"Thekkady","desc":"Periyar Wildlife Sanctuary, spice garden."},{"day":"Day 4","title":"Alleppey Houseboat","desc":"Board private houseboat, backwater cruise, dinner on water."},{"day":"Day 5","title":"Kovalam Beach","desc":"Ayurvedic massage, lighthouse beach sunset."},{"day":"Day 6","title":"Departure","desc":"Transfer to Thiruvananthapuram airport."}]', 4.9, 278, TRUE, TRUE),

('Bali Honeymoon Special', 'bali-honeymoon', 'international', 'honeymoon', '💑', 'linear-gradient(135deg,#f77062,#fe5196)', 7, 6, 54999, 68000, 'bestseller', 'Best Seller', 'Romance in paradise. Private villa, Ubud rice terraces, Tanah Lot sunset & couples spa in magical Bali.', ARRAY['Honeymoon','International','Luxury'], ARRAY['6N/7D','Private villa','Couples spa'], ARRAY['Private pool villa (6N)','Return flights from Delhi','Daily breakfast','Tanah Lot sunset','Ubud rice terraces','Couples spa (60 min)','Romantic beach dinner','Airport transfers'], ARRAY['Visa fees (~₹2,500)','Travel insurance','Personal expenses'], '[{"day":"Day 1","title":"Arrive Bali","desc":"Transfer to villa, welcome drink, romantic turndown."},{"day":"Day 2","title":"Ubud","desc":"Monkey Forest, rice terraces, Tirta Empul temple."},{"day":"Day 3","title":"Spa & Leisure","desc":"Couples spa, rooftop pool, sunset at Uluwatu."},{"day":"Day 4","title":"Tanah Lot","desc":"Sunset temple photography, beach dinner."},{"day":"Day 5","title":"Seminyak","desc":"Beach club, shopping, sunset cocktails."},{"day":"Day 6","title":"Nusa Penida","desc":"Kelingking Beach, Crystal Bay snorkelling."},{"day":"Day 7","title":"Departure","desc":"Leisure morning, check-out, airport transfer."}]', 4.9, 421, TRUE, TRUE),

('Rajasthan Royal Trail', 'rajasthan-royal-trail', 'domestic', 'heritage', '🏰', 'linear-gradient(135deg,#fa709a,#fee140)', 8, 7, 22999, 28000, 'bestseller', 'Best Seller', 'Live like royalty. Forts and palaces of Jaipur, Jodhpur & Udaipur with heritage hotel stays.', ARRAY['Heritage','Forts','Royal'], ARRAY['7N/8D','Heritage hotels','Camel safari'], ARRAY['Heritage hotels (7 nights)','Daily breakfast','Jaipur city tour','Jodhpur fort visit','Udaipur lake cruise','Camel safari','All AC transfers','Local guide'], ARRAY['Flights','Lunch & dinner','Monument entry fees'], '[{"day":"Day 1-2","title":"Jaipur","desc":"Amber Fort, Hawa Mahal, City Palace, Jantar Mantar."},{"day":"Day 3-4","title":"Jodhpur","desc":"Mehrangarh Fort, Jaswant Thada, old city bazaars."},{"day":"Day 5","title":"Jaisalmer","desc":"Sand dunes, camel safari, desert camp overnight."},{"day":"Day 6-7","title":"Udaipur","desc":"Lake Pichola cruise, City Palace, Saheliyon-ki-Bari."},{"day":"Day 8","title":"Departure","desc":"Transfer to Udaipur airport."}]', 4.8, 195, TRUE, TRUE),

('Andaman Paradise', 'andaman-paradise', 'domestic', 'beach', '🌊', 'linear-gradient(135deg,#0093E9,#80D0C7)', 6, 5, 24999, 30000, 'trending', 'Trending', 'Crystal-clear waters, white sand beaches & world-class snorkelling at Havelock and Neil Island.', ARRAY['Beach','Scuba','Islands'], ARRAY['5N/6D','Inter-island ferry','Snorkelling incl.'], ARRAY['Resorts (5 nights)','Inter-island ferry tickets','Radhanagar beach','Snorkelling session','Cellular Jail light show','All transfers'], ARRAY['Flights to Port Blair','Scuba diving (optional)','Meals except breakfast'], '[{"day":"Day 1","title":"Arrive Port Blair","desc":"Cellular Jail, sound & light show."},{"day":"Day 2","title":"North Bay & Ross Island","desc":"Glass-bottom boat, snorkelling."},{"day":"Day 3-4","title":"Havelock Island","desc":"Radhanagar Beach, Elephant Beach snorkelling."},{"day":"Day 5","title":"Neil Island","desc":"Natural Bridge, Bharatpur beach."},{"day":"Day 6","title":"Departure","desc":"Return to Port Blair, fly home."}]', 4.9, 312, TRUE, TRUE);

COMMENT ON TABLE public.profiles  IS 'Extended user profiles linked to Supabase auth';
COMMENT ON TABLE public.bookings  IS 'All customer bookings with payment and status tracking';
COMMENT ON TABLE public.enquiries IS 'Contact form and quote enquiries from customers';
COMMENT ON TABLE public.vendors   IS 'Partner/vendor registrations and their approval status';

-- ============================================================
-- NEWSLETTER SUBSCRIBERS TABLE
-- ============================================================
CREATE TABLE public.newsletter_subscribers (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email      TEXT UNIQUE NOT NULL,
  status     TEXT DEFAULT 'active' CHECK (status IN ('active','unsubscribed')),
  source     TEXT DEFAULT 'website',
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.newsletter_subscribers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can read subscribers" ON public.newsletter_subscribers FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
);
CREATE POLICY "Anyone can subscribe" ON public.newsletter_subscribers FOR INSERT WITH CHECK (TRUE);

-- Promo code for new users
INSERT INTO public.promo_codes (code, description, discount_type, discount_value, min_order, is_active)
VALUES ('FIRST15', '15% off for first-time bookers', 'percentage', 15, 5000, TRUE)
ON CONFLICT DO NOTHING;
