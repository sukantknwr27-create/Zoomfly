-- ================================================================
-- ZoomFly — 08_zoomfly_content_migration.sql
-- Run AFTER 00–07.
--
-- WHAT THIS FIXES (#6, #7, #8 — "existing destinations/bus routes/
-- cab services on the website aren't showing in the admin panel"):
--
-- The admin panel's Destinations / Bus Routes / Cab Services tables
-- were never actually empty by mistake — they're empty because the
-- content you see on the live site (destinations.html, bus.html,
-- cabs.html) is still hardcoded directly into those pages' HTML/JS,
-- and was never connected to these database tables at all. Two
-- separate, disconnected systems.
--
-- This migration:
--   1. Extends `destinations` with the extra fields the live page
--      actually needs (state, tagline, type, categories, tags,
--      starting price, best time to visit, description) that the
--      original bare-bones table didn't have.
--   2. Adds uniqueness constraints so this script — and any future
--      re-run — is idempotent, matching the rest of the migrations.
--   3. Seeds all 23 destinations, 6 bus routes, and 9 cab routes
--      currently hardcoded on the live site into their proper tables,
--      so they show up in the admin panel and become editable there.
--
-- A companion frontend change (destinations.html, bus.html, cabs.html)
-- now reads from these tables instead of the hardcoded arrays, with
-- the old hardcoded content kept as an automatic fallback ONLY if the
-- database returns zero rows — so nothing breaks if you haven't run
-- this migration yet, and nothing breaks if you run it twice.
-- ================================================================

-- ----------------------------------------------------------------
-- 1. SCHEMA: extra destination fields
-- ----------------------------------------------------------------
ALTER TABLE public.destinations ADD COLUMN IF NOT EXISTS state       TEXT;
ALTER TABLE public.destinations ADD COLUMN IF NOT EXISTS tagline     TEXT;
ALTER TABLE public.destinations ADD COLUMN IF NOT EXISTS dest_type   TEXT DEFAULT 'domestic' CHECK (dest_type IN ('domestic','international'));
ALTER TABLE public.destinations ADD COLUMN IF NOT EXISTS categories  TEXT[] DEFAULT '{}';
ALTER TABLE public.destinations ADD COLUMN IF NOT EXISTS tags        TEXT[] DEFAULT '{}';
ALTER TABLE public.destinations ADD COLUMN IF NOT EXISTS from_price  NUMERIC(10,2) DEFAULT 0;
ALTER TABLE public.destinations ADD COLUMN IF NOT EXISTS best_time   TEXT;
ALTER TABLE public.destinations ADD COLUMN IF NOT EXISTS description TEXT;

-- Idempotency: without a uniqueness constraint, ON CONFLICT below has
-- nothing to key off of and re-running this file would duplicate rows.
-- Wrapped so re-running this file doesn't error on "constraint already exists".
DO $$ BEGIN
  ALTER TABLE public.destinations ADD CONSTRAINT destinations_name_key UNIQUE (name);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE public.bus_routes ADD CONSTRAINT bus_routes_route_key UNIQUE (from_city, to_city, bus_type);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE public.cab_services ADD CONSTRAINT cab_services_route_key UNIQUE (from_location, to_location, cab_type);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ----------------------------------------------------------------
-- 2. SEED DATA — migrated verbatim from the live pages' hardcoded
--    content (destinations.html, bus.html, cabs.html)
-- ----------------------------------------------------------------

-- DESTINATIONS

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Goa', 'India', 'Goa', 'Sun, Sand & Sunsets', '🏖️', 'linear-gradient(135deg,#f6d365,#fda085)', 'domestic', ARRAY['beach','party','nature']::text[], ARRAY['Beach','Nightlife','Water Sports','Churches']::text[], 6999, 'Oct–Mar', 'India''s most loved beach destination with golden sands, lively shacks, colonial heritage and year-round sunshine.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Andaman Islands', 'India', 'Andaman & Nicobar', 'Crystal Blue Waters', '🐠', 'linear-gradient(135deg,#a1c4fd,#c2e9fb)', 'domestic', ARRAY['beach','adventure','nature']::text[], ARRAY['Beaches','Scuba Diving','Snorkelling','Cellular Jail']::text[], 14999, 'Nov–Apr', 'Paradise islands with pristine beaches, turquoise waters and some of India''s best scuba diving.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Lakshadweep', 'India', 'Lakshadweep', 'Coral Island Paradise', '🐚', 'linear-gradient(135deg,#43e97b,#38f9d7)', 'domestic', ARRAY['beach','honeymoon']::text[], ARRAY['Coral Reefs','Snorkelling','Kayaking','Isolated']::text[], 22999, 'Oct–May', 'Untouched coral islands with lagoons, white sand beaches and incredible marine biodiversity.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Manali', 'India', 'Himachal Pradesh', 'Mountains & Adventure', '🏔️', 'linear-gradient(135deg,#667eea,#764ba2)', 'domestic', ARRAY['mountains','adventure','honeymoon']::text[], ARRAY['Snow','Skiing','Trekking','Rohtang Pass']::text[], 10499, 'Oct–Jun', 'A high-altitude Himalayan resort town offering snow sports, adventure activities and scenic mountain beauty.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Shimla', 'India', 'Himachal Pradesh', 'Queen of Hills', '🏘️', 'linear-gradient(135deg,#4facfe,#00f2fe)', 'domestic', ARRAY['mountains','heritage']::text[], ARRAY['Colonial Heritage','Toy Train','Mall Road','Scenic']::text[], 7999, 'Mar–Jun, Oct–Dec', 'Former summer capital of British India, with colonial architecture, scenic hills and the famous toy train.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Darjeeling', 'India', 'West Bengal', 'Tea Gardens & Peaks', '🍵', 'linear-gradient(135deg,#43e97b,#38f9d7)', 'domestic', ARRAY['mountains','nature']::text[], ARRAY['Tea Gardens','Toy Train','Sunrise','Kanchenjunga']::text[], 8499, 'Mar–May, Oct–Dec', 'Charming hill station famous for its tea estates, UNESCO toy train and views of Kanchenjunga.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Spiti Valley', 'India', 'Himachal Pradesh', 'Cold Desert Magic', '🏜️', 'linear-gradient(135deg,#89f7fe,#66a6ff)', 'domestic', ARRAY['mountains','adventure']::text[], ARRAY['Monasteries','High Altitude','Trekking','Off-Beat']::text[], 12999, 'Jun–Oct', 'Remote high-altitude desert valley with ancient monasteries, barren landscapes and rare wildlife.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Ladakh', 'India', 'Ladakh (UT)', 'Land of High Passes', '⛰️', 'linear-gradient(135deg,#fccb90,#d57eeb)', 'domestic', ARRAY['mountains','adventure','spiritual']::text[], ARRAY['Pangong Lake','Monasteries','Bike Trip','Scenic']::text[], 16999, 'Jun–Sep', 'India''s crown jewel — moonscapes, mirror lakes, Buddhist monasteries and legendary mountain passes.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Rajasthan', 'India', 'Rajasthan', 'Royal Heritage', '🏰', 'linear-gradient(135deg,#fa709a,#fee140)', 'domestic', ARRAY['heritage','culture','desert']::text[], ARRAY['Forts','Palaces','Camel Safari','Desert']::text[], 12999, 'Oct–Mar', 'The royal state of India — golden forts, blue cities, pink cities and camel safaris under starlit skies.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Varanasi', 'India', 'Uttar Pradesh', 'Spiritual Capital', '🪔', 'linear-gradient(135deg,#f7971e,#ffd200)', 'domestic', ARRAY['spiritual','heritage']::text[], ARRAY['Ganges','Ghats','Temples','Aarti']::text[], 5999, 'Oct–Mar', 'One of the world''s oldest living cities — Ganga ghats, ancient temples and the most sacred spiritual experience in India.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Hampi', 'India', 'Karnataka', 'Ancient Ruins', '🗿', 'linear-gradient(135deg,#c94b4b,#4b134f)', 'domestic', ARRAY['heritage','adventure']::text[], ARRAY['UNESCO Site','Ruins','Bouldering','History']::text[], 6999, 'Oct–Feb', 'UNESCO World Heritage Site — magnificent ruins of the Vijayanagara Empire scattered across a surreal boulder landscape.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Kerala', 'India', 'Kerala', 'God''s Own Country', '🌴', 'linear-gradient(135deg,#56ab2f,#a8e063)', 'domestic', ARRAY['nature','beach','honeymoon','backwaters']::text[], ARRAY['Backwaters','Houseboat','Spices','Beaches']::text[], 9999, 'Sep–Mar', 'Tranquil backwaters, lush hills, Ayurvedic spas and palm-lined beaches — Kerala is India''s most serene state.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Coorg', 'India', 'Karnataka', 'Scotland of India', '☕', 'linear-gradient(135deg,#134e5e,#71b280)', 'domestic', ARRAY['nature','honeymoon']::text[], ARRAY['Coffee Estates','Waterfalls','Trekking','Misty Hills']::text[], 7999, 'Oct–May', 'Misty mountains, aromatic coffee estates and roaring waterfalls — Coorg is Karnataka''s most charming hill station.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Ranthambore', 'India', 'Rajasthan', 'Tiger Land', '🐯', 'linear-gradient(135deg,#d4680a,#f7971e)', 'domestic', ARRAY['wildlife','heritage']::text[], ARRAY['Tiger Safari','Wildlife','Fort','Jungle']::text[], 8999, 'Oct–Jun', 'Home to Royal Bengal Tigers and an ancient fort — Ranthambore is India''s most exciting wildlife destination.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Bangkok & Pattaya', 'Thailand', NULL, 'Temples & Nightlife', '🗼', 'linear-gradient(135deg,#4facfe,#00f2fe)', 'international', ARRAY['culture','beach','party']::text[], ARRAY['Temples','Street Food','Nightlife','Shopping']::text[], 28999, 'Nov–Apr', 'Vibrant capital with golden temples, floating markets, amazing street food and buzzing nightlife.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Bali', 'Indonesia', NULL, 'Island of Gods', '🌸', 'linear-gradient(135deg,#a18cd1,#fbc2eb)', 'international', ARRAY['beach','honeymoon','culture']::text[], ARRAY['Rice Terraces','Temples','Surfing','Spa']::text[], 42999, 'Apr–Oct', 'Spiritual island paradise with terraced rice fields, ancient temples, world-class surfing and romantic sunsets.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Singapore', 'Singapore', NULL, 'Lion City', '🦁', 'linear-gradient(135deg,#f6d365,#fda085)', 'international', ARRAY['city','family']::text[], ARRAY['Universal Studios','Marina Bay','Shopping','Gardens']::text[], 38999, 'Year Round', 'Ultra-modern city-state with iconic skylines, diverse cuisine, amazing theme parks and world-class shopping.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Dubai', 'UAE', NULL, 'City of Gold', '🌇', 'linear-gradient(135deg,#ffecd2,#fcb69f)', 'international', ARRAY['city','luxury','adventure']::text[], ARRAY['Burj Khalifa','Desert Safari','Shopping','Gold Souk']::text[], 45999, 'Nov–Apr', 'Futuristic city of superlatives — tallest buildings, luxury malls, gold souks and thrilling desert safaris.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Maldives', 'Maldives', NULL, 'Paradise on Earth', '🏝️', 'linear-gradient(135deg,#00c6fb,#005bea)', 'international', ARRAY['beach','honeymoon','luxury']::text[], ARRAY['Overwater Villas','Snorkelling','Luxury','Seclusion']::text[], 79999, 'Nov–Apr', 'The ultimate luxury tropical escape — overwater villas, crystal lagoons and some of the world''s best coral reefs.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Nepal', 'Nepal', NULL, 'Roof of the World', '🏔️', 'linear-gradient(135deg,#8e44ad,#3498db)', 'international', ARRAY['mountains','adventure','spiritual']::text[], ARRAY['Everest','Trekking','Temples','Pokhara']::text[], 18999, 'Mar–May, Oct–Nov', 'Home to eight of the world''s ten highest peaks, ancient temples, friendly people and legendary trekking trails.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Sri Lanka', 'Sri Lanka', NULL, 'Pearl of Indian Ocean', '🌿', 'linear-gradient(135deg,#2af598,#009efd)', 'international', ARRAY['nature','heritage','beach']::text[], ARRAY['Tea Estates','Temples','Wildlife','Beaches']::text[], 24999, 'Dec–Mar', 'Compact island with ancient cities, misty tea hills, elephant-filled national parks and palm-fringed beaches.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Europe Multi-City', 'Multiple', NULL, 'Castles & Culture', '🏰', 'linear-gradient(135deg,#b8cbb8,#b8a4c9)', 'international', ARRAY['heritage','culture','city']::text[], ARRAY['Paris','Rome','Amsterdam','Scenic Rail']::text[], 149999, 'Apr–Oct', 'Iconic cities of Europe — the Eiffel Tower, Colosseum, canals of Amsterdam and Swiss Alps on one grand tour.', TRUE)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.destinations (name, country, state, tagline, emoji, bg_gradient, dest_type, categories, tags, from_price, best_time, description, is_active)
VALUES ('Japan', 'Japan', NULL, 'Land of Rising Sun', '🌸', 'linear-gradient(135deg,#f7971e,#ffd200)', 'international', ARRAY['culture','nature','city']::text[], ARRAY['Cherry Blossoms','Temples','Mt. Fuji','Bullet Train']::text[], 95999, 'Mar–May, Oct–Nov', 'Ancient traditions meet futuristic cities — cherry blossoms, samurai history, sushi, Mt. Fuji and bullet trains.', TRUE)
ON CONFLICT (name) DO NOTHING;



-- BUS ROUTES

INSERT INTO public.bus_routes (from_city, to_city, operator, bus_type, price, duration, is_active)
VALUES ('Delhi', 'Manali', 'ZoomFly Partner', 'Volvo AC Sleeper', 799, '14 hrs', TRUE)
ON CONFLICT (from_city, to_city, bus_type) DO NOTHING;

INSERT INTO public.bus_routes (from_city, to_city, operator, bus_type, price, duration, is_active)
VALUES ('Mumbai', 'Goa', 'ZoomFly Partner', 'AC Sleeper', 650, '9 hrs', TRUE)
ON CONFLICT (from_city, to_city, bus_type) DO NOTHING;

INSERT INTO public.bus_routes (from_city, to_city, operator, bus_type, price, duration, is_active)
VALUES ('Bangalore', 'Mysore', 'ZoomFly Partner', 'AC Seater', 220, '3 hrs', TRUE)
ON CONFLICT (from_city, to_city, bus_type) DO NOTHING;

INSERT INTO public.bus_routes (from_city, to_city, operator, bus_type, price, duration, is_active)
VALUES ('Delhi', 'Jaipur', 'ZoomFly Partner', 'Volvo AC Seater', 349, '5 hrs', TRUE)
ON CONFLICT (from_city, to_city, bus_type) DO NOTHING;

INSERT INTO public.bus_routes (from_city, to_city, operator, bus_type, price, duration, is_active)
VALUES ('Chennai', 'Coimbatore', 'ZoomFly Partner', 'AC Sleeper', 450, '7 hrs', TRUE)
ON CONFLICT (from_city, to_city, bus_type) DO NOTHING;

INSERT INTO public.bus_routes (from_city, to_city, operator, bus_type, price, duration, is_active)
VALUES ('Hyderabad', 'Bangalore', 'ZoomFly Partner', 'Volvo Sleeper', 580, '8 hrs', TRUE)
ON CONFLICT (from_city, to_city, bus_type) DO NOTHING;



-- CAB ROUTES

INSERT INTO public.cab_services (from_location, to_location, cab_type, price, duration_hours, is_active)
VALUES ('Delhi', 'Agra', 'Hatchback/Sedan', 2800, 3.5, TRUE)
ON CONFLICT (from_location, to_location, cab_type) DO NOTHING;

INSERT INTO public.cab_services (from_location, to_location, cab_type, price, duration_hours, is_active)
VALUES ('Delhi', 'Jaipur', 'Sedan/SUV', 3500, 5, TRUE)
ON CONFLICT (from_location, to_location, cab_type) DO NOTHING;

INSERT INTO public.cab_services (from_location, to_location, cab_type, price, duration_hours, is_active)
VALUES ('Chandigarh', 'Manali', 'SUV', 6500, 8, TRUE)
ON CONFLICT (from_location, to_location, cab_type) DO NOTHING;

INSERT INTO public.cab_services (from_location, to_location, cab_type, price, duration_hours, is_active)
VALUES ('Mumbai', 'Pune', 'Sedan', 2200, 3, TRUE)
ON CONFLICT (from_location, to_location, cab_type) DO NOTHING;

INSERT INTO public.cab_services (from_location, to_location, cab_type, price, duration_hours, is_active)
VALUES ('Bangalore', 'Mysore', 'Sedan', 2000, 3, TRUE)
ON CONFLICT (from_location, to_location, cab_type) DO NOTHING;

INSERT INTO public.cab_services (from_location, to_location, cab_type, price, duration_hours, is_active)
VALUES ('Haridwar', 'Kedarnath', 'SUV', 7000, 9, TRUE)
ON CONFLICT (from_location, to_location, cab_type) DO NOTHING;

INSERT INTO public.cab_services (from_location, to_location, cab_type, price, duration_hours, is_active)
VALUES ('Delhi', 'Shimla', 'SUV', 5500, 6, TRUE)
ON CONFLICT (from_location, to_location, cab_type) DO NOTHING;

INSERT INTO public.cab_services (from_location, to_location, cab_type, price, duration_hours, is_active)
VALUES ('Kochi', 'Munnar', 'Sedan/SUV', 2800, 4, TRUE)
ON CONFLICT (from_location, to_location, cab_type) DO NOTHING;

INSERT INTO public.cab_services (from_location, to_location, cab_type, price, duration_hours, is_active)
VALUES ('Kolkata', 'Darjeeling', 'SUV', 9000, 10, TRUE)
ON CONFLICT (from_location, to_location, cab_type) DO NOTHING;