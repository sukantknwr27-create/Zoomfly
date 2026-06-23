-- ================================================================
-- ZOOMFLY — New Features SQL Setup
-- Run in Supabase → SQL Editor → New Query
-- ================================================================

-- 1. Co-Travellers
CREATE TABLE IF NOT EXISTS cotravellers (
  id              uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id         uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  name            text NOT NULL,
  age             integer,
  gender          text,
  relation        text DEFAULT 'other',
  id_type         text DEFAULT 'aadhaar',
  id_number       text,
  passport_no     text,
  passport_expiry date,
  notes           text,
  created_at      timestamptz DEFAULT now(),
  updated_at      timestamptz DEFAULT now()
);

-- 2. Travel Documents
CREATE TABLE IF NOT EXISTS travel_documents (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id     uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  doc_type    text NOT NULL,
  doc_name    text,
  file_url    text,
  created_at  timestamptz DEFAULT now(),
  updated_at  timestamptz DEFAULT now(),
  UNIQUE(user_id, doc_type)
);

-- 3. Price Alerts
CREATE TABLE IF NOT EXISTS price_alerts (
  id           uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id      uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  package_id   uuid,
  target_price numeric NOT NULL,
  is_active    boolean DEFAULT true,
  triggered_at timestamptz,
  created_at   timestamptz DEFAULT now(),
  UNIQUE(user_id, package_id)
);

-- 4. Booking Modifications
CREATE TABLE IF NOT EXISTS booking_modifications (
  id                uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  booking_id        uuid REFERENCES bookings(id) ON DELETE CASCADE,
  requested_changes text,
  reason            text,
  status            text DEFAULT 'pending',
  admin_notes       text,
  created_at        timestamptz DEFAULT now(),
  resolved_at       timestamptz
);

-- 5. Payment Links
CREATE TABLE IF NOT EXISTS payment_links (
  id               uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  booking_id       uuid,
  customer_name    text,
  customer_email   text,
  customer_phone   text,
  amount           numeric NOT NULL,
  description      text,
  status           text DEFAULT 'active',
  expires_at       timestamptz,
  paid_at          timestamptz,
  created_at       timestamptz DEFAULT now()
);

-- 6. Messages (in-app chat per booking)
CREATE TABLE IF NOT EXISTS messages (
  id             uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  booking_id     uuid REFERENCES bookings(id) ON DELETE CASCADE,
  sender_id      uuid REFERENCES auth.users(id),
  sender_type    text DEFAULT 'customer',
  body           text NOT NULL,
  attachment_url text,
  is_read        boolean DEFAULT false,
  created_at     timestamptz DEFAULT now()
);

-- 7. Broadcasts
CREATE TABLE IF NOT EXISTS broadcasts (
  id             uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  subject        text NOT NULL,
  message        text NOT NULL,
  recipient_type text DEFAULT 'all_customers',
  sent_by        text,
  sent_at        timestamptz DEFAULT now(),
  status         text DEFAULT 'sent',
  recipient_count integer DEFAULT 0
);

-- 8. Train Enquiries
CREATE TABLE IF NOT EXISTS train_enquiries (
  id             uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id        uuid REFERENCES auth.users(id),
  from_station   text,
  to_station     text,
  travel_date    date,
  quota          text DEFAULT 'GN',
  passengers     integer DEFAULT 1,
  status         text DEFAULT 'new',
  created_at     timestamptz DEFAULT now()
);

-- 9. Package Availability (blocked dates)
CREATE TABLE IF NOT EXISTS package_availability (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  package_id  uuid,
  date        date NOT NULL,
  is_blocked  boolean DEFAULT true,
  reason      text,
  created_at  timestamptz DEFAULT now(),
  UNIQUE(package_id, date)
);

-- 10. Add blocked_dates + photos columns to packages if missing
ALTER TABLE packages ADD COLUMN IF NOT EXISTS photos        text[];
ALTER TABLE packages ADD COLUMN IF NOT EXISTS blocked_dates text[];
ALTER TABLE packages ADD COLUMN IF NOT EXISTS exclusions    text[];
ALTER TABLE packages ADD COLUMN IF NOT EXISTS min_group     integer DEFAULT 2;

-- ================================================================
-- RLS POLICIES (drop + recreate)
-- ================================================================
ALTER TABLE cotravellers          ENABLE ROW LEVEL SECURITY;
ALTER TABLE travel_documents      ENABLE ROW LEVEL SECURITY;
ALTER TABLE price_alerts          ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_modifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_links         ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages              ENABLE ROW LEVEL SECURITY;
ALTER TABLE broadcasts            ENABLE ROW LEVEL SECURITY;
ALTER TABLE train_enquiries       ENABLE ROW LEVEL SECURITY;
ALTER TABLE package_availability  ENABLE ROW LEVEL SECURITY;

-- Drop old
DROP POLICY IF EXISTS "Users own cotravellers"    ON cotravellers;
DROP POLICY IF EXISTS "Users own documents"        ON travel_documents;
DROP POLICY IF EXISTS "Users own alerts"           ON price_alerts;
DROP POLICY IF EXISTS "Users own modifications"    ON booking_modifications;
DROP POLICY IF EXISTS "Users own messages"         ON messages;
DROP POLICY IF EXISTS "Admin all cotravellers"     ON cotravellers;
DROP POLICY IF EXISTS "Admin all documents"        ON travel_documents;
DROP POLICY IF EXISTS "Admin all alerts"           ON price_alerts;
DROP POLICY IF EXISTS "Admin all modifications"    ON booking_modifications;
DROP POLICY IF EXISTS "Admin all payment_links"    ON payment_links;
DROP POLICY IF EXISTS "Admin all messages"         ON messages;
DROP POLICY IF EXISTS "Admin all broadcasts"       ON broadcasts;
DROP POLICY IF EXISTS "Admin all train_enquiries"  ON train_enquiries;
DROP POLICY IF EXISTS "Admin all availability"     ON package_availability;
DROP POLICY IF EXISTS "Public read availability"   ON package_availability;
DROP POLICY IF EXISTS "Anyone create train_enq"    ON train_enquiries;
DROP POLICY IF EXISTS "Anyone view payment_links"  ON payment_links;

-- User-owned data
CREATE POLICY "Users own cotravellers"   ON cotravellers     FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users own documents"       ON travel_documents FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users own alerts"          ON price_alerts     FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users own modifications"   ON booking_modifications FOR SELECT USING (
  EXISTS (SELECT 1 FROM bookings WHERE id = booking_id AND user_id = auth.uid())
);
CREATE POLICY "Users own messages" ON messages FOR ALL USING (
  sender_id = auth.uid() OR
  EXISTS (SELECT 1 FROM bookings WHERE id = booking_id AND user_id = auth.uid())
);

-- Admin full access
CREATE POLICY "Admin all cotravellers"    ON cotravellers         FOR ALL USING ((auth.jwt()->'app_metadata'->>'role')='admin');
CREATE POLICY "Admin all documents"        ON travel_documents     FOR ALL USING ((auth.jwt()->'app_metadata'->>'role')='admin');
CREATE POLICY "Admin all alerts"           ON price_alerts         FOR ALL USING ((auth.jwt()->'app_metadata'->>'role')='admin');
CREATE POLICY "Admin all modifications"    ON booking_modifications FOR ALL USING ((auth.jwt()->'app_metadata'->>'role')='admin');
CREATE POLICY "Admin all payment_links"    ON payment_links        FOR ALL USING ((auth.jwt()->'app_metadata'->>'role')='admin');
CREATE POLICY "Admin all messages"         ON messages             FOR ALL USING ((auth.jwt()->'app_metadata'->>'role')='admin');
CREATE POLICY "Admin all broadcasts"       ON broadcasts           FOR ALL USING ((auth.jwt()->'app_metadata'->>'role')='admin');
CREATE POLICY "Admin all train_enquiries"  ON train_enquiries      FOR ALL USING ((auth.jwt()->'app_metadata'->>'role')='admin');
CREATE POLICY "Admin all availability"     ON package_availability FOR ALL USING ((auth.jwt()->'app_metadata'->>'role')='admin');

-- Public access
CREATE POLICY "Public read availability"  ON package_availability FOR SELECT USING (true);
CREATE POLICY "Anyone create train_enq"   ON train_enquiries      FOR INSERT WITH CHECK (true);
CREATE POLICY "Anyone view payment_links" ON payment_links        FOR SELECT USING (status = 'active');
CREATE POLICY "Anyone create messages"    ON messages             FOR INSERT WITH CHECK (true);

SELECT 'New features tables created successfully ✅' as status;
