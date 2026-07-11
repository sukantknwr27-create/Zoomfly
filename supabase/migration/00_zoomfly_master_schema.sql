-- ================================================================
-- ZoomFly — MASTER CONSOLIDATED SCHEMA (single source of truth)
-- Replaces: 001_schema.sql, 002_audit_fixes.sql, 003_security_
--   hardening.sql, zoomfly_admin_extras.sql, zoomfly_agents_
--   schema_fixed.sql, zoomfly_bookings_schema_fixed.sql, zoomfly_
--   loyalty_schema_fixed.sql, zoomfly_vendors_schema_fixed.sql,
--   setup-new-features.sql, zoomfly-final-fix.sql
--
-- Safe to run top-to-bottom on:
--   (a) a brand-new Supabase project, or
--   (b) your EXISTING project that already ran the 10 files above
--       (every statement is idempotent: CREATE TABLE/POLICY/COLUMN
--       IF NOT EXISTS, DROP ... IF EXISTS before CREATE, etc.)
--
-- ────────────────────────────────────────────────────────────────
-- READ THIS FIRST — two things this file does NOT silently paper
-- over, because they need a decision from you, not a guess from me:
--
-- 1. SCHEMA DRIFT ON `bookings` AND `vendors`.
--    Your migrations defined these tables TWICE, under different
--    names for the same concepts:
--      bookings: guest_name/guest_email/guest_phone/booking_type/
--                taxes/discount        (001_schema.sql, final-fix)
--            vs. customer_name/customer_email/customer_phone/
--                service_type/tax_amount/discount_amount/refund_*
--                                      (zoomfly_bookings_schema_fixed.sql)
--      vendors: owner_name/business_type/bank_account
--                                      (001_schema.sql)
--            vs. contact_name/vendor_type/bank_acc_name/bank_acc_num/listings
--                                      (zoomfly_vendors_schema_fixed.sql)
--    Because every file used `CREATE TABLE IF NOT EXISTS` + separate
--    `ALTER TABLE ADD COLUMN IF NOT EXISTS` statements, your LIVE
--    database almost certainly has BOTH sets of columns sitting side
--    by side right now, with different app code (older pages vs.
--    newer edge functions) reading/writing different ones. This file
--    keeps every column from both so nothing you're currently relying
--    on breaks, but you should treat this as a real to-do: pick ONE
--    naming convention, confirm which columns your current frontend
--    actually reads (I found `guest_email`/`guest_name` used by
--    verify-razorpay-payment.ts, and `customer_email` used by the
--    003 security-hardening trigger and get_guest_booking()), and
--    plan a follow-up migration to drop the unused set. Don't do
--    that cleanup on production without a backup and a maintenance
--    window — it's a job for a session on its own.
--
-- 2. SEVERAL SECURITY HOLES BEYOND WHAT WAS FLAGGED EARLIER.
--    On top of the profiles-role-escalation and fabricated-payment
--    issues already found, this pass turned up:
--      - `payments_links` had "Anyone view payment_links" USING
--        (status='active') with NO ownership check — any visitor
--        could read every active payment link's customer name,
--        email, phone, and amount. Fixed below (owner/admin only).
--      - `approve_vendor`, `reject_vendor`, `suspend_vendor`,
--        `confirm_payment`, `initiate_refund`, `record_agent_
--        commission`, `sync_agent_stats` were all SECURITY DEFINER
--        functions GRANTed to the `authenticated` role with NO
--        internal check on who was calling them — any logged-in
--        user could call `select confirm_payment(any_booking_id,...)`
--        directly and mark someone else's booking paid for free, or
--        approve/reject any vendor, or fabricate agent commissions.
--        Fixed below: each now raises an exception unless the caller
--        is an admin or service_role.
--      - `earn_booking_points`, `redeem_loyalty_points`, `award_
--        referral_bonus` took an arbitrary `p_user_id`/target with no
--        check that it matched the caller — meaning anyone could
--        redeem or award points on someone ELSE'S account. Fixed
--        below: these now require p_user_id = auth.uid() unless the
--        caller is service_role.
--      - `loyalty_accounts` had `"Users update own loyalty" USING
--        (auth.uid()=user_id)` with no column restriction — combined
--        with a direct table GRANT UPDATE to `authenticated`, any
--        customer could run `update loyalty_accounts set points_
--        balance=999999999 where user_id=auth.uid()` from the browser
--        console and mint free discount currency. Fixed with a
--        protective trigger, same pattern as the profiles fix.
--      - The "Admin upload logos" storage policy actually only
--        checked `auth.uid() IS NOT NULL` (any logged-in user, not
--        actually admin-only) — fixed to check real admin status.
--      - `handle_new_user()` (fires on signup) read `role` straight
--        from the client-supplied signup metadata
--        (`raw_user_meta_data->>'role'`) — meaning a user could sign
--        up via `supabase.auth.signUp({ options: { data: { role:
--        'admin' } } })` and get an admin profile the instant their
--        account was created, no UPDATE needed at all. Fixed to
--        always hard-code 'customer' at signup; roles can only be
--        changed by an admin/service_role afterward.
--      - The "SET ADMIN USER" block in zoomfly-final-fix.sql could
--        never have worked: it did `SET role='user'` (not a legal
--        value — the CHECK constraint only allows customer/admin/
--        vendor/agent) and `WHERE email IN (...)` against a
--        `profiles` table that has no `email` column at all. Fixed
--        below using a proper join to auth.users and a legal role
--        value.
-- ================================================================

-- ────────────────────────────────────────────────────────────
-- 0. EXTENSIONS
-- ────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ────────────────────────────────────────────────────────────
-- 0b. ADMIN-CHECK HELPER (non-recursive, used by every policy
--     below instead of each policy re-querying profiles itself —
--     this is what avoids the "infinite recursion on profiles"
--     bug that zoomfly-final-fix.sql was originally working around)
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
BEGIN
  -- LANGUAGE plpgsql (not sql) deliberately: plpgsql defers checking
  -- that public.profiles exists until this function actually RUNS,
  -- whereas a LANGUAGE sql function is validated against the schema
  -- at CREATE time — which fails here since profiles hasn't been
  -- created yet at this point in the script on a brand-new database.
  RETURN EXISTS (
    SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'
  );
END;
$$;
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, anon, service_role;

-- Drops every existing overload of a function name, regardless of
-- its old argument or return types. Needed because several of these
-- function names already exist in your database from earlier
-- migrations with different signatures — plain CREATE OR REPLACE
-- fails with "cannot change return type of existing function"
-- (error 42P13) when that happens, so we drop first, unconditionally.
CREATE OR REPLACE FUNCTION public._drop_all_functions(fn_name TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = fn_name AND n.nspname = 'public'
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS %s CASCADE', r.sig);
  END LOOP;
END;
$$;


-- ================================================================
-- 1. CORE TABLES
-- ================================================================

-- 1.1 PROFILES
CREATE TABLE IF NOT EXISTS public.profiles (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name       TEXT,
  phone           TEXT,
  avatar_url      TEXT,
  role            TEXT NOT NULL DEFAULT 'customer' CHECK (role IN ('customer','admin','vendor','agent')),
  is_active       BOOLEAN DEFAULT TRUE,
  gender          TEXT,
  date_of_birth   DATE,
  city            TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);
DO $$ BEGIN ALTER TABLE public.profiles ADD COLUMN gender TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE public.profiles ADD COLUMN date_of_birth DATE; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE public.profiles ADD COLUMN city TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE public.profiles ADD COLUMN avatar_url TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;

-- 1.2 PACKAGES
CREATE TABLE IF NOT EXISTS public.packages (
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
  itinerary       JSONB,
  rating          NUMERIC(3,2) DEFAULT 4.5,
  review_count    INT DEFAULT 0,
  is_active       BOOLEAN DEFAULT TRUE,
  is_featured     BOOLEAN DEFAULT FALSE,
  image_url       TEXT,
  gallery         JSONB DEFAULT '[]',
  photos          TEXT[],
  blocked_dates   TEXT[],
  min_group       INTEGER DEFAULT 2,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);
DO $$ BEGIN ALTER TABLE public.packages ADD COLUMN image_url TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE public.packages ADD COLUMN gallery JSONB DEFAULT '[]'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
ALTER TABLE public.packages ADD COLUMN IF NOT EXISTS photos        TEXT[];
ALTER TABLE public.packages ADD COLUMN IF NOT EXISTS blocked_dates TEXT[];
ALTER TABLE public.packages ADD COLUMN IF NOT EXISTS exclusions    TEXT[];
ALTER TABLE public.packages ADD COLUMN IF NOT EXISTS min_group     INTEGER DEFAULT 2;

-- 1.3 HOTELS
CREATE TABLE IF NOT EXISTS public.hotels (
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
  rooms           JSONB,
  is_active       BOOLEAN DEFAULT TRUE,
  is_featured     BOOLEAN DEFAULT FALSE,
  image_url       TEXT,
  gallery         JSONB DEFAULT '[]',
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);
DO $$ BEGIN ALTER TABLE public.hotels ADD COLUMN image_url TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE public.hotels ADD COLUMN gallery JSONB DEFAULT '[]'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;

-- 1.4 ENQUIRIES
CREATE TABLE IF NOT EXISTS public.enquiries (
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
  guest_email     TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.enquiries ADD COLUMN IF NOT EXISTS guest_email TEXT;

-- 1.5 BOOKINGS — merged schema (see header note re: schema drift)
CREATE TABLE IF NOT EXISTS public.bookings (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_ref         TEXT UNIQUE,
  user_id             UUID,
  -- "new" naming (zoomfly_bookings_schema_fixed.sql)
  service_type        TEXT NOT NULL DEFAULT 'package',
  service_id          UUID,
  service_name        TEXT NOT NULL DEFAULT '',
  customer_name       TEXT NOT NULL DEFAULT '',
  customer_email      TEXT NOT NULL DEFAULT '',
  customer_phone      TEXT NOT NULL DEFAULT '',
  customer_whatsapp   TEXT,
  travel_details      JSONB NOT NULL DEFAULT '{}',
  num_adults          INTEGER NOT NULL DEFAULT 1,
  num_children        INTEGER NOT NULL DEFAULT 0,
  num_infants         INTEGER NOT NULL DEFAULT 0,
  travellers          JSONB DEFAULT '[]',
  base_amount         NUMERIC(12,2) NOT NULL DEFAULT 0,
  tax_amount          NUMERIC(12,2) NOT NULL DEFAULT 0,
  discount_amount     NUMERIC(12,2) NOT NULL DEFAULT 0,
  promo_code          TEXT,
  total_amount        NUMERIC(12,2) NOT NULL DEFAULT 0,
  currency            TEXT NOT NULL DEFAULT 'INR',
  payment_status      TEXT NOT NULL DEFAULT 'pending',
  payment_method      TEXT,
  razorpay_order_id   TEXT,
  razorpay_payment_id TEXT,
  razorpay_signature  TEXT,
  paid_amount         NUMERIC(10,2) DEFAULT 0,
  paid_at             TIMESTAMPTZ,
  refund_status       TEXT NOT NULL DEFAULT 'not_applicable',
  refund_amount       NUMERIC(12,2) DEFAULT 0,
  refund_reason       TEXT,
  refund_initiated_at TIMESTAMPTZ,
  refund_completed_at TIMESTAMPTZ,
  status              TEXT NOT NULL DEFAULT 'pending',
  status_history      JSONB DEFAULT '[]',
  confirmation_sent   BOOLEAN DEFAULT FALSE,
  whatsapp_sent       BOOLEAN DEFAULT FALSE,
  last_notified_at    TIMESTAMPTZ,
  assigned_to         TEXT,
  internal_notes      TEXT,
  vendor_id           UUID,
  vendor_confirmed    BOOLEAN DEFAULT FALSE,
  vendor_confirmed_at TIMESTAMPTZ,
  special_requests    TEXT,
  booking_source      TEXT DEFAULT 'website',
  utm_source          TEXT,
  utm_medium          TEXT,
  utm_campaign        TEXT,
  -- "legacy" naming (001_schema.sql / zoomfly-final-fix.sql) — kept
  -- alongside the above; see header note.
  booking_type        TEXT,
  package_id          UUID REFERENCES public.packages(id),
  hotel_id            UUID REFERENCES public.hotels(id),
  guest_name          TEXT,
  guest_email         TEXT,
  guest_phone         TEXT,
  checkin_date        DATE,
  checkout_date       DATE,
  travel_date         DATE,
  num_guests          INTEGER DEFAULT 1,
  num_rooms           INT DEFAULT 1,
  room_type           TEXT,
  discount            NUMERIC(10,2) DEFAULT 0,
  taxes               NUMERIC(10,2) DEFAULT 0,
  cancel_reason       TEXT,
  confirmed_at        TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  cancelled_at        TIMESTAMPTZ,
  completed_at        TIMESTAMPTZ
);
-- Safety net: add every column above with IF NOT EXISTS too, in case
-- this table already existed from only *some* of the old migrations.
DO $$ BEGIN ALTER TABLE public.bookings ADD COLUMN booking_ref TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS service_type        TEXT NOT NULL DEFAULT 'package';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS service_id          UUID;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS service_name        TEXT NOT NULL DEFAULT '';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS customer_name       TEXT NOT NULL DEFAULT '';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS customer_email      TEXT NOT NULL DEFAULT '';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS customer_phone      TEXT NOT NULL DEFAULT '';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS customer_whatsapp   TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS travel_details      JSONB NOT NULL DEFAULT '{}';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS num_adults          INTEGER NOT NULL DEFAULT 1;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS num_children        INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS num_infants         INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS travellers          JSONB DEFAULT '[]';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS base_amount         NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS tax_amount          NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS discount_amount     NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS promo_code          TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS total_amount        NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS currency            TEXT NOT NULL DEFAULT 'INR';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS payment_status      TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS payment_method      TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS razorpay_order_id   TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS razorpay_payment_id TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS razorpay_signature  TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS paid_amount         NUMERIC(10,2) DEFAULT 0;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS paid_at             TIMESTAMPTZ;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS refund_status       TEXT NOT NULL DEFAULT 'not_applicable';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS refund_amount       NUMERIC(12,2) DEFAULT 0;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS refund_reason       TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS refund_initiated_at TIMESTAMPTZ;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS refund_completed_at TIMESTAMPTZ;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS status              TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS status_history      JSONB DEFAULT '[]';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS confirmation_sent   BOOLEAN DEFAULT FALSE;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS whatsapp_sent       BOOLEAN DEFAULT FALSE;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS last_notified_at    TIMESTAMPTZ;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS assigned_to         TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS internal_notes      TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS vendor_id           UUID;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS vendor_confirmed    BOOLEAN DEFAULT FALSE;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS vendor_confirmed_at TIMESTAMPTZ;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS special_requests    TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS booking_source      TEXT DEFAULT 'website';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS utm_source          TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS utm_medium          TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS utm_campaign        TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS booking_type        TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS package_id          UUID;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS hotel_id            UUID;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS guest_name          TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS guest_email         TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS guest_phone         TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS checkin_date        DATE;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS checkout_date       DATE;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS travel_date         DATE;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS num_guests          INTEGER DEFAULT 1;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS num_rooms           INT DEFAULT 1;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS room_type           TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS discount            NUMERIC(10,2) DEFAULT 0;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS taxes               NUMERIC(10,2) DEFAULT 0;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS cancel_reason       TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS confirmed_at        TIMESTAMPTZ;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS cancelled_at        TIMESTAMPTZ;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS completed_at        TIMESTAMPTZ;
DO $$ BEGIN
  ALTER TABLE public.bookings ADD CONSTRAINT bookings_booking_ref_key UNIQUE (booking_ref);
EXCEPTION WHEN duplicate_table THEN NULL; WHEN duplicate_object THEN NULL; END $$;
-- Constraints widened to match every value the app can send
ALTER TABLE public.bookings DROP CONSTRAINT IF EXISTS bookings_booking_type_check;
ALTER TABLE public.bookings ADD CONSTRAINT bookings_booking_type_check
  CHECK (booking_type IS NULL OR booking_type IN ('package','hotel','flight','bus','cab'));

-- 1.6 PAYMENTS (deny-all by default via RLS below — service_role only)
CREATE TABLE IF NOT EXISTS public.payments (
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

-- 1.7 REVIEWS
CREATE TABLE IF NOT EXISTS public.reviews (
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

-- 1.8 WISHLISTS
CREATE TABLE IF NOT EXISTS public.wishlists (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  package_id  UUID REFERENCES public.packages(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, package_id)
);

-- 1.9 PROMO CODES
CREATE TABLE IF NOT EXISTS public.promo_codes (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  code            TEXT UNIQUE NOT NULL,
  description     TEXT,
  discount_type   TEXT DEFAULT 'percentage' CHECK (discount_type IN ('percentage','fixed')),
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

-- 1.10 VENDORS — merged schema (see header note re: schema drift)
CREATE TABLE IF NOT EXISTS public.vendors (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id             UUID UNIQUE REFERENCES public.profiles(id),
  business_name       TEXT NOT NULL,
  vendor_type         TEXT NOT NULL DEFAULT 'hotel',
  business_type       TEXT,               -- legacy (001_schema.sql)
  owner_name          TEXT,               -- legacy
  description         TEXT,
  logo_url            TEXT,
  website             TEXT,
  contact_name        TEXT NOT NULL DEFAULT '',
  email               TEXT NOT NULL DEFAULT '',
  phone               TEXT NOT NULL DEFAULT '',
  whatsapp            TEXT,
  city                TEXT NOT NULL DEFAULT '',
  state               TEXT,
  pincode             TEXT,
  address             TEXT,
  gstin               TEXT,
  pan                 TEXT,
  trade_license       TEXT,
  business_reg_number TEXT,
  capacity            TEXT,               -- legacy
  bank_account        TEXT,               -- legacy
  bank_acc_name       TEXT,
  bank_acc_num        TEXT,
  bank_ifsc           TEXT,
  bank_name           TEXT,
  bank_branch         TEXT,
  commission_rate     NUMERIC(5,2) DEFAULT 10.00,
  status              TEXT NOT NULL DEFAULT 'pending',
  status_note         TEXT,
  verified_at         TIMESTAMPTZ,        -- legacy
  approved_at         TIMESTAMPTZ,
  approved_by         TEXT,
  listings            JSONB DEFAULT '[]',
  total_bookings      INTEGER DEFAULT 0,
  confirmed_bookings  INTEGER DEFAULT 0,
  total_revenue       NUMERIC(12,2) DEFAULT 0,
  avg_rating          NUMERIC(3,1),
  notes               TEXT,
  tags                TEXT[],
  is_featured         BOOLEAN DEFAULT FALSE,
  extra_data          JSONB DEFAULT '{}',
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_active_at      TIMESTAMPTZ
);
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS business_type       TEXT;
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS owner_name          TEXT;
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS capacity            TEXT;
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS bank_account        TEXT;
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS verified_at         TIMESTAMPTZ;
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS extra_data          JSONB DEFAULT '{}';
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS status_note         TEXT;
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS approved_by         TEXT;
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS listings            JSONB DEFAULT '[]';
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS total_bookings      INTEGER DEFAULT 0;
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS confirmed_bookings  INTEGER DEFAULT 0;
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS total_revenue       NUMERIC(12,2) DEFAULT 0;
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS avg_rating          NUMERIC(3,1);
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS is_featured         BOOLEAN DEFAULT FALSE;
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS tags                TEXT[];
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS notes               TEXT;
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS last_active_at      TIMESTAMPTZ;
ALTER TABLE public.vendors DROP CONSTRAINT IF EXISTS vendors_status_check;
ALTER TABLE public.vendors ADD CONSTRAINT vendors_status_check
  CHECK (status IN ('pending','approved','active','rejected','suspended'));

-- 1.11 AGENTS + related tables
CREATE TABLE IF NOT EXISTS public.agents (
  id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id                 UUID UNIQUE REFERENCES public.profiles(id),
  full_name               TEXT NOT NULL DEFAULT '',
  email                   TEXT NOT NULL DEFAULT '',
  phone                   TEXT NOT NULL DEFAULT '',
  whatsapp                TEXT,
  city                    TEXT,
  state                   TEXT,
  pan                     TEXT,
  agent_code              TEXT UNIQUE NOT NULL DEFAULT 'ZFA000000',
  tier                    TEXT NOT NULL DEFAULT 'associate',
  status                  TEXT NOT NULL DEFAULT 'active',
  experience              TEXT,
  commission_rate         NUMERIC(5,2) DEFAULT 5.00,
  parent_agent_id         UUID REFERENCES public.agents(id),
  sub_agent_commission    NUMERIC(5,2) DEFAULT 1.00,
  bank_acc_name           TEXT,
  bank_acc_num            TEXT,
  bank_ifsc               TEXT,
  bank_name               TEXT,
  bank_branch             TEXT,
  total_bookings          INTEGER DEFAULT 0,
  confirmed_bookings      INTEGER DEFAULT 0,
  total_booking_value     NUMERIC(14,2) DEFAULT 0,
  total_commission_earned NUMERIC(14,2) DEFAULT 0,
  total_commission_paid   NUMERIC(14,2) DEFAULT 0,
  affiliate_clicks        INTEGER DEFAULT 0,
  affiliate_conversions   INTEGER DEFAULT 0,
  internal_notes          TEXT,
  approved_by             TEXT,
  approved_at             TIMESTAMPTZ,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_active_at          TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.agent_commissions (
  id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  agent_id           UUID NOT NULL REFERENCES public.agents(id),
  booking_id         UUID REFERENCES public.bookings(id),
  booking_ref        TEXT NOT NULL DEFAULT '',
  booking_amount     NUMERIC(12,2) NOT NULL DEFAULT 0,
  commission_rate    NUMERIC(5,2) NOT NULL DEFAULT 5,
  commission_amount  NUMERIC(12,2) NOT NULL DEFAULT 0,
  parent_agent_id    UUID,
  parent_commission  NUMERIC(12,2) DEFAULT 0,
  status             TEXT NOT NULL DEFAULT 'pending',
  payout_id          UUID,
  notes              TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.agent_payouts (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  agent_id       UUID NOT NULL REFERENCES public.agents(id),
  amount         NUMERIC(12,2) NOT NULL DEFAULT 0,
  tds_deducted   NUMERIC(12,2) NOT NULL DEFAULT 0,
  net_amount     NUMERIC(12,2) NOT NULL DEFAULT 0,
  payout_status  TEXT NOT NULL DEFAULT 'pending',
  payout_method  TEXT DEFAULT 'neft',
  utr_number     TEXT,
  payout_date    DATE,
  commission_ids UUID[],
  booking_count  INTEGER DEFAULT 0,
  processed_by   TEXT,
  notes          TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.agent_clicks (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  agent_code  TEXT NOT NULL,
  page        TEXT,
  ip_hash     TEXT,
  user_agent  TEXT,
  converted   BOOLEAN DEFAULT FALSE,
  booking_ref TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1.12 LOYALTY
CREATE TABLE IF NOT EXISTS public.loyalty_accounts (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID UNIQUE REFERENCES public.profiles(id),
  customer_name   TEXT,
  customer_email  TEXT,
  customer_phone  TEXT,
  points_balance  INTEGER NOT NULL DEFAULT 0,
  points_earned   INTEGER NOT NULL DEFAULT 0,
  points_redeemed INTEGER NOT NULL DEFAULT 0,
  points_expired  INTEGER NOT NULL DEFAULT 0,
  tier            TEXT NOT NULL DEFAULT 'bronze',
  tier_updated_at TIMESTAMPTZ,
  referral_code   TEXT UNIQUE,
  referred_by     UUID,
  referral_count  INTEGER DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.loyalty_transactions (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id    UUID NOT NULL REFERENCES public.loyalty_accounts(id),
  user_id       UUID,
  txn_type      TEXT NOT NULL,
  points        INTEGER NOT NULL,
  balance_after INTEGER NOT NULL,
  booking_ref   TEXT,
  booking_id    UUID,
  description   TEXT,
  expires_at    TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 1.13 CONTENT / ADMIN TABLES
CREATE TABLE IF NOT EXISTS public.destinations (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name         TEXT NOT NULL,
  country      TEXT DEFAULT 'India',
  emoji        TEXT DEFAULT '🏖️',
  image_url    TEXT,
  gallery      JSONB DEFAULT '[]',
  bg_gradient  TEXT,
  is_active    BOOLEAN NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.destinations ADD COLUMN IF NOT EXISTS image_url TEXT;
ALTER TABLE public.destinations ADD COLUMN IF NOT EXISTS gallery   JSONB DEFAULT '[]';

CREATE TABLE IF NOT EXISTS public.bus_routes (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  from_city       TEXT NOT NULL,
  to_city         TEXT NOT NULL,
  operator        TEXT DEFAULT 'Private',
  bus_type        TEXT DEFAULT 'AC Sleeper',
  price           NUMERIC(10,2) NOT NULL DEFAULT 0,
  departure_time  TEXT,
  duration        TEXT,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.cab_services (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  from_location   TEXT NOT NULL,
  to_location     TEXT NOT NULL,
  cab_type        TEXT DEFAULT 'Sedan',
  price           NUMERIC(10,2) NOT NULL DEFAULT 0,
  duration_hours  NUMERIC(5,2),
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.page_contents (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  page_slug   TEXT UNIQUE NOT NULL,
  content     TEXT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.newsletter_subscribers (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email         TEXT UNIQUE NOT NULL,
  status        TEXT DEFAULT 'active' CHECK (status IN ('active','unsubscribed')),
  source        TEXT DEFAULT 'website',
  promo_code    TEXT DEFAULT 'FIRST10',
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  subscribed_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.newsletter_subscribers ADD COLUMN IF NOT EXISTS promo_code    TEXT DEFAULT 'FIRST10';
ALTER TABLE public.newsletter_subscribers ADD COLUMN IF NOT EXISTS subscribed_at TIMESTAMPTZ DEFAULT NOW();

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

CREATE TABLE IF NOT EXISTS public.site_settings (
  id              INTEGER PRIMARY KEY DEFAULT 1,
  site_name       TEXT DEFAULT 'ZoomFly',
  logo_url        TEXT,
  favicon_url     TEXT,
  primary_color   TEXT DEFAULT '#0057FF',
  accent_color    TEXT DEFAULT '#FF6B35',
  tagline         TEXT DEFAULT 'Travel Smart. Dream Big.',
  footer_text     TEXT DEFAULT '2026 ZoomFly Travel Services',
  whatsapp_number TEXT DEFAULT '918076136300',
  admin_email     TEXT,
  gstin           TEXT,
  address         TEXT,
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);
INSERT INTO public.site_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.offers (
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

-- 1.14 CUSTOMER FEATURE TABLES
CREATE TABLE IF NOT EXISTS public.cotravellers (
  id              UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id         UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  age             INTEGER,
  gender          TEXT,
  relation        TEXT DEFAULT 'other',
  id_type         TEXT DEFAULT 'aadhaar',
  id_number       TEXT,
  passport_no     TEXT,
  passport_expiry DATE,
  notes           TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.travel_documents (
  id          UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id     UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  doc_type    TEXT NOT NULL,
  doc_name    TEXT,
  file_url    TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, doc_type)
);

CREATE TABLE IF NOT EXISTS public.price_alerts (
  id           UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id      UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  package_id   UUID REFERENCES public.packages(id),
  target_price NUMERIC NOT NULL,
  is_active    BOOLEAN DEFAULT TRUE,
  triggered_at TIMESTAMPTZ,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, package_id)
);

CREATE TABLE IF NOT EXISTS public.booking_modifications (
  id                UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  booking_id        UUID REFERENCES public.bookings(id) ON DELETE CASCADE,
  requested_changes TEXT,
  reason            TEXT,
  status            TEXT DEFAULT 'pending',
  admin_notes       TEXT,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  resolved_at       TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.payment_links (
  id             UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  booking_id     UUID REFERENCES public.bookings(id),
  user_id        UUID REFERENCES auth.users(id),
  customer_name  TEXT,
  customer_email TEXT,
  customer_phone TEXT,
  amount         NUMERIC NOT NULL,
  description    TEXT,
  status         TEXT DEFAULT 'active',
  expires_at     TIMESTAMPTZ,
  paid_at        TIMESTAMPTZ,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);
-- user_id lets us tie a payment link to whoever it was issued for,
-- so RLS can restrict reads to them instead of the whole internet.
ALTER TABLE public.payment_links ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);

CREATE TABLE IF NOT EXISTS public.messages (
  id             UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  booking_id     UUID REFERENCES public.bookings(id) ON DELETE CASCADE,
  sender_id      UUID REFERENCES auth.users(id),
  sender_type    TEXT DEFAULT 'customer',
  body           TEXT NOT NULL,
  attachment_url TEXT,
  is_read        BOOLEAN DEFAULT FALSE,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.broadcasts (
  id              UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  subject         TEXT NOT NULL,
  message         TEXT NOT NULL,
  recipient_type  TEXT DEFAULT 'all_customers',
  sent_by         TEXT,
  sent_at         TIMESTAMPTZ DEFAULT NOW(),
  status          TEXT DEFAULT 'sent',
  recipient_count INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS public.train_enquiries (
  id           UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id      UUID REFERENCES auth.users(id),
  from_station TEXT,
  to_station   TEXT,
  travel_date  DATE,
  quota        TEXT DEFAULT 'GN',
  passengers   INTEGER DEFAULT 1,
  status       TEXT DEFAULT 'new',
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.package_availability (
  id          UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  package_id  UUID REFERENCES public.packages(id),
  date        DATE NOT NULL,
  is_blocked  BOOLEAN DEFAULT TRUE,
  reason      TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(package_id, date)
);

-- ================================================================
-- 2. INDEXES
-- ================================================================
CREATE INDEX IF NOT EXISTS idx_bookings_user_id        ON public.bookings(user_id);
CREATE INDEX IF NOT EXISTS idx_bookings_status         ON public.bookings(status);
CREATE INDEX IF NOT EXISTS idx_bookings_ref             ON public.bookings(booking_ref);
CREATE INDEX IF NOT EXISTS idx_bookings_service_type    ON public.bookings(service_type);
CREATE INDEX IF NOT EXISTS idx_bookings_payment_status  ON public.bookings(payment_status);
CREATE INDEX IF NOT EXISTS idx_bookings_created_at      ON public.bookings(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bookings_customer_email  ON public.bookings(customer_email);
CREATE INDEX IF NOT EXISTS idx_bookings_customer_phone  ON public.bookings(customer_phone);
CREATE INDEX IF NOT EXISTS idx_bookings_guest_email     ON public.bookings(guest_email);
CREATE INDEX IF NOT EXISTS idx_bookings_vendor_id       ON public.bookings(vendor_id);
CREATE INDEX IF NOT EXISTS idx_bookings_travel_details  ON public.bookings USING gin(travel_details);
CREATE INDEX IF NOT EXISTS idx_enquiries_status         ON public.enquiries(status);
CREATE INDEX IF NOT EXISTS idx_enquiries_email          ON public.enquiries(email);
CREATE INDEX IF NOT EXISTS idx_packages_active          ON public.packages(is_active);
CREATE INDEX IF NOT EXISTS idx_packages_type            ON public.packages(type);
CREATE INDEX IF NOT EXISTS idx_hotels_city              ON public.hotels(city);
CREATE INDEX IF NOT EXISTS idx_reviews_package          ON public.reviews(package_id);
CREATE INDEX IF NOT EXISTS idx_wishlists_user           ON public.wishlists(user_id);
CREATE INDEX IF NOT EXISTS idx_destinations_active      ON public.destinations(is_active);
CREATE INDEX IF NOT EXISTS idx_bus_routes_active        ON public.bus_routes(is_active);
CREATE INDEX IF NOT EXISTS idx_bus_routes_cities        ON public.bus_routes(from_city, to_city);
CREATE INDEX IF NOT EXISTS idx_cab_services_active      ON public.cab_services(is_active);
CREATE INDEX IF NOT EXISTS idx_vendors_user_id          ON public.vendors(user_id);
CREATE INDEX IF NOT EXISTS idx_vendors_status           ON public.vendors(status);
CREATE INDEX IF NOT EXISTS idx_vendors_type             ON public.vendors(vendor_type);
CREATE INDEX IF NOT EXISTS idx_vendors_city             ON public.vendors(city);
CREATE INDEX IF NOT EXISTS idx_vendors_featured         ON public.vendors(is_featured) WHERE is_featured = TRUE;
CREATE INDEX IF NOT EXISTS idx_vendors_listings         ON public.vendors USING gin(listings);
CREATE INDEX IF NOT EXISTS idx_vendors_email            ON public.vendors(email);
CREATE INDEX IF NOT EXISTS idx_agents_tier              ON public.agents(tier);
CREATE INDEX IF NOT EXISTS idx_agents_status            ON public.agents(status);
CREATE INDEX IF NOT EXISTS idx_acomm_agent_id           ON public.agent_commissions(agent_id);
CREATE INDEX IF NOT EXISTS idx_acomm_booking_ref        ON public.agent_commissions(booking_ref);
CREATE INDEX IF NOT EXISTS idx_acomm_status             ON public.agent_commissions(status);
CREATE INDEX IF NOT EXISTS idx_apayout_agent_id         ON public.agent_payouts(agent_id);
CREATE INDEX IF NOT EXISTS idx_agent_clicks_code        ON public.agent_clicks(agent_code);
CREATE INDEX IF NOT EXISTS idx_agent_clicks_date        ON public.agent_clicks(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_loyalty_user_id          ON public.loyalty_accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_loyalty_ref_code         ON public.loyalty_accounts(referral_code);
CREATE INDEX IF NOT EXISTS idx_loyalty_tier             ON public.loyalty_accounts(tier);
CREATE INDEX IF NOT EXISTS idx_ltxn_account_id          ON public.loyalty_transactions(account_id);
CREATE INDEX IF NOT EXISTS idx_ltxn_booking_ref         ON public.loyalty_transactions(booking_ref);
CREATE INDEX IF NOT EXISTS idx_ltxn_type                ON public.loyalty_transactions(txn_type);
CREATE INDEX IF NOT EXISTS idx_ltxn_created             ON public.loyalty_transactions(created_at DESC);

-- ================================================================
-- 3. TRIGGERS & FUNCTIONS
-- ================================================================

-- 3.1 Generic updated_at toucher, reused by most tables
SELECT public._drop_all_functions('update_updated_at');
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS trg_packages_updated ON public.packages;
CREATE TRIGGER trg_packages_updated BEFORE UPDATE ON public.packages FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS trg_hotels_updated ON public.hotels;
CREATE TRIGGER trg_hotels_updated BEFORE UPDATE ON public.hotels FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS trg_bookings_updated ON public.bookings;
CREATE TRIGGER trg_bookings_updated BEFORE UPDATE ON public.bookings FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS trg_enquiries_updated ON public.enquiries;
CREATE TRIGGER trg_enquiries_updated BEFORE UPDATE ON public.enquiries FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS trg_vendors_updated ON public.vendors;
CREATE TRIGGER trg_vendors_updated BEFORE UPDATE ON public.vendors FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS trg_destinations_updated ON public.destinations;
CREATE TRIGGER trg_destinations_updated BEFORE UPDATE ON public.destinations FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS trg_bus_routes_updated ON public.bus_routes;
CREATE TRIGGER trg_bus_routes_updated BEFORE UPDATE ON public.bus_routes FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS trg_cab_services_updated ON public.cab_services;
CREATE TRIGGER trg_cab_services_updated BEFORE UPDATE ON public.cab_services FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS trg_agents_updated_at ON public.agents;
CREATE TRIGGER trg_agents_updated_at BEFORE UPDATE ON public.agents FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS trg_acomm_updated_at ON public.agent_commissions;
CREATE TRIGGER trg_acomm_updated_at BEFORE UPDATE ON public.agent_commissions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS trg_apayout_updated_at ON public.agent_payouts;
CREATE TRIGGER trg_apayout_updated_at BEFORE UPDATE ON public.agent_payouts FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
DROP TRIGGER IF EXISTS trg_loyalty_updated_at ON public.loyalty_accounts;
CREATE TRIGGER trg_loyalty_updated_at BEFORE UPDATE ON public.loyalty_accounts FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- 3.2 New-user signup → create profile row.
-- FIXED: no longer trusts client-supplied signup metadata for role.
-- Previously: COALESCE(NEW.raw_user_meta_data->>'role', 'customer')
-- meant `supabase.auth.signUp({options:{data:{role:'admin'}}})` from
-- the browser console made you an admin on the spot. Every account
-- now starts as 'customer', full stop — role can only change via an
-- admin/service_role action afterward.
SELECT public._drop_all_functions('handle_new_user');
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (NEW.id, NEW.raw_user_meta_data->>'full_name', 'customer')
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW; -- never block auth signup because of a profile hiccup
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 3.3 Review insert/update → recompute package rating
SELECT public._drop_all_functions('update_package_rating');
CREATE OR REPLACE FUNCTION public.update_package_rating()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.packages SET
    rating = (SELECT ROUND(AVG(rating)::NUMERIC, 2) FROM public.reviews WHERE package_id = NEW.package_id AND is_published = TRUE),
    review_count = (SELECT COUNT(*) FROM public.reviews WHERE package_id = NEW.package_id AND is_published = TRUE)
  WHERE id = NEW.package_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_package_rating ON public.reviews;
CREATE TRIGGER trg_package_rating AFTER INSERT OR UPDATE ON public.reviews FOR EACH ROW EXECUTE FUNCTION public.update_package_rating();

-- 3.4 Booking ref + status-change bookkeeping
SELECT public._drop_all_functions('generate_booking_ref');
CREATE OR REPLACE FUNCTION public.generate_booking_ref(svc TEXT DEFAULT 'GEN')
RETURNS TEXT AS $$
DECLARE
  prefix   TEXT;
  date_str TEXT;
  seq_val  INT;
BEGIN
  prefix   := UPPER(LEFT(COALESCE(svc,'GEN'), 3));
  date_str := TO_CHAR(NOW(), 'YYMMDD');
  seq_val  := FLOOR(RANDOM() * 9000 + 1000);
  RETURN 'ZF-' || prefix || date_str || seq_val;
END;
$$ LANGUAGE plpgsql;

SELECT public._drop_all_functions('track_booking_status_change');
CREATE OR REPLACE FUNCTION public.track_booking_status_change()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    NEW.status_history := COALESCE(OLD.status_history, '[]'::jsonb) ||
      jsonb_build_object('from', OLD.status, 'to', NEW.status, 'at', NOW());
    IF NEW.status = 'cancelled' THEN NEW.cancelled_at := NOW(); END IF;
    IF NEW.status = 'confirmed' THEN NEW.confirmed_at := NOW(); END IF;
    IF NEW.status = 'completed' THEN NEW.completed_at := NOW(); END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_track_status_change ON public.bookings;
CREATE TRIGGER trg_track_status_change
  BEFORE UPDATE ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.track_booking_status_change();

-- 3.5 Vendor bookkeeping: auto-updated_at + auto-assign 'vendor' role
-- to the profile behind a new vendor application.
SELECT public._drop_all_functions('set_vendor_role');
CREATE OR REPLACE FUNCTION public.set_vendor_role()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.user_id IS NOT NULL THEN
    UPDATE public.profiles SET role = 'vendor' WHERE id = NEW.user_id AND role = 'customer';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_set_vendor_role ON public.vendors;
CREATE TRIGGER trg_set_vendor_role
  AFTER INSERT ON public.vendors
  FOR EACH ROW EXECUTE FUNCTION public.set_vendor_role();

-- 3.6 Agents: auto agent_code + tier auto-upgrade based on lifetime value
SELECT public._drop_all_functions('generate_agent_code');
CREATE OR REPLACE FUNCTION public.generate_agent_code()
RETURNS TEXT AS $$
DECLARE code TEXT;
BEGIN
  code := 'ZFA' || LPAD(FLOOR(RANDOM()*999999)::TEXT, 6, '0');
  RETURN code;
END;
$$ LANGUAGE plpgsql;

SELECT public._drop_all_functions('auto_upgrade_agent_tier');
CREATE OR REPLACE FUNCTION public.auto_upgrade_agent_tier()
RETURNS TRIGGER AS $$
BEGIN
  NEW.tier := CASE
    WHEN NEW.total_booking_value >= 2000000 THEN 'platinum'
    WHEN NEW.total_booking_value >= 500000  THEN 'gold'
    WHEN NEW.total_booking_value >= 100000  THEN 'silver'
    ELSE 'associate'
  END;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auto_upgrade_tier ON public.agents;
CREATE TRIGGER trg_auto_upgrade_tier BEFORE UPDATE ON public.agents FOR EACH ROW EXECUTE FUNCTION public.auto_upgrade_agent_tier();

-- 3.7 ── SECURITY TRIGGERS ────────────────────────────────────
-- These are the actual fix for "ownership-only" RLS policies that
-- can't restrict individual columns. Each pins a table's sensitive
-- fields back to their existing value unless the request is coming
-- from service_role (your edge functions) or, where noted, an admin.

-- profiles: stop self-promotion to admin (see header note #2)
SELECT public._drop_all_functions('protect_profile_privileged_columns');
CREATE OR REPLACE FUNCTION public.protect_profile_privileged_columns()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.role() <> 'service_role' THEN
    NEW.role      := OLD.role;
    NEW.is_active := OLD.is_active;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_protect_profile_privileged_columns ON public.profiles;
CREATE TRIGGER trg_protect_profile_privileged_columns
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.protect_profile_privileged_columns();

-- vendors: stop vendors self-approving or editing their own commission
SELECT public._drop_all_functions('protect_vendor_privileged_columns');
CREATE OR REPLACE FUNCTION public.protect_vendor_privileged_columns()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    NEW.status          := OLD.status;
    NEW.status_note      := OLD.status_note;
    NEW.commission_rate   := OLD.commission_rate;
    NEW.approved_at       := OLD.approved_at;
    NEW.approved_by       := OLD.approved_by;
    NEW.verified_at       := OLD.verified_at;
    NEW.total_bookings    := OLD.total_bookings;
    NEW.confirmed_bookings:= OLD.confirmed_bookings;
    NEW.total_revenue     := OLD.total_revenue;
    NEW.is_featured       := OLD.is_featured;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_protect_vendor_privileged_columns ON public.vendors;
CREATE TRIGGER trg_protect_vendor_privileged_columns
  BEFORE UPDATE ON public.vendors
  FOR EACH ROW EXECUTE FUNCTION public.protect_vendor_privileged_columns();

-- agents: stop agents self-editing tier/commission/earnings/status
SELECT public._drop_all_functions('protect_agent_privileged_columns');
CREATE OR REPLACE FUNCTION public.protect_agent_privileged_columns()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    NEW.status                  := OLD.status;
    NEW.tier                     := OLD.tier;
    NEW.commission_rate          := OLD.commission_rate;
    NEW.sub_agent_commission     := OLD.sub_agent_commission;
    NEW.total_bookings           := OLD.total_bookings;
    NEW.confirmed_bookings       := OLD.confirmed_bookings;
    NEW.total_booking_value      := OLD.total_booking_value;
    NEW.total_commission_earned  := OLD.total_commission_earned;
    NEW.total_commission_paid    := OLD.total_commission_paid;
    NEW.parent_agent_id          := OLD.parent_agent_id;
    NEW.approved_by              := OLD.approved_by;
    NEW.approved_at              := OLD.approved_at;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_protect_agent_privileged_columns ON public.agents;
CREATE TRIGGER trg_protect_agent_privileged_columns
  BEFORE UPDATE ON public.agents
  FOR EACH ROW EXECUTE FUNCTION public.protect_agent_privileged_columns();

-- loyalty_accounts: stop customers minting their own points/tier
SELECT public._drop_all_functions('protect_loyalty_privileged_columns');
CREATE OR REPLACE FUNCTION public.protect_loyalty_privileged_columns()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    NEW.points_balance  := OLD.points_balance;
    NEW.points_earned   := OLD.points_earned;
    NEW.points_redeemed := OLD.points_redeemed;
    NEW.points_expired  := OLD.points_expired;
    NEW.tier            := OLD.tier;
    NEW.tier_updated_at := OLD.tier_updated_at;
    NEW.referral_count  := OLD.referral_count;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_protect_loyalty_privileged_columns ON public.loyalty_accounts;
CREATE TRIGGER trg_protect_loyalty_privileged_columns
  BEFORE UPDATE ON public.loyalty_accounts
  FOR EACH ROW EXECUTE FUNCTION public.protect_loyalty_privileged_columns();

-- bookings: stop fabricated "paid/confirmed" bookings on INSERT and
-- stop customers editing pricing/payment/status on UPDATE (covers
-- BOTH the legacy and new column names — see header note #1)
SELECT public._drop_all_functions('enforce_safe_booking_insert');
CREATE OR REPLACE FUNCTION public.enforce_safe_booking_insert()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.role() <> 'service_role' THEN
    IF NEW.user_id IS NOT NULL AND NEW.user_id <> auth.uid() THEN
      NEW.user_id := auth.uid();
    END IF;
    NEW.status              := 'pending';
    NEW.payment_status       := 'pending';
    NEW.paid_amount          := 0;
    NEW.paid_at              := NULL;
    NEW.confirmed_at         := NULL;
    NEW.razorpay_payment_id  := NULL;
    NEW.razorpay_signature   := NULL;
    NEW.refund_status        := 'not_applicable';
    NEW.refund_amount        := 0;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_enforce_safe_booking_insert ON public.bookings;
CREATE TRIGGER trg_enforce_safe_booking_insert
  BEFORE INSERT ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.enforce_safe_booking_insert();

SELECT public._drop_all_functions('protect_booking_payment_columns');
CREATE OR REPLACE FUNCTION public.protect_booking_payment_columns()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    -- a customer may still cancel their own booking
    IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status <> 'cancelled' THEN
      NEW.status := OLD.status;
    END IF;
    NEW.payment_status       := OLD.payment_status;
    NEW.total_amount          := OLD.total_amount;
    NEW.base_amount           := OLD.base_amount;
    NEW.discount              := OLD.discount;
    NEW.taxes                 := OLD.taxes;
    NEW.tax_amount            := OLD.tax_amount;
    NEW.discount_amount       := OLD.discount_amount;
    NEW.paid_amount           := OLD.paid_amount;
    NEW.paid_at               := OLD.paid_at;
    NEW.confirmed_at          := OLD.confirmed_at;
    NEW.razorpay_order_id     := OLD.razorpay_order_id;
    NEW.razorpay_payment_id   := OLD.razorpay_payment_id;
    NEW.razorpay_signature    := OLD.razorpay_signature;
    NEW.refund_status         := OLD.refund_status;
    NEW.refund_amount         := OLD.refund_amount;
    NEW.assigned_to           := OLD.assigned_to;
    NEW.internal_notes        := OLD.internal_notes;
    NEW.vendor_confirmed      := OLD.vendor_confirmed;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_protect_booking_payment_columns ON public.bookings;
CREATE TRIGGER trg_protect_booking_payment_columns
  BEFORE UPDATE ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.protect_booking_payment_columns();

-- ================================================================
-- 4. ROW LEVEL SECURITY
-- ================================================================
ALTER TABLE public.profiles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookings             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enquiries            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wishlists            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.packages             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hotels               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendors              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promo_codes          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.newsletter_subscribers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.destinations         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bus_routes           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cab_services         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.page_contents        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.testimonials         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.site_settings        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.offers               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendors              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agents               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_commissions    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_payouts        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_clicks         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loyalty_accounts     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loyalty_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cotravellers         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.travel_documents     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.price_alerts         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.booking_modifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_links        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.broadcasts           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.train_enquiries      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.package_availability ENABLE ROW LEVEL SECURITY;

-- Helper to drop every existing policy on a table before recreating
-- (keeps this file safe to re-run without "policy already exists" errors)
SELECT public._drop_all_functions('_drop_all_policies');
CREATE OR REPLACE FUNCTION public._drop_all_policies(tbl TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies WHERE tablename = tbl AND schemaname = 'public'
  LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', r.policyname, tbl); END LOOP;
END;
$$;

SELECT public._drop_all_policies('profiles');
SELECT public._drop_all_policies('bookings');
SELECT public._drop_all_policies('enquiries');
SELECT public._drop_all_policies('wishlists');
SELECT public._drop_all_policies('reviews');
SELECT public._drop_all_policies('packages');
SELECT public._drop_all_policies('hotels');
SELECT public._drop_all_policies('vendors');
SELECT public._drop_all_policies('promo_codes');
SELECT public._drop_all_policies('newsletter_subscribers');
SELECT public._drop_all_policies('destinations');
SELECT public._drop_all_policies('bus_routes');
SELECT public._drop_all_policies('cab_services');
SELECT public._drop_all_policies('page_contents');
SELECT public._drop_all_policies('testimonials');
SELECT public._drop_all_policies('site_settings');
SELECT public._drop_all_policies('offers');
SELECT public._drop_all_policies('agents');
SELECT public._drop_all_policies('agent_commissions');
SELECT public._drop_all_policies('agent_payouts');
SELECT public._drop_all_policies('agent_clicks');
SELECT public._drop_all_policies('loyalty_accounts');
SELECT public._drop_all_policies('loyalty_transactions');
SELECT public._drop_all_policies('cotravellers');
SELECT public._drop_all_policies('travel_documents');
SELECT public._drop_all_policies('price_alerts');
SELECT public._drop_all_policies('booking_modifications');
SELECT public._drop_all_policies('payment_links');
SELECT public._drop_all_policies('messages');
SELECT public._drop_all_policies('broadcasts');
SELECT public._drop_all_policies('train_enquiries');
SELECT public._drop_all_policies('package_availability');
-- payments intentionally NOT included: it stays default-deny (no
-- policies at all) so only service_role (your edge functions) can
-- ever touch it. Confirmed nothing in the current frontend queries
-- it directly.

-- PROFILES
CREATE POLICY "profiles_select_own_or_admin" ON public.profiles FOR SELECT USING (auth.uid() = id OR public.is_admin());
CREATE POLICY "profiles_insert_own" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "profiles_update_own" ON public.profiles FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
CREATE POLICY "profiles_admin_all" ON public.profiles FOR ALL USING (public.is_admin());

-- PACKAGES / HOTELS (public read, admin write)
CREATE POLICY "packages_public_read" ON public.packages FOR SELECT USING (is_active = TRUE OR public.is_admin());
CREATE POLICY "packages_admin_write" ON public.packages FOR ALL USING (public.is_admin());
CREATE POLICY "hotels_public_read" ON public.hotels FOR SELECT USING (is_active = TRUE OR public.is_admin());
CREATE POLICY "hotels_admin_write" ON public.hotels FOR ALL USING (public.is_admin());

-- BOOKINGS — INSERT stays permissive (guests can book); the
-- enforce_safe_booking_insert / protect_booking_payment_columns
-- triggers above are what actually stop abuse, not this policy.
CREATE POLICY "bookings_public_insert" ON public.bookings FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "bookings_select" ON public.bookings FOR SELECT USING (
  user_id = auth.uid()
  OR guest_email  = (SELECT email FROM auth.users WHERE id = auth.uid())
  OR customer_email = (SELECT email FROM auth.users WHERE id = auth.uid())
  OR public.is_admin()
);
CREATE POLICY "bookings_update_own_or_admin" ON public.bookings FOR UPDATE USING (
  user_id = auth.uid() OR public.is_admin() OR auth.role() = 'service_role'
);
CREATE POLICY "bookings_admin_delete" ON public.bookings FOR DELETE USING (public.is_admin());

-- ENQUIRIES
CREATE POLICY "enquiries_public_insert" ON public.enquiries FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "enquiries_select" ON public.enquiries FOR SELECT USING (
  email = (SELECT email FROM auth.users WHERE id = auth.uid())
  OR guest_email = (SELECT email FROM auth.users WHERE id = auth.uid())
  OR public.is_admin()
);
CREATE POLICY "enquiries_admin_update" ON public.enquiries FOR UPDATE USING (public.is_admin());

-- WISHLISTS
CREATE POLICY "wishlists_own" ON public.wishlists FOR ALL USING (user_id = auth.uid());

-- REVIEWS
CREATE POLICY "reviews_public_read" ON public.reviews FOR SELECT USING (is_published = TRUE OR public.is_admin());
CREATE POLICY "reviews_create_own" ON public.reviews FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "reviews_admin_all" ON public.reviews FOR ALL USING (public.is_admin());

-- VENDORS
CREATE POLICY "vendors_public_insert" ON public.vendors FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "vendors_select" ON public.vendors FOR SELECT USING (
  user_id = auth.uid() OR status IN ('active','approved') OR public.is_admin()
);
CREATE POLICY "vendors_update_own_or_admin" ON public.vendors FOR UPDATE USING (
  user_id = auth.uid() OR public.is_admin()
);
CREATE POLICY "vendors_admin_delete" ON public.vendors FOR DELETE USING (public.is_admin());

-- PROMO CODES
CREATE POLICY "promo_codes_public_read" ON public.promo_codes FOR SELECT USING (is_active = TRUE OR public.is_admin());
CREATE POLICY "promo_codes_admin_write" ON public.promo_codes FOR ALL USING (public.is_admin());

-- NEWSLETTER
CREATE POLICY "newsletter_public_insert" ON public.newsletter_subscribers FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "newsletter_admin_read" ON public.newsletter_subscribers FOR ALL USING (public.is_admin());

-- DESTINATIONS / BUS ROUTES / CAB SERVICES / PAGE CONTENTS
CREATE POLICY "destinations_public_read" ON public.destinations FOR SELECT USING (is_active = TRUE OR public.is_admin());
CREATE POLICY "destinations_admin_write" ON public.destinations FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "bus_routes_public_read" ON public.bus_routes FOR SELECT USING (is_active = TRUE OR public.is_admin());
CREATE POLICY "bus_routes_admin_write" ON public.bus_routes FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "cab_services_public_read" ON public.cab_services FOR SELECT USING (is_active = TRUE OR public.is_admin());
CREATE POLICY "cab_services_admin_write" ON public.cab_services FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "page_contents_public_read" ON public.page_contents FOR SELECT USING (TRUE);
CREATE POLICY "page_contents_admin_write" ON public.page_contents FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- TESTIMONIALS / SITE SETTINGS / OFFERS
CREATE POLICY "testimonials_public_read" ON public.testimonials FOR SELECT USING (is_active = TRUE OR public.is_admin());
CREATE POLICY "testimonials_admin_all" ON public.testimonials FOR ALL USING (public.is_admin());
CREATE POLICY "site_settings_public_read" ON public.site_settings FOR SELECT USING (TRUE);
CREATE POLICY "site_settings_admin_write" ON public.site_settings FOR ALL USING (public.is_admin());
CREATE POLICY "offers_public_read" ON public.offers FOR SELECT USING (is_active = TRUE OR public.is_admin());
CREATE POLICY "offers_admin_write" ON public.offers FOR ALL USING (public.is_admin());

-- AGENTS
CREATE POLICY "agents_view_own" ON public.agents FOR SELECT USING (auth.uid() = user_id OR public.is_admin());
CREATE POLICY "agents_insert_own" ON public.agents FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "agents_admin_all" ON public.agents FOR ALL USING (public.is_admin());
CREATE POLICY "agent_comm_view_own" ON public.agent_commissions FOR SELECT USING (
  agent_id IN (SELECT id FROM public.agents WHERE user_id = auth.uid()) OR public.is_admin()
);
CREATE POLICY "agent_comm_admin_all" ON public.agent_commissions FOR ALL USING (public.is_admin());
CREATE POLICY "agent_payouts_view_own" ON public.agent_payouts FOR SELECT USING (
  agent_id IN (SELECT id FROM public.agents WHERE user_id = auth.uid()) OR public.is_admin()
);
CREATE POLICY "agent_payouts_admin_all" ON public.agent_payouts FOR ALL USING (public.is_admin());
CREATE POLICY "agent_clicks_public_insert" ON public.agent_clicks FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "agent_clicks_admin_read" ON public.agent_clicks FOR SELECT USING (public.is_admin());

-- LOYALTY
CREATE POLICY "loyalty_view_own" ON public.loyalty_accounts FOR SELECT USING (auth.uid() = user_id OR public.is_admin());
CREATE POLICY "loyalty_update_own" ON public.loyalty_accounts FOR UPDATE USING (auth.uid() = user_id OR public.is_admin());
CREATE POLICY "loyalty_admin_all" ON public.loyalty_accounts FOR ALL USING (public.is_admin());
CREATE POLICY "loyalty_txns_view_own" ON public.loyalty_transactions FOR SELECT USING (auth.uid() = user_id OR public.is_admin());
CREATE POLICY "loyalty_txns_admin_all" ON public.loyalty_transactions FOR ALL USING (public.is_admin());

-- CO-TRAVELLERS / DOCUMENTS / ALERTS / MODIFICATIONS
CREATE POLICY "cotravellers_own" ON public.cotravellers FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "cotravellers_admin" ON public.cotravellers FOR ALL USING (public.is_admin());
CREATE POLICY "documents_own" ON public.travel_documents FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "documents_admin" ON public.travel_documents FOR ALL USING (public.is_admin());
CREATE POLICY "alerts_own" ON public.price_alerts FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "alerts_admin" ON public.price_alerts FOR ALL USING (public.is_admin());
CREATE POLICY "modifications_own_read" ON public.booking_modifications FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.bookings WHERE id = booking_id AND user_id = auth.uid())
);
CREATE POLICY "modifications_admin" ON public.booking_modifications FOR ALL USING (public.is_admin());

-- PAYMENT LINKS — FIXED: was public-readable by anyone with
-- status='active' (a PII/financial-data leak). Now restricted to
-- the booking's owner or the person it was explicitly issued to.
CREATE POLICY "payment_links_own_read" ON public.payment_links FOR SELECT USING (
  user_id = auth.uid()
  OR EXISTS (SELECT 1 FROM public.bookings WHERE id = booking_id AND user_id = auth.uid())
  OR public.is_admin()
);
CREATE POLICY "payment_links_admin_all" ON public.payment_links FOR ALL USING (public.is_admin());

-- MESSAGES — FIXED: insert now requires you to actually be the
-- sender or own the booking, so you can no longer post into a
-- stranger's booking thread or spoof another sender_id.
CREATE POLICY "messages_own_read" ON public.messages FOR SELECT USING (
  sender_id = auth.uid()
  OR EXISTS (SELECT 1 FROM public.bookings WHERE id = booking_id AND user_id = auth.uid())
  OR public.is_admin()
);
CREATE POLICY "messages_own_insert" ON public.messages FOR INSERT WITH CHECK (
  sender_id = auth.uid()
  OR EXISTS (SELECT 1 FROM public.bookings WHERE id = booking_id AND user_id = auth.uid())
  OR public.is_admin()
);
CREATE POLICY "messages_admin_all" ON public.messages FOR ALL USING (public.is_admin());

-- BROADCASTS / TRAIN ENQUIRIES / PACKAGE AVAILABILITY
CREATE POLICY "broadcasts_admin_all" ON public.broadcasts FOR ALL USING (public.is_admin());
CREATE POLICY "train_enq_public_insert" ON public.train_enquiries FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "train_enq_own_read" ON public.train_enquiries FOR SELECT USING (auth.uid() = user_id OR public.is_admin());
CREATE POLICY "train_enq_admin_all" ON public.train_enquiries FOR ALL USING (public.is_admin());
CREATE POLICY "availability_public_read" ON public.package_availability FOR SELECT USING (TRUE);
CREATE POLICY "availability_admin_all" ON public.package_availability FOR ALL USING (public.is_admin());

-- ================================================================
-- 5. RPC FUNCTIONS
-- Every admin-only function below now RAISES unless the caller is
-- an admin or service_role — previously they were SECURITY DEFINER
-- with EXECUTE granted to `authenticated` and NO internal check,
-- so any logged-in user could call them directly (approve any
-- vendor, mark any booking paid, fabricate agent commissions, etc).
-- ================================================================

SELECT public._drop_all_functions('confirm_payment');
CREATE OR REPLACE FUNCTION public.confirm_payment(
  p_booking_id UUID, p_razorpay_order TEXT,
  p_razorpay_payment TEXT, p_razorpay_sig TEXT, p_method TEXT DEFAULT 'upi'
) RETURNS public.bookings AS $$
DECLARE result public.bookings;
BEGIN
  IF auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized to confirm payments directly';
  END IF;
  UPDATE public.bookings SET payment_status='paid', payment_method=p_method,
    razorpay_order_id=p_razorpay_order, razorpay_payment_id=p_razorpay_payment,
    razorpay_signature=p_razorpay_sig, paid_at=NOW(), status='confirmed', updated_at=NOW()
  WHERE id=p_booking_id RETURNING * INTO result;
  RETURN result;
END; $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

SELECT public._drop_all_functions('initiate_refund');
CREATE OR REPLACE FUNCTION public.initiate_refund(p_booking_id UUID, p_refund_amount NUMERIC, p_reason TEXT)
RETURNS public.bookings AS $$
DECLARE result public.bookings;
BEGIN
  IF auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized to initiate refunds directly';
  END IF;
  UPDATE public.bookings SET refund_status='requested', refund_amount=p_refund_amount,
    refund_reason=p_reason, refund_initiated_at=NOW(), status='cancelled', updated_at=NOW()
  WHERE id=p_booking_id RETURNING * INTO result;
  RETURN result;
END; $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

SELECT public._drop_all_functions('get_dashboard_stats');
CREATE OR REPLACE FUNCTION public.get_dashboard_stats()
RETURNS JSON AS $$
DECLARE result JSON;
BEGIN
  IF NOT public.is_admin() AND auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  SELECT json_build_object(
    'total_bookings',     (SELECT COUNT(*) FROM public.bookings),
    'today_bookings',     (SELECT COUNT(*) FROM public.bookings WHERE DATE(created_at)=CURRENT_DATE),
    'pending_bookings',   (SELECT COUNT(*) FROM public.bookings WHERE status='pending'),
    'confirmed_bookings', (SELECT COUNT(*) FROM public.bookings WHERE status='confirmed'),
    'total_revenue',      (SELECT COALESCE(SUM(total_amount),0) FROM public.bookings WHERE payment_status='paid'),
    'today_revenue',      (SELECT COALESCE(SUM(total_amount),0) FROM public.bookings WHERE payment_status='paid' AND DATE(created_at)=CURRENT_DATE),
    'pending_refunds',    (SELECT COUNT(*) FROM public.bookings WHERE refund_status='requested')
  ) INTO result;
  RETURN result;
END; $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

SELECT public._drop_all_functions('approve_vendor');
CREATE OR REPLACE FUNCTION public.approve_vendor(p_vendor_id UUID, p_note TEXT DEFAULT NULL)
RETURNS public.vendors AS $$
DECLARE result public.vendors;
BEGIN
  IF NOT public.is_admin() AND auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Not authorized to approve vendors';
  END IF;
  UPDATE public.vendors SET status='active', approved_at=NOW(),
    status_note=COALESCE(p_note,'Approved by admin'), updated_at=NOW()
  WHERE id=p_vendor_id RETURNING * INTO result;
  RETURN result;
END; $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

SELECT public._drop_all_functions('reject_vendor');
CREATE OR REPLACE FUNCTION public.reject_vendor(p_vendor_id UUID, p_reason TEXT)
RETURNS public.vendors AS $$
DECLARE result public.vendors;
BEGIN
  IF NOT public.is_admin() AND auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Not authorized to reject vendors';
  END IF;
  UPDATE public.vendors SET status='rejected', status_note=p_reason, updated_at=NOW()
  WHERE id=p_vendor_id RETURNING * INTO result;
  RETURN result;
END; $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

SELECT public._drop_all_functions('suspend_vendor');
CREATE OR REPLACE FUNCTION public.suspend_vendor(p_vendor_id UUID, p_reason TEXT)
RETURNS public.vendors AS $$
DECLARE result public.vendors;
BEGIN
  IF NOT public.is_admin() AND auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Not authorized to suspend vendors';
  END IF;
  UPDATE public.vendors SET status='suspended', status_note=p_reason, updated_at=NOW()
  WHERE id=p_vendor_id RETURNING * INTO result;
  RETURN result;
END; $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

SELECT public._drop_all_functions('record_agent_commission');
CREATE OR REPLACE FUNCTION public.record_agent_commission(
  p_booking_id UUID, p_booking_ref TEXT, p_booking_amount NUMERIC, p_agent_code TEXT
) RETURNS public.agent_commissions AS $$
DECLARE
  agent_rec   public.agents;
  comm_amount NUMERIC;
  parent_comm NUMERIC := 0;
  result      public.agent_commissions;
BEGIN
  IF NOT public.is_admin() AND auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Not authorized to record commissions directly';
  END IF;
  -- Only ever pay commission on a booking that is actually paid.
  IF NOT EXISTS (SELECT 1 FROM public.bookings WHERE id = p_booking_id AND payment_status = 'paid') THEN
    RAISE EXCEPTION 'Booking % is not paid — refusing to record commission', p_booking_id;
  END IF;
  SELECT * INTO agent_rec FROM public.agents WHERE agent_code=p_agent_code AND status='active';
  IF NOT FOUND THEN RETURN NULL; END IF;
  comm_amount := ROUND(p_booking_amount*(agent_rec.commission_rate/100.0),2);
  IF agent_rec.parent_agent_id IS NOT NULL THEN
    parent_comm := ROUND(p_booking_amount*(agent_rec.sub_agent_commission/100.0),2);
  END IF;
  INSERT INTO public.agent_commissions (agent_id, booking_id, booking_ref, booking_amount, commission_rate, commission_amount, parent_agent_id, parent_commission, status)
  VALUES (agent_rec.id, p_booking_id, p_booking_ref, p_booking_amount, agent_rec.commission_rate, comm_amount, agent_rec.parent_agent_id, parent_comm, 'earned')
  RETURNING * INTO result;
  UPDATE public.agents SET confirmed_bookings=confirmed_bookings+1, total_booking_value=total_booking_value+p_booking_amount,
    total_commission_earned=total_commission_earned+comm_amount, last_active_at=NOW()
  WHERE id=agent_rec.id;
  RETURN result;
END; $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

SELECT public._drop_all_functions('sync_agent_stats');
CREATE OR REPLACE FUNCTION public.sync_agent_stats(p_agent_code TEXT)
RETURNS VOID AS $$
DECLARE agent_rec public.agents;
BEGIN
  IF NOT public.is_admin() AND auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  SELECT * INTO agent_rec FROM public.agents WHERE agent_code=p_agent_code;
  IF NOT FOUND THEN RETURN; END IF;
  UPDATE public.agents SET
    total_bookings=(SELECT COUNT(*) FROM public.bookings WHERE booking_source='agent_'||p_agent_code),
    confirmed_bookings=(SELECT COUNT(*) FROM public.bookings WHERE booking_source='agent_'||p_agent_code AND status IN ('confirmed','completed')),
    total_booking_value=(SELECT COALESCE(SUM(total_amount),0) FROM public.bookings WHERE booking_source='agent_'||p_agent_code AND payment_status='paid'),
    total_commission_earned=(SELECT COALESCE(SUM(commission_amount),0) FROM public.agent_commissions WHERE agent_id=agent_rec.id),
    total_commission_paid=(SELECT COALESCE(SUM(commission_amount),0) FROM public.agent_commissions WHERE agent_id=agent_rec.id AND status='paid'),
    last_active_at=NOW()
  WHERE id=agent_rec.id;
END; $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Loyalty: these ARE meant to be called by a logged-in customer for
-- THEIR OWN account, so instead of admin-only we require
-- p_user_id = auth.uid() unless the caller is service_role/admin —
-- fixes "anyone can redeem/earn points on someone else's account".
SELECT public._drop_all_functions('earn_booking_points');
CREATE OR REPLACE FUNCTION public.earn_booking_points(
  p_user_id UUID, p_booking_id UUID, p_booking_ref TEXT, p_amount_paid NUMERIC
) RETURNS public.loyalty_accounts AS $$
DECLARE
  acct     public.loyalty_accounts;
  pts_rate NUMERIC; pts_earn INTEGER; new_bal INTEGER; new_tier TEXT;
  result   public.loyalty_accounts;
BEGIN
  IF p_user_id <> auth.uid() AND auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Cannot earn points on another user''s account';
  END IF;
  IF auth.role() <> 'service_role' AND NOT public.is_admin()
     AND NOT EXISTS (SELECT 1 FROM public.bookings WHERE id = p_booking_id AND user_id = p_user_id AND payment_status = 'paid') THEN
    RAISE EXCEPTION 'Booking is not a paid booking belonging to this user';
  END IF;
  INSERT INTO public.loyalty_accounts (user_id) VALUES (p_user_id) ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO acct FROM public.loyalty_accounts WHERE user_id=p_user_id;
  pts_rate := CASE acct.tier WHEN 'platinum' THEN 15 WHEN 'gold' THEN 10 WHEN 'silver' THEN 7 ELSE 5 END;
  pts_earn := GREATEST(1, FLOOR((p_amount_paid/100.0)*pts_rate));
  new_bal  := acct.points_balance + pts_earn;
  new_tier := CASE
    WHEN (acct.points_earned+pts_earn) >= 50000 THEN 'platinum'
    WHEN (acct.points_earned+pts_earn) >= 20000 THEN 'gold'
    WHEN (acct.points_earned+pts_earn) >= 5000  THEN 'silver'
    ELSE 'bronze'
  END;
  UPDATE public.loyalty_accounts SET
    points_balance=new_bal, points_earned=points_earned+pts_earn, tier=new_tier,
    tier_updated_at=CASE WHEN new_tier!=acct.tier THEN NOW() ELSE tier_updated_at END
  WHERE user_id=p_user_id RETURNING * INTO result;
  INSERT INTO public.loyalty_transactions (account_id, user_id, txn_type, points, balance_after, booking_ref, booking_id, description, expires_at)
  VALUES (acct.id, p_user_id, 'earn_booking', pts_earn, new_bal, p_booking_ref, p_booking_id,
    format('Earned %s points on booking %s', pts_earn, p_booking_ref), NOW()+INTERVAL '1 year');
  RETURN result;
END; $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

SELECT public._drop_all_functions('redeem_loyalty_points');
CREATE OR REPLACE FUNCTION public.redeem_loyalty_points(p_user_id UUID, p_points INTEGER, p_booking_ref TEXT)
RETURNS JSON AS $$
DECLARE acct public.loyalty_accounts; new_bal INTEGER; discount NUMERIC;
BEGIN
  IF p_user_id <> auth.uid() AND auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Cannot redeem points on another user''s account';
  END IF;
  SELECT * INTO acct FROM public.loyalty_accounts WHERE user_id=p_user_id;
  IF NOT FOUND THEN RETURN '{"error":"No loyalty account found"}'::JSON; END IF;
  IF acct.points_balance < p_points THEN RETURN json_build_object('error','Insufficient points. Balance: '||acct.points_balance); END IF;
  IF p_points < 100 THEN RETURN '{"error":"Minimum redemption is 100 points"}'::JSON; END IF;
  discount := p_points * 0.25;
  new_bal  := acct.points_balance - p_points;
  UPDATE public.loyalty_accounts SET points_balance=new_bal, points_redeemed=points_redeemed+p_points WHERE user_id=p_user_id;
  INSERT INTO public.loyalty_transactions (account_id, user_id, txn_type, points, balance_after, booking_ref, description)
  VALUES (acct.id, p_user_id, 'redeem', -p_points, new_bal, p_booking_ref, format('Redeemed %s points for Rs%s discount on %s', p_points, discount, p_booking_ref));
  RETURN json_build_object('success',true,'points_used',p_points,'discount_inr',discount,'new_balance',new_bal);
END; $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

SELECT public._drop_all_functions('award_signup_bonus');
CREATE OR REPLACE FUNCTION public.award_signup_bonus(p_user_id UUID, p_name TEXT, p_email TEXT, p_phone TEXT DEFAULT NULL)
RETURNS public.loyalty_accounts AS $$
DECLARE ref_code TEXT; acct public.loyalty_accounts;
BEGIN
  IF p_user_id <> auth.uid() AND auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Cannot award a signup bonus to another user''s account';
  END IF;
  ref_code := 'ZF'||UPPER(SUBSTRING(MD5(p_user_id::TEXT),1,6));
  INSERT INTO public.loyalty_accounts (user_id, customer_name, customer_email, customer_phone, points_balance, points_earned, referral_code)
  VALUES (p_user_id, p_name, p_email, p_phone, 250, 250, ref_code)
  ON CONFLICT (user_id) DO NOTHING RETURNING * INTO acct;
  IF acct.id IS NOT NULL THEN
    INSERT INTO public.loyalty_transactions (account_id, user_id, txn_type, points, balance_after, description, expires_at)
    VALUES (acct.id, p_user_id, 'earn_signup', 250, 250, 'Welcome bonus 250 ZoomFly Points', NOW()+INTERVAL '1 year');
  END IF;
  RETURN acct;
END; $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

SELECT public._drop_all_functions('award_referral_bonus');
CREATE OR REPLACE FUNCTION public.award_referral_bonus(p_referrer_code TEXT, p_new_user_id UUID)
RETURNS VOID AS $$
DECLARE referrer public.loyalty_accounts;
BEGIN
  IF p_new_user_id <> auth.uid() AND auth.role() <> 'service_role' AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Cannot claim a referral bonus for another user''s account';
  END IF;
  SELECT * INTO referrer FROM public.loyalty_accounts WHERE referral_code=p_referrer_code;
  IF NOT FOUND THEN RETURN; END IF;
  IF referrer.user_id = p_new_user_id THEN RETURN; END IF; -- can't refer yourself
  UPDATE public.loyalty_accounts SET points_balance=points_balance+500, points_earned=points_earned+500, referral_count=referral_count+1 WHERE id=referrer.id;
  INSERT INTO public.loyalty_transactions (account_id, user_id, txn_type, points, balance_after, description, expires_at)
  SELECT id, referrer.user_id, 'earn_referral', 500, points_balance, 'Referral bonus - friend joined ZoomFly!', NOW()+INTERVAL '1 year'
  FROM public.loyalty_accounts WHERE id=referrer.id;
  UPDATE public.loyalty_accounts SET points_balance=points_balance+250, points_earned=points_earned+250, referred_by=referrer.id WHERE user_id=p_new_user_id;
END; $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Guest booking lookup (unchanged logic — this one was already fixed
-- correctly): requires knowing the booking_ref AND the email on file.
SELECT public._drop_all_functions('get_guest_booking');
CREATE OR REPLACE FUNCTION public.get_guest_booking(p_ref TEXT, p_email TEXT)
RETURNS SETOF public.bookings AS $$
  SELECT * FROM public.bookings
  WHERE booking_ref = UPPER(TRIM(p_ref))
    AND user_id IS NULL
    AND (lower(customer_email) = lower(TRIM(p_email)) OR lower(guest_email) = lower(TRIM(p_email)))
  LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public;

-- ================================================================
-- 6. VIEWS
-- ================================================================
DROP VIEW IF EXISTS public.v_bookings_daily CASCADE;
CREATE OR REPLACE VIEW public.v_bookings_daily AS
SELECT DATE(created_at) AS booking_date, service_type,
  COUNT(*) AS total_bookings,
  COUNT(*) FILTER (WHERE status='confirmed') AS confirmed,
  COUNT(*) FILTER (WHERE status='cancelled') AS cancelled,
  COUNT(*) FILTER (WHERE status='pending')   AS pending,
  SUM(total_amount) FILTER (WHERE payment_status='paid') AS revenue_inr
FROM public.bookings GROUP BY DATE(created_at), service_type ORDER BY booking_date DESC;

DROP VIEW IF EXISTS public.v_revenue_by_service CASCADE;
CREATE OR REPLACE VIEW public.v_revenue_by_service AS
SELECT service_type,
  COUNT(*) AS total_bookings,
  COUNT(*) FILTER (WHERE status='confirmed') AS confirmed_bookings,
  SUM(total_amount) AS gross_revenue,
  SUM(total_amount) FILTER (WHERE payment_status='paid') AS net_revenue,
  SUM(refund_amount) AS total_refunded,
  ROUND(AVG(total_amount),2) AS avg_booking_value
FROM public.bookings GROUP BY service_type ORDER BY net_revenue DESC NULLS LAST;

DROP VIEW IF EXISTS public.v_bookings_recent CASCADE;
CREATE OR REPLACE VIEW public.v_bookings_recent AS
SELECT id, booking_ref, service_type, service_name,
  customer_name, customer_email, customer_phone, customer_whatsapp,
  num_adults, num_children, base_amount, tax_amount, discount_amount, total_amount,
  payment_status, payment_method, status, refund_status, refund_amount,
  confirmation_sent, whatsapp_sent, booking_source, special_requests,
  created_at, updated_at
FROM public.bookings WHERE created_at >= NOW() - INTERVAL '30 days' ORDER BY created_at DESC;

DROP VIEW IF EXISTS public.v_vendors_overview CASCADE;
CREATE OR REPLACE VIEW public.v_vendors_overview AS
SELECT v.id, v.business_name, v.vendor_type, v.contact_name, v.email, v.phone, v.city,
  v.status, v.commission_rate, v.is_featured, v.total_bookings, v.confirmed_bookings,
  v.total_revenue,
  ROUND(v.total_revenue*(v.commission_rate/100),2) AS commission_earned,
  jsonb_array_length(COALESCE(v.listings,'[]'::jsonb)) AS listing_count,
  v.created_at, v.approved_at, v.last_active_at
FROM public.vendors v ORDER BY v.created_at DESC;

DROP VIEW IF EXISTS public.v_vendors_pending CASCADE;
CREATE OR REPLACE VIEW public.v_vendors_pending AS
SELECT id, business_name, vendor_type, contact_name, email, phone, city, gstin, created_at
FROM public.vendors WHERE status='pending' ORDER BY created_at ASC;

DROP VIEW IF EXISTS public.v_agents_overview CASCADE;
CREATE OR REPLACE VIEW public.v_agents_overview AS
SELECT a.id, a.agent_code, a.full_name, a.email, a.phone, a.city, a.tier, a.status,
  a.commission_rate, a.total_bookings, a.confirmed_bookings, a.total_booking_value,
  a.total_commission_earned, a.total_commission_paid,
  GREATEST(0, a.total_commission_earned-a.total_commission_paid) AS pending_payout,
  a.affiliate_clicks, a.affiliate_conversions,
  a.created_at, a.last_active_at
FROM public.agents a ORDER BY a.created_at DESC;

DROP VIEW IF EXISTS public.v_loyalty_stats CASCADE;
CREATE OR REPLACE VIEW public.v_loyalty_stats AS
SELECT COUNT(*) AS total_members,
  COUNT(*) FILTER (WHERE tier='bronze') AS bronze,
  COUNT(*) FILTER (WHERE tier='silver') AS silver,
  COUNT(*) FILTER (WHERE tier='gold') AS gold,
  COUNT(*) FILTER (WHERE tier='platinum') AS platinum,
  SUM(points_balance) AS total_points_outstanding,
  SUM(points_earned) AS total_points_ever_earned,
  SUM(points_redeemed) AS total_points_redeemed,
  ROUND(SUM(points_redeemed)*0.25,2) AS total_discount_given_inr
FROM public.loyalty_accounts;

-- v_vendor_listings deliberately NOT granted to anon (was previously
-- public-readable, exposing every vendor's business_name/city
-- alongside raw listing JSON to unauthenticated visitors). If your
-- vendor directory page needs this publicly, expose only the
-- specific fields it needs through a dedicated, narrower view.
DROP VIEW IF EXISTS public.v_vendor_listings CASCADE;
CREATE OR REPLACE VIEW public.v_vendor_listings AS
SELECT v.id AS vendor_id, v.business_name, v.vendor_type, v.city AS vendor_city,
  v.status, v.commission_rate, l.value AS listing
FROM public.vendors v, jsonb_array_elements(COALESCE(v.listings,'[]'::jsonb)) AS l
WHERE v.status='active';

-- ================================================================
-- 7. GRANTS
-- ================================================================
GRANT SELECT ON public.destinations, public.bus_routes, public.cab_services, public.page_contents TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.destinations, public.bus_routes, public.cab_services, public.page_contents TO authenticated;
GRANT SELECT ON public.site_settings, public.offers TO anon, authenticated;
GRANT ALL ON public.site_settings, public.offers TO service_role;

GRANT SELECT, INSERT, UPDATE ON public.bookings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.bookings TO service_role;
GRANT SELECT ON public.v_bookings_daily, public.v_revenue_by_service, public.v_bookings_recent TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_dashboard_stats() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.confirm_payment(UUID,TEXT,TEXT,TEXT,TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.initiate_refund(UUID,NUMERIC,TEXT) TO authenticated, service_role;
-- (each of these functions now self-checks admin/service_role
-- internally, so granting EXECUTE to `authenticated` is safe — the
-- function body itself raises an exception for anyone else)

GRANT SELECT, INSERT, UPDATE ON public.vendors TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.vendors TO service_role;
GRANT SELECT ON public.v_vendors_overview, public.v_vendors_pending TO authenticated;
GRANT SELECT ON public.v_vendor_listings TO authenticated; -- no longer to anon, see view comment above
GRANT EXECUTE ON FUNCTION public.approve_vendor(UUID,TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reject_vendor(UUID,TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.suspend_vendor(UUID,TEXT) TO authenticated, service_role;

GRANT SELECT, INSERT, UPDATE ON public.agents TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.agents TO service_role;
GRANT SELECT ON public.v_agents_overview TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_agent_commission(UUID,TEXT,NUMERIC,TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.sync_agent_stats(TEXT) TO authenticated, service_role;

GRANT SELECT, INSERT, UPDATE ON public.loyalty_accounts TO authenticated;
GRANT SELECT, INSERT ON public.loyalty_transactions TO authenticated;
GRANT SELECT ON public.v_loyalty_stats TO authenticated;
GRANT EXECUTE ON FUNCTION public.earn_booking_points(UUID,UUID,TEXT,NUMERIC) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.redeem_loyalty_points(UUID,INTEGER,TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.award_signup_bonus(UUID,TEXT,TEXT,TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.award_referral_bonus(TEXT,UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_guest_booking(TEXT,TEXT) TO service_role;

-- ================================================================
-- 8. STORAGE BUCKETS
-- ================================================================
INSERT INTO storage.buckets (id, name, public) VALUES ('avatars','avatars',true) ON CONFLICT (id) DO NOTHING;
INSERT INTO storage.buckets (id, name, public) VALUES ('media','media',true)     ON CONFLICT (id) DO NOTHING;
INSERT INTO storage.buckets (id, name, public) VALUES ('logos','logos',true)    ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Public read avatars" ON storage.objects;
DROP POLICY IF EXISTS "Auth upload avatars" ON storage.objects;
DROP POLICY IF EXISTS "Auth update avatars" ON storage.objects;
DROP POLICY IF EXISTS "Public read media"   ON storage.objects;
DROP POLICY IF EXISTS "Auth upload media"   ON storage.objects;
DROP POLICY IF EXISTS "Auth update media"   ON storage.objects;
DROP POLICY IF EXISTS "Public read logos"   ON storage.objects;
DROP POLICY IF EXISTS "Admin upload logos"  ON storage.objects;
DROP POLICY IF EXISTS "Admin update logos"  ON storage.objects;

CREATE POLICY "Public read avatars" ON storage.objects FOR SELECT USING (bucket_id='avatars');
CREATE POLICY "Auth upload avatars" ON storage.objects FOR INSERT WITH CHECK (bucket_id='avatars' AND auth.uid() IS NOT NULL);
CREATE POLICY "Auth update avatars" ON storage.objects FOR UPDATE USING (bucket_id='avatars' AND auth.uid() IS NOT NULL);

CREATE POLICY "Public read media" ON storage.objects FOR SELECT USING (bucket_id='media');
CREATE POLICY "Auth upload media" ON storage.objects FOR INSERT WITH CHECK (bucket_id='media' AND auth.uid() IS NOT NULL);
CREATE POLICY "Auth update media" ON storage.objects FOR UPDATE USING (bucket_id='media' AND auth.uid() IS NOT NULL);

-- FIXED: "Admin upload logos" previously only checked
-- `auth.uid() IS NOT NULL` (any logged-in user) despite the name —
-- now it actually requires admin.
CREATE POLICY "Public read logos" ON storage.objects FOR SELECT USING (bucket_id='logos');
CREATE POLICY "Admin upload logos" ON storage.objects FOR INSERT WITH CHECK (bucket_id='logos' AND public.is_admin());
CREATE POLICY "Admin update logos" ON storage.objects FOR UPDATE USING (bucket_id='logos' AND public.is_admin());

-- ================================================================
-- 9. SEED DATA (idempotent — safe to re-run)
-- ================================================================
INSERT INTO public.promo_codes (code, description, discount_type, discount_value, min_order, is_active) VALUES
  ('ZOOMFLY10', '10% off on all bookings',          'percentage', 10,  5000,  TRUE),
  ('FIRST15',   '15% off for first-time bookers',   'percentage', 15,  5000,  TRUE),
  ('SUMMER500', 'Flat ₹500 off on summer packages', 'fixed',     500, 10000,  TRUE)
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.testimonials (name, city, trip, stars, text, avatar, initials) VALUES
('Rohit Verma',          'Hyderabad', 'Manali Snow Escape',   5, 'Booked the Manali package — everything was perfect. Hotel, transfers, the Rohtang trip — ZoomFly handled every detail flawlessly.',             '#0057FF', 'RV'),
('Priya & Arjun Singh',  'Mumbai',    'Bali Honeymoon',       5, 'Our Bali honeymoon was an absolute dream. The private villa, couples spa and romantic beach dinner — all arranged perfectly.',                    '#f77062', 'PA'),
('Kavita Nair',          'Bengaluru', 'Kerala Backwaters',    5, 'Incredible value for money. Kerala backwaters on a private houseboat was a bucket-list experience. Team was available on WhatsApp throughout.',    '#43e97b', 'KN'),
('Aditya Sharma',        'Delhi',     'Ladakh Grand Tour',    5, 'Ladakh Grand Tour was life-changing. The permits, camping, jeep safari — flawlessly organised. Will book again for Spiti!',                       '#764ba2', 'AS'),
('Sunita & Rakesh Gupta','Pune',      'Rajasthan Royal Tour', 5, 'Rajasthan package exceeded all expectations. Heritage hotels, camel safari, amazing food — worth every rupee.',                                   '#fa709a', 'SR'),
('Manish Patel',         'Ahmedabad', 'Goa Beach Bliss',      4, 'Great Goa package for our group of 8. All transfers on time, hotel was excellent and the water sports were amazing!',                             '#f6d365', 'MP')
ON CONFLICT DO NOTHING;

INSERT INTO public.offers (title, description, discount_type, discount_value, promo_code, applies_to, is_featured, valid_until)
SELECT 'First Booking Offer', 'Get 10% off on your first ZoomFly booking', 'percentage', 10, 'FIRST10', 'all', true, CURRENT_DATE + 90
WHERE NOT EXISTS (SELECT 1 FROM public.offers WHERE promo_code = 'FIRST10');
INSERT INTO public.offers (title, description, discount_type, discount_value, promo_code, applies_to, is_featured, valid_until)
SELECT 'Summer Special', 'Flat 500 off on holiday packages above 10000', 'flat', 500, 'SUMMER500', 'package', true, CURRENT_DATE + 60
WHERE NOT EXISTS (SELECT 1 FROM public.offers WHERE promo_code = 'SUMMER500');
INSERT INTO public.offers (title, description, discount_type, discount_value, promo_code, applies_to, valid_until)
SELECT 'Group Discount', '15 percent off for groups of 10 or more', 'percentage', 15, 'GROUP15', 'package', CURRENT_DATE + 180
WHERE NOT EXISTS (SELECT 1 FROM public.offers WHERE promo_code = 'GROUP15');

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

-- ================================================================
-- 10. GRANT ADMIN TO A SPECIFIC ACCOUNT
-- FIXED from zoomfly-final-fix.sql, which could never have worked:
-- it did `SET role='user'` (illegal — the CHECK constraint only
-- allows customer/admin/vendor/agent) and filtered on
-- `profiles.email`, a column that doesn't exist (email lives on
-- auth.users, not profiles). This version joins to auth.users
-- correctly and uses a legal role value.
--
-- EDIT THE EMAIL BELOW to the exact address you signed up with at
-- /pages/login.html, then run just this block whenever you need to
-- (re-)grant admin to an account.
-- ================================================================
UPDATE public.profiles SET role = 'customer' WHERE role = 'admin';

UPDATE public.profiles p
SET role = 'admin'
FROM auth.users u
WHERE p.id = u.id
  AND u.email IN ('s.admin@zoomfly.in', 'casukant0711@gmail.com'); -- ← edit this list

SELECT p.id, u.email, p.role, p.full_name
FROM public.profiles p JOIN auth.users u ON u.id = p.id
WHERE p.role = 'admin';

SELECT 'ZoomFly master schema applied successfully ✅' AS status;
