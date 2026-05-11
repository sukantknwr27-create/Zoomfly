-- ============================================================
--  ZOOMFLY — LOYALTY & POINTS SYSTEM SQL
--  Run in Supabase SQL Editor
--
--  Tables:   loyalty_accounts, loyalty_transactions
--  Features: Points earn on booking, redeem on checkout,
--            tier system (Silver/Gold/Platinum),
--            referral bonuses, expiry, admin views
-- ============================================================

-- ── ENUMS ──────────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE loyalty_tier AS ENUM ('bronze','silver','gold','platinum');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE loyalty_txn_type AS ENUM (
    'earn_booking',    -- Points earned from a booking
    'earn_referral',   -- Points earned from referring a user
    'earn_bonus',      -- Admin-issued bonus points
    'earn_signup',     -- Welcome points on signup
    'redeem',          -- Points redeemed for discount
    'expire',          -- Points expired
    'adjust'           -- Manual admin adjustment
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── LOYALTY ACCOUNTS ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS loyalty_accounts (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  customer_name   TEXT,
  customer_email  TEXT,
  customer_phone  TEXT,

  -- Points
  points_balance  INTEGER NOT NULL DEFAULT 0,
  points_earned   INTEGER NOT NULL DEFAULT 0,  -- lifetime earned
  points_redeemed INTEGER NOT NULL DEFAULT 0,  -- lifetime redeemed
  points_expired  INTEGER NOT NULL DEFAULT 0,

  -- Tier
  tier            loyalty_tier NOT NULL DEFAULT 'bronze',
  tier_updated_at TIMESTAMPTZ,

  -- Referral
  referral_code   TEXT UNIQUE,
  referred_by     UUID REFERENCES loyalty_accounts(id),
  referral_count  INTEGER DEFAULT 0,

  -- Meta
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── LOYALTY TRANSACTIONS ───────────────────────────────────
CREATE TABLE IF NOT EXISTS loyalty_transactions (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id    UUID NOT NULL REFERENCES loyalty_accounts(id) ON DELETE CASCADE,
  user_id       UUID REFERENCES auth.users(id),
  txn_type      loyalty_txn_type NOT NULL,
  points        INTEGER NOT NULL,          -- positive=earn, negative=redeem/expire
  balance_after INTEGER NOT NULL,
  booking_ref   TEXT,
  booking_id    UUID,
  description   TEXT,
  expires_at    TIMESTAMPTZ,               -- when these points expire (1 year from earn)
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── INDEXES ────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_loyalty_user_id    ON loyalty_accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_loyalty_ref_code   ON loyalty_accounts(referral_code);
CREATE INDEX IF NOT EXISTS idx_loyalty_tier       ON loyalty_accounts(tier);
CREATE INDEX IF NOT EXISTS idx_ltxn_account_id    ON loyalty_transactions(account_id);
CREATE INDEX IF NOT EXISTS idx_ltxn_booking_ref   ON loyalty_transactions(booking_ref);
CREATE INDEX IF NOT EXISTS idx_ltxn_type          ON loyalty_transactions(txn_type);
CREATE INDEX IF NOT EXISTS idx_ltxn_created       ON loyalty_transactions(created_at DESC);

-- ── AUTO updated_at ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION loyalty_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at := NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_loyalty_updated_at
  BEFORE UPDATE ON loyalty_accounts
  FOR EACH ROW EXECUTE FUNCTION loyalty_updated_at();

-- ── TIER CONFIG ─────────────────────────────────────────────
-- Points rate per ₹100 spent and tier thresholds
-- Bronze:   0–4,999  lifetime points  → 5 pts per ₹100
-- Silver:   5,000–19,999             → 7 pts per ₹100 + 10% extra earn
-- Gold:     20,000–49,999            → 10 pts per ₹100 + 20% extra earn
-- Platinum: 50,000+                  → 15 pts per ₹100 + 30% extra earn + free upgrade

-- ── EARN POINTS ON BOOKING ─────────────────────────────────
CREATE OR REPLACE FUNCTION earn_booking_points(
  p_user_id     UUID,
  p_booking_id  UUID,
  p_booking_ref TEXT,
  p_amount_paid NUMERIC   -- total amount paid in INR
)
RETURNS loyalty_accounts AS $$
DECLARE
  acct      loyalty_accounts;
  pts_rate  NUMERIC;
  pts_earn  INTEGER;
  new_bal   INTEGER;
  new_tier  loyalty_tier;
  result    loyalty_accounts;
BEGIN
  -- Get or create account
  INSERT INTO loyalty_accounts (user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT * INTO acct FROM loyalty_accounts WHERE user_id = p_user_id;

  -- Points rate by tier
  pts_rate := CASE acct.tier
    WHEN 'platinum' THEN 15
    WHEN 'gold'     THEN 10
    WHEN 'silver'   THEN 7
    ELSE 5
  END;

  -- 5–15 points per ₹100 spent
  pts_earn := FLOOR((p_amount_paid / 100.0) * pts_rate);
  IF pts_earn < 1 THEN pts_earn := 1; END IF;

  new_bal := acct.points_balance + pts_earn;

  -- Determine new tier based on lifetime earned
  new_tier := CASE
    WHEN (acct.points_earned + pts_earn) >= 50000 THEN 'platinum'
    WHEN (acct.points_earned + pts_earn) >= 20000 THEN 'gold'
    WHEN (acct.points_earned + pts_earn) >= 5000  THEN 'silver'
    ELSE 'bronze'
  END;

  -- Update account
  UPDATE loyalty_accounts
  SET
    points_balance  = new_bal,
    points_earned   = points_earned + pts_earn,
    tier            = new_tier,
    tier_updated_at = CASE WHEN new_tier != acct.tier THEN NOW() ELSE tier_updated_at END
  WHERE user_id = p_user_id
  RETURNING * INTO result;

  -- Record transaction
  INSERT INTO loyalty_transactions
    (account_id, user_id, txn_type, points, balance_after, booking_ref, booking_id, description, expires_at)
  VALUES
    (acct.id, p_user_id, 'earn_booking', pts_earn, new_bal, p_booking_ref, p_booking_id,
     format('Earned %s points on booking %s (₹%s paid)', pts_earn, p_booking_ref, p_amount_paid),
     NOW() + INTERVAL '1 year');

  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── REDEEM POINTS ───────────────────────────────────────────
-- 1 point = ₹0.25 discount
CREATE OR REPLACE FUNCTION redeem_loyalty_points(
  p_user_id     UUID,
  p_points      INTEGER,   -- points to redeem
  p_booking_ref TEXT
)
RETURNS JSON AS $$
DECLARE
  acct      loyalty_accounts;
  discount  NUMERIC;
  new_bal   INTEGER;
BEGIN
  SELECT * INTO acct FROM loyalty_accounts WHERE user_id = p_user_id;
  IF NOT FOUND THEN RETURN '{"error":"No loyalty account found"}'::JSON; END IF;
  IF acct.points_balance < p_points THEN
    RETURN json_build_object('error', 'Insufficient points. Balance: ' || acct.points_balance);
  END IF;
  IF p_points < 100 THEN RETURN '{"error":"Minimum redemption is 100 points"}'::JSON; END IF;

  discount := p_points * 0.25;  -- ₹0.25 per point
  new_bal  := acct.points_balance - p_points;

  UPDATE loyalty_accounts
  SET points_balance  = new_bal,
      points_redeemed = points_redeemed + p_points
  WHERE user_id = p_user_id;

  INSERT INTO loyalty_transactions
    (account_id, user_id, txn_type, points, balance_after, booking_ref, description)
  VALUES
    (acct.id, p_user_id, 'redeem', -p_points, new_bal, p_booking_ref,
     format('Redeemed %s points for ₹%s discount on %s', p_points, discount, p_booking_ref));

  RETURN json_build_object(
    'success',       true,
    'points_used',   p_points,
    'discount_inr',  discount,
    'new_balance',   new_bal
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── SIGNUP BONUS ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION award_signup_bonus(p_user_id UUID, p_name TEXT, p_email TEXT, p_phone TEXT DEFAULT NULL)
RETURNS loyalty_accounts AS $$
DECLARE
  ref_code TEXT;
  acct     loyalty_accounts;
BEGIN
  ref_code := 'ZF' || UPPER(SUBSTRING(MD5(p_user_id::TEXT), 1, 6));
  INSERT INTO loyalty_accounts
    (user_id, customer_name, customer_email, customer_phone, points_balance, points_earned, referral_code)
  VALUES
    (p_user_id, p_name, p_email, p_phone, 250, 250, ref_code)
  ON CONFLICT (user_id) DO NOTHING
  RETURNING * INTO acct;

  IF acct.id IS NOT NULL THEN
    INSERT INTO loyalty_transactions
      (account_id, user_id, txn_type, points, balance_after, description, expires_at)
    VALUES
      (acct.id, p_user_id, 'earn_signup', 250, 250,
       'Welcome bonus — 250 ZoomFly Points', NOW() + INTERVAL '1 year');
  END IF;
  RETURN acct;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── REFERRAL BONUS ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION award_referral_bonus(
  p_referrer_code TEXT,
  p_new_user_id   UUID
)
RETURNS VOID AS $$
DECLARE
  referrer loyalty_accounts;
  new_acct loyalty_accounts;
BEGIN
  SELECT * INTO referrer FROM loyalty_accounts WHERE referral_code = p_referrer_code;
  IF NOT FOUND THEN RETURN; END IF;

  -- Award referrer 500 points
  UPDATE loyalty_accounts
  SET points_balance  = points_balance + 500,
      points_earned   = points_earned + 500,
      referral_count  = referral_count + 1
  WHERE id = referrer.id;

  INSERT INTO loyalty_transactions
    (account_id, user_id, txn_type, points, balance_after, description, expires_at)
  SELECT id, referrer.user_id, 'earn_referral', 500, points_balance,
         'Referral bonus — friend joined ZoomFly!', NOW() + INTERVAL '1 year'
  FROM loyalty_accounts WHERE id = referrer.id;

  -- Award new user 250 bonus
  UPDATE loyalty_accounts
  SET points_balance = points_balance + 250,
      points_earned  = points_earned + 250,
      referred_by    = referrer.id
  WHERE user_id = p_new_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── EXPIRE OLD POINTS ───────────────────────────────────────
CREATE OR REPLACE FUNCTION expire_old_points()
RETURNS VOID AS $$
DECLARE
  txn loyalty_transactions;
BEGIN
  FOR txn IN
    SELECT * FROM loyalty_transactions
    WHERE txn_type IN ('earn_booking','earn_referral','earn_bonus','earn_signup')
      AND expires_at < NOW()
      AND points > 0
  LOOP
    UPDATE loyalty_accounts
    SET points_balance = GREATEST(0, points_balance - txn.points),
        points_expired = points_expired + txn.points
    WHERE id = txn.account_id;

    INSERT INTO loyalty_transactions
      (account_id, user_id, txn_type, points, balance_after, description)
    SELECT txn.account_id, txn.user_id, 'expire', -txn.points,
           GREATEST(0, la.points_balance - txn.points),
           'Points expired (earned on ' || txn.created_at::date || ')'
    FROM loyalty_accounts la WHERE la.id = txn.account_id;

    -- Mark original as expired (set expires_at to past)
    UPDATE loyalty_transactions SET expires_at = NULL WHERE id = txn.id;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── VIEWS ───────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_loyalty_leaderboard AS
SELECT
  la.customer_name,
  la.tier,
  la.points_balance,
  la.points_earned,
  la.referral_count,
  la.created_at
FROM loyalty_accounts la
ORDER BY la.points_earned DESC
LIMIT 100;

CREATE OR REPLACE VIEW v_loyalty_stats AS
SELECT
  COUNT(*)                                          AS total_members,
  COUNT(*) FILTER (WHERE tier='bronze')             AS bronze,
  COUNT(*) FILTER (WHERE tier='silver')             AS silver,
  COUNT(*) FILTER (WHERE tier='gold')               AS gold,
  COUNT(*) FILTER (WHERE tier='platinum')           AS platinum,
  SUM(points_balance)                               AS total_points_outstanding,
  SUM(points_earned)                                AS total_points_ever_earned,
  SUM(points_redeemed)                              AS total_points_redeemed,
  ROUND(SUM(points_redeemed) * 0.25, 2)             AS total_discount_given_inr
FROM loyalty_accounts;

-- ── RLS ─────────────────────────────────────────────────────
ALTER TABLE loyalty_accounts     ENABLE ROW LEVEL SECURITY;
ALTER TABLE loyalty_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users view own loyalty"       ON loyalty_accounts;
DROP POLICY IF EXISTS "Service role loyalty"         ON loyalty_accounts;
DROP POLICY IF EXISTS "Users view own txns"          ON loyalty_transactions;
DROP POLICY IF EXISTS "Service role txns"            ON loyalty_transactions;
DROP POLICY IF EXISTS "Admins view all loyalty"      ON loyalty_accounts;

CREATE POLICY "Users view own loyalty"   ON loyalty_accounts     FOR SELECT USING (auth.uid()=user_id);
CREATE POLICY "Users update own loyalty" ON loyalty_accounts     FOR UPDATE USING (auth.uid()=user_id);
CREATE POLICY "Users view own txns"      ON loyalty_transactions FOR SELECT USING (auth.uid()=user_id);
CREATE POLICY "Service role loyalty"     ON loyalty_accounts     FOR ALL    USING (auth.role()='service_role');
CREATE POLICY "Service role txns"        ON loyalty_transactions FOR ALL    USING (auth.role()='service_role');
CREATE POLICY "Admins view all loyalty"  ON loyalty_accounts     FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id=auth.uid() AND profiles.role='admin'));
CREATE POLICY "Admins view all txns"     ON loyalty_transactions FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id=auth.uid() AND profiles.role='admin'));

-- ── GRANTS ──────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE ON loyalty_accounts     TO authenticated;
GRANT SELECT, INSERT         ON loyalty_transactions TO authenticated;
GRANT SELECT ON v_loyalty_leaderboard TO authenticated;
GRANT SELECT ON v_loyalty_stats       TO authenticated;
GRANT EXECUTE ON FUNCTION earn_booking_points(UUID,UUID,TEXT,NUMERIC) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION redeem_loyalty_points(UUID,INTEGER,TEXT)    TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION award_signup_bonus(UUID,TEXT,TEXT,TEXT)     TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION award_referral_bonus(TEXT,UUID)             TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION expire_old_points()                         TO service_role;

-- ── DONE ✅ ──────────────────────────────────────────────────
