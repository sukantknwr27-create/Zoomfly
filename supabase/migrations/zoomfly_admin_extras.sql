-- ============================================================
--  ZOOMFLY ADMIN EXTRAS SQL (Fixed)
--  Run this AFTER the 4 main schema files
--  Issues fixed: #13 image uploads, #14 logo/favicon, #15 offers
-- ============================================================

-- Site Settings (Issue #14)
CREATE TABLE IF NOT EXISTS site_settings (
  id              INTEGER PRIMARY KEY DEFAULT 1,
  site_name       TEXT DEFAULT 'ZoomFly',
  logo_url        TEXT,
  favicon_url     TEXT,
  primary_color   TEXT DEFAULT '#1a73e8',
  accent_color    TEXT DEFAULT '#ff6b35',
  tagline         TEXT DEFAULT 'Travel Smart. Dream Big.',
  footer_text     TEXT DEFAULT '2026 ZoomFly Travel Services',
  whatsapp_number TEXT DEFAULT '918076136300',
  admin_email     TEXT DEFAULT 's.admin@zoomfly.in',
  gstin           TEXT,
  address         TEXT,
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);
INSERT INTO site_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

-- Add missing columns to site_settings
DO $$ BEGIN ALTER TABLE site_settings ADD COLUMN logo_url TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE site_settings ADD COLUMN favicon_url TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE site_settings ADD COLUMN tagline TEXT DEFAULT 'Travel Smart. Dream Big.'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE site_settings ADD COLUMN whatsapp_number TEXT DEFAULT '918076136300'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE site_settings ADD COLUMN admin_email TEXT DEFAULT 's.admin@zoomfly.in'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE site_settings ADD COLUMN gstin TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE site_settings ADD COLUMN address TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE site_settings ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW(); EXCEPTION WHEN duplicate_column THEN NULL; END $$;

-- Offers table (Issue #15)
CREATE TABLE IF NOT EXISTS offers (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title          TEXT NOT NULL,
  description    TEXT,
  image_url      TEXT,
  discount_type  TEXT DEFAULT 'percentage',
  discount_value NUMERIC(10,2) DEFAULT 0,
  promo_code     TEXT,
  min_booking    NUMERIC(10,2) DEFAULT 0,
  max_discount   NUMERIC(10,2),
  applies_to     TEXT DEFAULT 'all',
  valid_from     DATE DEFAULT CURRENT_DATE,
  valid_until    DATE,
  is_active      BOOLEAN DEFAULT TRUE,
  is_featured    BOOLEAN DEFAULT FALSE,
  display_order  INTEGER DEFAULT 0,
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  updated_at     TIMESTAMPTZ DEFAULT NOW()
);

-- Add missing columns to offers
DO $$ BEGIN ALTER TABLE offers ADD COLUMN image_url TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE offers ADD COLUMN discount_type TEXT DEFAULT 'percentage'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE offers ADD COLUMN discount_value NUMERIC(10,2) DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE offers ADD COLUMN promo_code TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE offers ADD COLUMN min_booking NUMERIC(10,2) DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE offers ADD COLUMN applies_to TEXT DEFAULT 'all'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE offers ADD COLUMN valid_from DATE DEFAULT CURRENT_DATE; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE offers ADD COLUMN valid_until DATE; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE offers ADD COLUMN is_active BOOLEAN DEFAULT TRUE; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE offers ADD COLUMN is_featured BOOLEAN DEFAULT FALSE; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE offers ADD COLUMN display_order INTEGER DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE offers ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW(); EXCEPTION WHEN duplicate_column THEN NULL; END $$;

-- Sample offers
INSERT INTO offers (title, description, discount_type, discount_value, promo_code, applies_to, is_featured, valid_until)
SELECT 'First Booking Offer', 'Get 10% off on your first ZoomFly booking', 'percentage', 10, 'FIRST10', 'all', true, CURRENT_DATE + 90
WHERE NOT EXISTS (SELECT 1 FROM offers WHERE promo_code = 'FIRST10');

INSERT INTO offers (title, description, discount_type, discount_value, promo_code, applies_to, is_featured, valid_until)
SELECT 'Summer Special', 'Flat 500 off on holiday packages above 10000', 'flat', 500, 'SUMMER500', 'package', true, CURRENT_DATE + 60
WHERE NOT EXISTS (SELECT 1 FROM offers WHERE promo_code = 'SUMMER500');

INSERT INTO offers (title, description, discount_type, discount_value, promo_code, applies_to, valid_until)
SELECT 'Group Discount', '15 percent off for groups of 10 or more', 'percentage', 15, 'GROUP15', 'package', CURRENT_DATE + 180
WHERE NOT EXISTS (SELECT 1 FROM offers WHERE promo_code = 'GROUP15');

-- Add image columns to packages/hotels/destinations (Issue #12 #13)
DO $$ BEGIN ALTER TABLE packages ADD COLUMN image_url TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE packages ADD COLUMN gallery JSONB DEFAULT '[]'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE hotels ADD COLUMN image_url TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE hotels ADD COLUMN gallery JSONB DEFAULT '[]'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE destinations ADD COLUMN image_url TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE destinations ADD COLUMN gallery JSONB DEFAULT '[]'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;

-- Add gender + dob + city to profiles (Issue #10)
DO $$ BEGIN ALTER TABLE profiles ADD COLUMN gender TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE profiles ADD COLUMN date_of_birth DATE; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE profiles ADD COLUMN city TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE profiles ADD COLUMN avatar_url TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;

-- RLS for site_settings
ALTER TABLE site_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public read settings" ON site_settings;
DROP POLICY IF EXISTS "Admin write settings" ON site_settings;
CREATE POLICY "Public read settings" ON site_settings FOR SELECT USING (true);
CREATE POLICY "Admin write settings" ON site_settings FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id=auth.uid() AND profiles.role='admin'));
GRANT SELECT ON site_settings TO anon, authenticated;
GRANT ALL ON site_settings TO service_role;

-- RLS for offers
ALTER TABLE offers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public read active offers" ON offers;
DROP POLICY IF EXISTS "Admin manage offers" ON offers;
CREATE POLICY "Public read active offers" ON offers FOR SELECT USING (is_active=true);
CREATE POLICY "Admin manage offers" ON offers FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id=auth.uid() AND profiles.role='admin'));
GRANT SELECT ON offers TO anon, authenticated;
GRANT ALL ON offers TO service_role;

-- ============================================================
-- SUPABASE STORAGE BUCKETS SETUP
-- Run these separately in Supabase Dashboard > Storage
-- OR run via SQL:
-- ============================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('media', 'media', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('logos', 'logos', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies
DROP POLICY IF EXISTS "Public read avatars" ON storage.objects;
DROP POLICY IF EXISTS "Auth upload avatars" ON storage.objects;
DROP POLICY IF EXISTS "Public read media"   ON storage.objects;
DROP POLICY IF EXISTS "Auth upload media"   ON storage.objects;
DROP POLICY IF EXISTS "Public read logos"   ON storage.objects;
DROP POLICY IF EXISTS "Admin upload logos"  ON storage.objects;

CREATE POLICY "Public read avatars"  ON storage.objects FOR SELECT USING (bucket_id='avatars');
CREATE POLICY "Auth upload avatars"  ON storage.objects FOR INSERT WITH CHECK (bucket_id='avatars' AND auth.uid() IS NOT NULL);
CREATE POLICY "Auth update avatars"  ON storage.objects FOR UPDATE USING (bucket_id='avatars' AND auth.uid() IS NOT NULL);

CREATE POLICY "Public read media"    ON storage.objects FOR SELECT USING (bucket_id='media');
CREATE POLICY "Auth upload media"    ON storage.objects FOR INSERT WITH CHECK (bucket_id='media' AND auth.uid() IS NOT NULL);
CREATE POLICY "Auth update media"    ON storage.objects FOR UPDATE USING (bucket_id='media' AND auth.uid() IS NOT NULL);

CREATE POLICY "Public read logos"    ON storage.objects FOR SELECT USING (bucket_id='logos');
CREATE POLICY "Admin upload logos"   ON storage.objects FOR INSERT WITH CHECK (bucket_id='logos' AND auth.uid() IS NOT NULL);
CREATE POLICY "Admin update logos"   ON storage.objects FOR UPDATE USING (bucket_id='logos' AND auth.uid() IS NOT NULL);

-- ============================================================
-- GOOGLE OAUTH SETUP INSTRUCTIONS (Issue #3)
-- ============================================================
-- 1. Go to: https://console.cloud.google.com
-- 2. Create OAuth 2.0 Client ID
-- 3. Add Authorized redirect URI:
--    https://ndaurluolurdljrjbxii.supabase.co/auth/v1/callback
-- 4. Go to Supabase Dashboard > Authentication > Providers > Google
-- 5. Enable Google provider
-- 6. Paste your Client ID and Client Secret
-- 7. Add Site URL in Supabase Auth settings:
--    https://zoomfly.in
-- 8. Add Redirect URLs:
--    https://zoomfly.in/pages/dashboard.html
--    https://zoomfly-virid.vercel.app/pages/dashboard.html
-- ============================================================

-- DONE
