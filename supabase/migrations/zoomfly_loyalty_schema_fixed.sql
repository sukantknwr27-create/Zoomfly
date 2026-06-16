-- ============================================================
--  ZOOMFLY LOYALTY SCHEMA - FIXED (No ENUM conflicts)
--  Uses TEXT columns instead of ENUM types
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Loyalty accounts
CREATE TABLE IF NOT EXISTS loyalty_accounts (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID UNIQUE,
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

-- Add missing columns safely
DO $$ BEGIN ALTER TABLE loyalty_accounts ADD COLUMN user_id UUID UNIQUE; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_accounts ADD COLUMN customer_name TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_accounts ADD COLUMN customer_email TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_accounts ADD COLUMN customer_phone TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_accounts ADD COLUMN points_balance INTEGER NOT NULL DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_accounts ADD COLUMN points_earned INTEGER NOT NULL DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_accounts ADD COLUMN points_redeemed INTEGER NOT NULL DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_accounts ADD COLUMN points_expired INTEGER NOT NULL DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_accounts ADD COLUMN tier TEXT NOT NULL DEFAULT 'bronze'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_accounts ADD COLUMN tier_updated_at TIMESTAMPTZ; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_accounts ADD COLUMN referral_code TEXT UNIQUE; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_accounts ADD COLUMN referred_by UUID; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_accounts ADD COLUMN referral_count INTEGER DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_accounts ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(); EXCEPTION WHEN duplicate_column THEN NULL; END $$;

-- Loyalty transactions
CREATE TABLE IF NOT EXISTS loyalty_transactions (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id    UUID NOT NULL,
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

-- Add missing columns
DO $$ BEGIN ALTER TABLE loyalty_transactions ADD COLUMN account_id UUID NOT NULL DEFAULT uuid_generate_v4(); EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_transactions ADD COLUMN user_id UUID; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_transactions ADD COLUMN txn_type TEXT NOT NULL DEFAULT 'earn_booking'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_transactions ADD COLUMN points INTEGER NOT NULL DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_transactions ADD COLUMN balance_after INTEGER NOT NULL DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_transactions ADD COLUMN booking_ref TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_transactions ADD COLUMN booking_id UUID; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_transactions ADD COLUMN description TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE loyalty_transactions ADD COLUMN expires_at TIMESTAMPTZ; EXCEPTION WHEN duplicate_column THEN NULL; END $$;

-- Auto updated_at
CREATE OR REPLACE FUNCTION loyalty_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at:=NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_loyalty_updated_at ON loyalty_accounts;
CREATE TRIGGER trg_loyalty_updated_at
  BEFORE UPDATE ON loyalty_accounts
  FOR EACH ROW EXECUTE FUNCTION loyalty_updated_at();

-- Indexes
CREATE INDEX IF NOT EXISTS idx_loyalty_user_id  ON loyalty_accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_loyalty_ref_code ON loyalty_accounts(referral_code);
CREATE INDEX IF NOT EXISTS idx_loyalty_tier     ON loyalty_accounts(tier);
CREATE INDEX IF NOT EXISTS idx_ltxn_account_id  ON loyalty_transactions(account_id);
CREATE INDEX IF NOT EXISTS idx_ltxn_booking_ref ON loyalty_transactions(booking_ref);
CREATE INDEX IF NOT EXISTS idx_ltxn_type        ON loyalty_transactions(txn_type);
CREATE INDEX IF NOT EXISTS idx_ltxn_created     ON loyalty_transactions(created_at DESC);

-- Earn points on booking
CREATE OR REPLACE FUNCTION earn_booking_points(
  p_user_id UUID, p_booking_id UUID,
  p_booking_ref TEXT, p_amount_paid NUMERIC
)
RETURNS loyalty_accounts AS $$
DECLARE
  acct      loyalty_accounts;
  pts_rate  NUMERIC;
  pts_earn  INTEGER;
  new_bal   INTEGER;
  new_tier  TEXT;
  result    loyalty_accounts;
BEGIN
  INSERT INTO loyalty_accounts (user_id) VALUES (p_user_id) ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO acct FROM loyalty_accounts WHERE user_id=p_user_id;
  pts_rate := CASE acct.tier WHEN 'platinum' THEN 15 WHEN 'gold' THEN 10 WHEN 'silver' THEN 7 ELSE 5 END;
  pts_earn := GREATEST(1, FLOOR((p_amount_paid/100.0)*pts_rate));
  new_bal  := acct.points_balance + pts_earn;
  new_tier := CASE
    WHEN (acct.points_earned+pts_earn) >= 50000 THEN 'platinum'
    WHEN (acct.points_earned+pts_earn) >= 20000 THEN 'gold'
    WHEN (acct.points_earned+pts_earn) >= 5000  THEN 'silver'
    ELSE 'bronze'
  END;
  UPDATE loyalty_accounts SET
    points_balance=new_bal, points_earned=points_earned+pts_earn, tier=new_tier,
    tier_updated_at=CASE WHEN new_tier!=acct.tier THEN NOW() ELSE tier_updated_at END
  WHERE user_id=p_user_id RETURNING * INTO result;
  INSERT INTO loyalty_transactions (account_id, user_id, txn_type, points, balance_after, booking_ref, booking_id, description, expires_at)
  VALUES (acct.id, p_user_id, 'earn_booking', pts_earn, new_bal, p_booking_ref, p_booking_id,
    format('Earned %s points on booking %s', pts_earn, p_booking_ref), NOW()+INTERVAL '1 year');
  RETURN result;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

-- Redeem points (1 pt = Rs 0.25)
CREATE OR REPLACE FUNCTION redeem_loyalty_points(p_user_id UUID, p_points INTEGER, p_booking_ref TEXT)
RETURNS JSON AS $$
DECLARE acct loyalty_accounts; new_bal INTEGER; discount NUMERIC;
BEGIN
  SELECT * INTO acct FROM loyalty_accounts WHERE user_id=p_user_id;
  IF NOT FOUND THEN RETURN '{"error":"No loyalty account found"}'::JSON; END IF;
  IF acct.points_balance < p_points THEN RETURN json_build_object('error','Insufficient points. Balance: '||acct.points_balance); END IF;
  IF p_points < 100 THEN RETURN '{"error":"Minimum redemption is 100 points"}'::JSON; END IF;
  discount := p_points * 0.25;
  new_bal  := acct.points_balance - p_points;
  UPDATE loyalty_accounts SET points_balance=new_bal, points_redeemed=points_redeemed+p_points WHERE user_id=p_user_id;
  INSERT INTO loyalty_transactions (account_id, user_id, txn_type, points, balance_after, booking_ref, description)
  VALUES (acct.id, p_user_id, 'redeem', -p_points, new_bal, p_booking_ref, format('Redeemed %s points for Rs%s discount on %s', p_points, discount, p_booking_ref));
  RETURN json_build_object('success',true,'points_used',p_points,'discount_inr',discount,'new_balance',new_bal);
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

-- Signup bonus
CREATE OR REPLACE FUNCTION award_signup_bonus(p_user_id UUID, p_name TEXT, p_email TEXT, p_phone TEXT DEFAULT NULL)
RETURNS loyalty_accounts AS $$
DECLARE ref_code TEXT; acct loyalty_accounts;
BEGIN
  ref_code := 'ZF'||UPPER(SUBSTRING(MD5(p_user_id::TEXT),1,6));
  INSERT INTO loyalty_accounts (user_id, customer_name, customer_email, customer_phone, points_balance, points_earned, referral_code)
  VALUES (p_user_id, p_name, p_email, p_phone, 250, 250, ref_code)
  ON CONFLICT (user_id) DO NOTHING RETURNING * INTO acct;
  IF acct.id IS NOT NULL THEN
    INSERT INTO loyalty_transactions (account_id, user_id, txn_type, points, balance_after, description, expires_at)
    VALUES (acct.id, p_user_id, 'earn_signup', 250, 250, 'Welcome bonus 250 ZoomFly Points', NOW()+INTERVAL '1 year');
  END IF;
  RETURN acct;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

-- Referral bonus
CREATE OR REPLACE FUNCTION award_referral_bonus(p_referrer_code TEXT, p_new_user_id UUID)
RETURNS VOID AS $$
DECLARE referrer loyalty_accounts;
BEGIN
  SELECT * INTO referrer FROM loyalty_accounts WHERE referral_code=p_referrer_code;
  IF NOT FOUND THEN RETURN; END IF;
  UPDATE loyalty_accounts SET points_balance=points_balance+500, points_earned=points_earned+500, referral_count=referral_count+1 WHERE id=referrer.id;
  INSERT INTO loyalty_transactions (account_id, user_id, txn_type, points, balance_after, description, expires_at)
  SELECT id, referrer.user_id, 'earn_referral', 500, points_balance, 'Referral bonus - friend joined ZoomFly!', NOW()+INTERVAL '1 year'
  FROM loyalty_accounts WHERE id=referrer.id;
  UPDATE loyalty_accounts SET points_balance=points_balance+250, points_earned=points_earned+250, referred_by=referrer.id WHERE user_id=p_new_user_id;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

-- Views
CREATE OR REPLACE VIEW v_loyalty_stats AS
SELECT COUNT(*) AS total_members,
  COUNT(*) FILTER (WHERE tier='bronze') AS bronze,
  COUNT(*) FILTER (WHERE tier='silver') AS silver,
  COUNT(*) FILTER (WHERE tier='gold') AS gold,
  COUNT(*) FILTER (WHERE tier='platinum') AS platinum,
  SUM(points_balance) AS total_points_outstanding,
  SUM(points_earned) AS total_points_ever_earned,
  SUM(points_redeemed) AS total_points_redeemed,
  ROUND(SUM(points_redeemed)*0.25,2) AS total_discount_given_inr
FROM loyalty_accounts;

-- RLS
ALTER TABLE loyalty_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE loyalty_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users view own loyalty"   ON loyalty_accounts;
DROP POLICY IF EXISTS "Users update own loyalty" ON loyalty_accounts;
DROP POLICY IF EXISTS "Service role loyalty"     ON loyalty_accounts;
DROP POLICY IF EXISTS "Admins view all loyalty"  ON loyalty_accounts;
DROP POLICY IF EXISTS "Users view own txns"      ON loyalty_transactions;
DROP POLICY IF EXISTS "Service role txns"        ON loyalty_transactions;
DROP POLICY IF EXISTS "Admins view all txns"     ON loyalty_transactions;

CREATE POLICY "Users view own loyalty"   ON loyalty_accounts FOR SELECT USING (auth.uid()=user_id);
CREATE POLICY "Users update own loyalty" ON loyalty_accounts FOR UPDATE USING (auth.uid()=user_id);
CREATE POLICY "Service role loyalty"     ON loyalty_accounts FOR ALL USING (auth.role()='service_role');
CREATE POLICY "Admins view all loyalty"  ON loyalty_accounts FOR ALL USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id=auth.uid() AND profiles.role='admin'));
CREATE POLICY "Users view own txns"      ON loyalty_transactions FOR SELECT USING (auth.uid()=user_id);
CREATE POLICY "Service role txns"        ON loyalty_transactions FOR ALL USING (auth.role()='service_role');
CREATE POLICY "Admins view all txns"     ON loyalty_transactions FOR ALL USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id=auth.uid() AND profiles.role='admin'));

-- Grants
GRANT SELECT, INSERT, UPDATE ON loyalty_accounts TO authenticated;
GRANT SELECT, INSERT ON loyalty_transactions TO authenticated;
GRANT SELECT ON v_loyalty_stats TO authenticated;
GRANT EXECUTE ON FUNCTION earn_booking_points(UUID,UUID,TEXT,NUMERIC) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION redeem_loyalty_points(UUID,INTEGER,TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION award_signup_bonus(UUID,TEXT,TEXT,TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION award_referral_bonus(TEXT,UUID) TO authenticated, service_role;

-- DONE
