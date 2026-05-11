-- ============================================================
--  ZOOMFLY — AGENTS / AFFILIATES SQL SCHEMA
--  Run in Supabase SQL Editor
--
--  Tables:    agents, agent_commissions, agent_payouts
--  Enums:     agent_tier, agent_status
--  Features:  Commission tracking, payout management,
--             tier upgrades, affiliate link tracking,
--             sub-agent network, admin views
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- 0. EXTENSIONS
-- ────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- ────────────────────────────────────────────────────────────
-- 1. ENUMS
-- ────────────────────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE agent_tier AS ENUM ('associate','senior','elite');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE agent_status AS ENUM ('pending','active','suspended','inactive');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE payout_status AS ENUM ('pending','processing','completed','failed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ────────────────────────────────────────────────────────────
-- 2. AGENTS TABLE
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS agents (

  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Identity
  full_name       TEXT NOT NULL,
  email           TEXT NOT NULL,
  phone           TEXT NOT NULL,
  whatsapp        TEXT,
  city            TEXT,
  state           TEXT,
  pan             TEXT,                  -- Required for payout above ₹5,000/year

  -- Agent details
  agent_code      TEXT UNIQUE NOT NULL,  -- e.g. ZFA1A2B3
  tier            agent_tier NOT NULL DEFAULT 'associate',
  status          agent_status NOT NULL DEFAULT 'active',
  experience      TEXT,                  -- 'new','1-3','3-5','5+'

  -- Commission rates (can be overridden per agent)
  commission_rate NUMERIC(5,2) DEFAULT 5.00,   -- % of booking amount
  -- Tier thresholds:
  --   associate: 5% (0–49 bookings / < ₹5L revenue)
  --   senior:    7% (50–199 bookings / ₹5L–₹25L)
  --   elite:    10% (200+ bookings / ₹25L+)

  -- Sub-agent network
  parent_agent_id UUID REFERENCES agents(id), -- for sub-agent hierarchy
  sub_agent_commission NUMERIC(5,2) DEFAULT 1.00,  -- % given to parent on sub-agent bookings

  -- Bank / Payout
  bank_acc_name   TEXT,
  bank_acc_num    TEXT,
  bank_ifsc       TEXT,
  bank_name       TEXT,
  bank_branch     TEXT,

  -- Performance stats (denormalised)
  total_bookings        INTEGER   DEFAULT 0,
  confirmed_bookings    INTEGER   DEFAULT 0,
  total_booking_value   NUMERIC(14,2) DEFAULT 0,
  total_commission_earned NUMERIC(14,2) DEFAULT 0,
  total_commission_paid   NUMERIC(14,2) DEFAULT 0,

  -- Affiliate tracking
  affiliate_clicks  INTEGER DEFAULT 0,
  affiliate_conversions INTEGER DEFAULT 0,

  -- Notes
  internal_notes  TEXT,
  approved_by     TEXT,
  approved_at     TIMESTAMPTZ,

  -- Timestamps
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_active_at  TIMESTAMPTZ

);


-- ────────────────────────────────────────────────────────────
-- 3. AGENT COMMISSIONS TABLE
--    One row per booking that earns commission
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS agent_commissions (

  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  agent_id        UUID NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
  booking_id      UUID REFERENCES bookings(id) ON DELETE SET NULL,
  booking_ref     TEXT NOT NULL,

  -- Amounts
  booking_amount  NUMERIC(12,2) NOT NULL DEFAULT 0,  -- total booking value
  commission_rate NUMERIC(5,2)  NOT NULL DEFAULT 5,  -- % rate applied
  commission_amount NUMERIC(12,2) NOT NULL DEFAULT 0, -- actual commission ₹

  -- Parent agent commission (sub-agent network)
  parent_agent_id   UUID REFERENCES agents(id),
  parent_commission NUMERIC(12,2) DEFAULT 0,

  -- Status
  status          TEXT NOT NULL DEFAULT 'pending',
  -- pending   → booking confirmed but payment not received
  -- earned    → payment received, commission calculated
  -- paid      → included in a payout
  -- reversed  → booking cancelled, commission reversed

  payout_id       UUID,   -- FK to agent_payouts (set when paid)

  -- Meta
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()

);


-- ────────────────────────────────────────────────────────────
-- 4. AGENT PAYOUTS TABLE
--    Batch payouts to agents
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS agent_payouts (

  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  agent_id        UUID NOT NULL REFERENCES agents(id) ON DELETE CASCADE,

  amount          NUMERIC(12,2) NOT NULL DEFAULT 0,
  tds_deducted    NUMERIC(12,2) NOT NULL DEFAULT 0,   -- 5% TDS if annual > ₹15,000
  net_amount      NUMERIC(12,2) NOT NULL DEFAULT 0,   -- amount actually transferred

  payout_status   payout_status NOT NULL DEFAULT 'pending',
  payout_method   TEXT DEFAULT 'neft',                -- neft/rtgs/upi
  utr_number      TEXT,                               -- bank UTR reference
  payout_date     DATE,

  commission_ids  UUID[],     -- array of agent_commission IDs included in this payout
  booking_count   INTEGER DEFAULT 0,

  processed_by    TEXT,
  notes           TEXT,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()

);


-- ────────────────────────────────────────────────────────────
-- 5. AFFILIATE CLICK TRACKING TABLE
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS agent_clicks (

  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  agent_code  TEXT NOT NULL,
  page        TEXT,              -- page visited via affiliate link
  ip_hash     TEXT,              -- hashed IP for dedup (no PII stored)
  user_agent  TEXT,
  converted   BOOLEAN DEFAULT FALSE,
  booking_ref TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()

);

CREATE INDEX IF NOT EXISTS idx_agent_clicks_code ON agent_clicks(agent_code);
CREATE INDEX IF NOT EXISTS idx_agent_clicks_date ON agent_clicks(created_at DESC);


-- ────────────────────────────────────────────────────────────
-- 6. INDEXES
-- ────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_agents_user_id    ON agents(user_id);
CREATE INDEX IF NOT EXISTS idx_agents_code       ON agents(agent_code);
CREATE INDEX IF NOT EXISTS idx_agents_tier       ON agents(tier);
CREATE INDEX IF NOT EXISTS idx_agents_status     ON agents(status);
CREATE INDEX IF NOT EXISTS idx_agents_parent     ON agents(parent_agent_id);
CREATE INDEX IF NOT EXISTS idx_acomm_agent_id    ON agent_commissions(agent_id);
CREATE INDEX IF NOT EXISTS idx_acomm_booking_ref ON agent_commissions(booking_ref);
CREATE INDEX IF NOT EXISTS idx_acomm_status      ON agent_commissions(status);
CREATE INDEX IF NOT EXISTS idx_apayout_agent_id  ON agent_payouts(agent_id);
CREATE INDEX IF NOT EXISTS idx_apayout_status    ON agent_payouts(payout_status);


-- ────────────────────────────────────────────────────────────
-- 7. AUTO updated_at TRIGGERS
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION agents_updated_at()
RETURNS TRIGGER AS $$ BEGIN NEW.updated_at:=NOW(); RETURN NEW; END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_agents_updated_at
  BEFORE UPDATE ON agents FOR EACH ROW EXECUTE FUNCTION agents_updated_at();

CREATE OR REPLACE TRIGGER trg_acomm_updated_at
  BEFORE UPDATE ON agent_commissions FOR EACH ROW EXECUTE FUNCTION agents_updated_at();

CREATE OR REPLACE TRIGGER trg_apayout_updated_at
  BEFORE UPDATE ON agent_payouts FOR EACH ROW EXECUTE FUNCTION agents_updated_at();


-- ────────────────────────────────────────────────────────────
-- 8. AUTO AGENT CODE GENERATOR
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION generate_agent_code()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.agent_code IS NULL OR NEW.agent_code = '' THEN
    NEW.agent_code := 'ZFA' || UPPER(SUBSTRING(MD5(NEW.user_id::TEXT || NOW()::TEXT), 1, 6));
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_generate_agent_code
  BEFORE INSERT ON agents
  FOR EACH ROW EXECUTE FUNCTION generate_agent_code();


-- ────────────────────────────────────────────────────────────
-- 9. AUTO TIER UPGRADE TRIGGER
--    Upgrades agent tier based on confirmed bookings + revenue
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION auto_upgrade_agent_tier()
RETURNS TRIGGER AS $$
DECLARE
  new_tier         agent_tier;
  new_comm_rate    NUMERIC(5,2);
BEGIN
  -- Only trigger on stats updates
  IF (NEW.confirmed_bookings IS NOT DISTINCT FROM OLD.confirmed_bookings) AND
     (NEW.total_booking_value IS NOT DISTINCT FROM OLD.total_booking_value) THEN
    RETURN NEW;
  END IF;

  new_tier := CASE
    WHEN NEW.confirmed_bookings >= 200 OR NEW.total_booking_value >= 2500000 THEN 'elite'
    WHEN NEW.confirmed_bookings >= 50  OR NEW.total_booking_value >= 500000  THEN 'senior'
    ELSE 'associate'
  END;

  new_comm_rate := CASE new_tier
    WHEN 'elite'     THEN 10.00
    WHEN 'senior'    THEN 7.00
    ELSE                  5.00
  END;

  IF new_tier != OLD.tier THEN
    NEW.tier            := new_tier;
    NEW.commission_rate := new_comm_rate;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_auto_upgrade_tier
  BEFORE UPDATE ON agents
  FOR EACH ROW EXECUTE FUNCTION auto_upgrade_agent_tier();


-- ────────────────────────────────────────────────────────────
-- 10. RECORD COMMISSION ON BOOKING CONFIRMATION
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION record_agent_commission(
  p_booking_id     UUID,
  p_booking_ref    TEXT,
  p_booking_amount NUMERIC,
  p_agent_code     TEXT
)
RETURNS agent_commissions AS $$
DECLARE
  agent_rec    agents;
  comm_amount  NUMERIC;
  parent_comm  NUMERIC := 0;
  result       agent_commissions;
BEGIN
  -- Find agent by code
  SELECT * INTO agent_rec FROM agents WHERE agent_code = p_agent_code AND status = 'active';
  IF NOT FOUND THEN RETURN NULL; END IF;

  comm_amount := ROUND(p_booking_amount * (agent_rec.commission_rate / 100.0), 2);

  -- Parent agent sub-commission
  IF agent_rec.parent_agent_id IS NOT NULL THEN
    parent_comm := ROUND(p_booking_amount * (agent_rec.sub_agent_commission / 100.0), 2);
  END IF;

  -- Insert commission record
  INSERT INTO agent_commissions
    (agent_id, booking_id, booking_ref, booking_amount, commission_rate,
     commission_amount, parent_agent_id, parent_commission, status)
  VALUES
    (agent_rec.id, p_booking_id, p_booking_ref, p_booking_amount,
     agent_rec.commission_rate, comm_amount,
     agent_rec.parent_agent_id, parent_comm, 'earned')
  RETURNING * INTO result;

  -- Update agent stats
  UPDATE agents
  SET
    confirmed_bookings      = confirmed_bookings + 1,
    total_booking_value     = total_booking_value + p_booking_amount,
    total_commission_earned = total_commission_earned + comm_amount,
    last_active_at          = NOW()
  WHERE id = agent_rec.id;

  -- Update parent agent stats if applicable
  IF agent_rec.parent_agent_id IS NOT NULL AND parent_comm > 0 THEN
    UPDATE agents
    SET total_commission_earned = total_commission_earned + parent_comm,
        last_active_at          = NOW()
    WHERE id = agent_rec.parent_agent_id;

    INSERT INTO agent_commissions
      (agent_id, booking_id, booking_ref, booking_amount, commission_rate,
       commission_amount, status, notes)
    VALUES
      (agent_rec.parent_agent_id, p_booking_id, p_booking_ref, p_booking_amount,
       agent_rec.sub_agent_commission, parent_comm, 'earned',
       'Sub-agent commission from ' || p_agent_code);
  END IF;

  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ────────────────────────────────────────────────────────────
-- 11. PROCESS PAYOUT (admin use)
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION process_agent_payout(
  p_agent_id    UUID,
  p_utr         TEXT DEFAULT NULL,
  p_notes       TEXT DEFAULT NULL
)
RETURNS agent_payouts AS $$
DECLARE
  pending_comms  agent_commissions[];
  total_amount   NUMERIC := 0;
  tds_amount     NUMERIC := 0;
  net_amount     NUMERIC;
  comm_ids       UUID[];
  booking_cnt    INTEGER;
  payout_rec     agent_payouts;
BEGIN
  -- Get all earned, unpaid commissions for this agent
  SELECT
    ARRAY_AGG(id), SUM(commission_amount), COUNT(*)
  INTO comm_ids, total_amount, booking_cnt
  FROM agent_commissions
  WHERE agent_id = p_agent_id AND status = 'earned' AND payout_id IS NULL;

  IF total_amount IS NULL OR total_amount = 0 THEN
    RAISE EXCEPTION 'No pending commissions for this agent';
  END IF;

  -- TDS: 5% if annual earnings > ₹15,000 (simplified: apply if payout > ₹5,000)
  IF total_amount > 5000 THEN
    tds_amount := ROUND(total_amount * 0.05, 2);
  END IF;

  net_amount := total_amount - tds_amount;

  -- Create payout record
  INSERT INTO agent_payouts
    (agent_id, amount, tds_deducted, net_amount, payout_status,
     utr_number, commission_ids, booking_count, notes, payout_date)
  VALUES
    (p_agent_id, total_amount, tds_amount, net_amount, 'completed',
     p_utr, comm_ids, booking_cnt, p_notes, CURRENT_DATE)
  RETURNING * INTO payout_rec;

  -- Mark commissions as paid
  UPDATE agent_commissions
  SET status = 'paid', payout_id = payout_rec.id
  WHERE id = ANY(comm_ids);

  -- Update agent paid stats
  UPDATE agents
  SET total_commission_paid = total_commission_paid + net_amount
  WHERE id = p_agent_id;

  RETURN payout_rec;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ────────────────────────────────────────────────────────────
-- 12. SYNC AGENT STATS FROM BOOKINGS
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION sync_agent_stats(p_agent_code TEXT)
RETURNS VOID AS $$
DECLARE
  agent_rec agents;
BEGIN
  SELECT * INTO agent_rec FROM agents WHERE agent_code = p_agent_code;
  IF NOT FOUND THEN RETURN; END IF;

  UPDATE agents
  SET
    total_bookings        = (SELECT COUNT(*) FROM bookings
                              WHERE booking_source = 'agent_' || p_agent_code),
    confirmed_bookings    = (SELECT COUNT(*) FROM bookings
                              WHERE booking_source = 'agent_' || p_agent_code
                                AND status IN ('confirmed','completed')),
    total_booking_value   = (SELECT COALESCE(SUM(total_amount),0) FROM bookings
                              WHERE booking_source = 'agent_' || p_agent_code
                                AND payment_status = 'paid'),
    total_commission_earned = (SELECT COALESCE(SUM(commission_amount),0)
                                FROM agent_commissions WHERE agent_id = agent_rec.id),
    total_commission_paid   = (SELECT COALESCE(SUM(commission_amount),0)
                                FROM agent_commissions WHERE agent_id = agent_rec.id AND status = 'paid'),
    last_active_at          = NOW()
  WHERE id = agent_rec.id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ────────────────────────────────────────────────────────────
-- 13. ADMIN VIEWS
-- ────────────────────────────────────────────────────────────

-- Full agent overview
CREATE OR REPLACE VIEW v_agents_overview AS
SELECT
  a.id, a.agent_code, a.full_name, a.email, a.phone, a.city,
  a.tier, a.status, a.commission_rate,
  a.total_bookings, a.confirmed_bookings,
  a.total_booking_value,
  a.total_commission_earned,
  a.total_commission_paid,
  GREATEST(0, a.total_commission_earned - a.total_commission_paid) AS pending_payout,
  (SELECT COUNT(*) FROM agents sub WHERE sub.parent_agent_id = a.id) AS sub_agent_count,
  a.affiliate_clicks, a.affiliate_conversions,
  CASE WHEN a.affiliate_clicks > 0
    THEN ROUND((a.affiliate_conversions::NUMERIC / a.affiliate_clicks) * 100, 1)
    ELSE 0 END AS conversion_rate_pct,
  a.created_at, a.last_active_at
FROM agents a
ORDER BY a.total_commission_earned DESC NULLS LAST;

-- Pending payouts summary
CREATE OR REPLACE VIEW v_agent_payouts_pending AS
SELECT
  a.id AS agent_id, a.agent_code, a.full_name, a.email, a.phone,
  a.bank_acc_name, a.bank_acc_num, a.bank_ifsc, a.bank_name,
  a.tier,
  COALESCE(SUM(ac.commission_amount),0)              AS pending_amount,
  COUNT(ac.id)                                       AS commission_count,
  CASE WHEN SUM(ac.commission_amount) > 5000
    THEN ROUND(SUM(ac.commission_amount) * 0.05, 2) ELSE 0 END AS tds_amount,
  CASE WHEN SUM(ac.commission_amount) > 5000
    THEN SUM(ac.commission_amount) - ROUND(SUM(ac.commission_amount) * 0.05, 2)
    ELSE SUM(ac.commission_amount) END                AS net_payout
FROM agents a
LEFT JOIN agent_commissions ac
  ON ac.agent_id = a.id AND ac.status = 'earned' AND ac.payout_id IS NULL
WHERE a.status = 'active'
GROUP BY a.id, a.agent_code, a.full_name, a.email, a.phone,
         a.bank_acc_name, a.bank_acc_num, a.bank_ifsc, a.bank_name, a.tier
HAVING COALESCE(SUM(ac.commission_amount), 0) >= 500  -- min payout threshold
ORDER BY pending_amount DESC;

-- Top agents leaderboard
CREATE OR REPLACE VIEW v_agent_leaderboard AS
SELECT
  ROW_NUMBER() OVER (ORDER BY total_commission_earned DESC) AS rank,
  agent_code, full_name, city, tier,
  total_bookings, confirmed_bookings, total_booking_value,
  total_commission_earned
FROM agents
WHERE status = 'active'
ORDER BY total_commission_earned DESC
LIMIT 50;

-- Monthly commission report
CREATE OR REPLACE VIEW v_agent_monthly_report AS
SELECT
  DATE_TRUNC('month', ac.created_at)                 AS month,
  a.agent_code, a.full_name, a.tier,
  COUNT(ac.id)                                       AS bookings,
  SUM(ac.booking_amount)                             AS booking_value,
  SUM(ac.commission_amount)                          AS commission_earned,
  COUNT(*) FILTER (WHERE ac.status = 'paid')         AS paid_commissions,
  SUM(ac.commission_amount) FILTER (WHERE ac.status = 'paid') AS commission_paid
FROM agent_commissions ac
JOIN agents a ON a.id = ac.agent_id
GROUP BY DATE_TRUNC('month', ac.created_at), a.agent_code, a.full_name, a.tier
ORDER BY month DESC, commission_earned DESC;


-- ────────────────────────────────────────────────────────────
-- 14. ROW LEVEL SECURITY
-- ────────────────────────────────────────────────────────────
ALTER TABLE agents             ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_commissions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_payouts      ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_clicks       ENABLE ROW LEVEL SECURITY;

-- Drop existing
DROP POLICY IF EXISTS "Agent view own"            ON agents;
DROP POLICY IF EXISTS "Agent update own"          ON agents;
DROP POLICY IF EXISTS "Agent insert own"          ON agents;
DROP POLICY IF EXISTS "Admin view all agents"     ON agents;
DROP POLICY IF EXISTS "Service role agents"       ON agents;
DROP POLICY IF EXISTS "Agent view own comms"      ON agent_commissions;
DROP POLICY IF EXISTS "Service role comms"        ON agent_commissions;
DROP POLICY IF EXISTS "Agent view own payouts"    ON agent_payouts;
DROP POLICY IF EXISTS "Service role payouts"      ON agent_payouts;
DROP POLICY IF EXISTS "Service role clicks"       ON agent_clicks;
DROP POLICY IF EXISTS "Anon insert clicks"        ON agent_clicks;

-- Agents policies
CREATE POLICY "Agent view own"      ON agents FOR SELECT USING (auth.uid()=user_id);
CREATE POLICY "Agent update own"    ON agents FOR UPDATE USING (auth.uid()=user_id) WITH CHECK (auth.uid()=user_id);
CREATE POLICY "Agent insert own"    ON agents FOR INSERT WITH CHECK (auth.uid()=user_id);
CREATE POLICY "Service role agents" ON agents FOR ALL   USING (auth.role()='service_role');
CREATE POLICY "Admin view all agents" ON agents FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id=auth.uid() AND profiles.role='admin'));

-- Commissions policies
CREATE POLICY "Agent view own comms" ON agent_commissions FOR SELECT
  USING (agent_id IN (SELECT id FROM agents WHERE user_id=auth.uid()));
CREATE POLICY "Service role comms"   ON agent_commissions FOR ALL USING (auth.role()='service_role');
CREATE POLICY "Admin view all comms" ON agent_commissions FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id=auth.uid() AND profiles.role='admin'));

-- Payouts policies
CREATE POLICY "Agent view own payouts" ON agent_payouts FOR SELECT
  USING (agent_id IN (SELECT id FROM agents WHERE user_id=auth.uid()));
CREATE POLICY "Service role payouts"   ON agent_payouts FOR ALL USING (auth.role()='service_role');
CREATE POLICY "Admin view all payouts" ON agent_payouts FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id=auth.uid() AND profiles.role='admin'));

-- Click tracking: anyone can insert (for affiliate tracking), service role for all
CREATE POLICY "Anon insert clicks"    ON agent_clicks FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "Service role clicks"   ON agent_clicks FOR ALL USING (auth.role()='service_role');
CREATE POLICY "Admin view clicks"     ON agent_clicks FOR SELECT
  USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id=auth.uid() AND profiles.role='admin'));


-- ────────────────────────────────────────────────────────────
-- 15. GRANTS
-- ────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE         ON agents            TO authenticated;
GRANT SELECT                         ON agent_commissions TO authenticated;
GRANT SELECT                         ON agent_payouts     TO authenticated;
GRANT INSERT                         ON agent_clicks      TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON agents            TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON agent_commissions TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON agent_payouts     TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON agent_clicks      TO service_role;

GRANT SELECT ON v_agents_overview     TO authenticated;
GRANT SELECT ON v_agent_payouts_pending TO authenticated;
GRANT SELECT ON v_agent_leaderboard   TO authenticated;
GRANT SELECT ON v_agent_monthly_report TO authenticated;

GRANT EXECUTE ON FUNCTION record_agent_commission(UUID,TEXT,NUMERIC,TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION process_agent_payout(UUID,TEXT,TEXT)            TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION sync_agent_stats(TEXT)                          TO authenticated, service_role;


-- ────────────────────────────────────────────────────────────
-- 16. AFFILIATE LINK TRACKER (Edge Function call or JS snippet)
-- ────────────────────────────────────────────────────────────
-- Add this to your site's <head> to track affiliate visits:
/*
<script>
  (function() {
    const params = new URLSearchParams(window.location.search);
    const agentCode = params.get('agent');
    if (agentCode) {
      // Store in cookie for 30 days
      document.cookie = `zf_agent=${agentCode}; max-age=${30*24*3600}; path=/; SameSite=Lax`;
      // Track click in DB
      fetch('https://yourproject.supabase.co/rest/v1/agent_clicks', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': 'YOUR_ANON_KEY',
          'Authorization': 'Bearer YOUR_ANON_KEY'
        },
        body: JSON.stringify({
          agent_code: agentCode,
          page: window.location.pathname,
          user_agent: navigator.userAgent.slice(0, 200)
        })
      });
    }
    // Expose agent code getter for booking forms
    window.getAgentCode = function() {
      const match = document.cookie.match(/zf_agent=([^;]+)/);
      return match ? match[1] : null;
    };
  })();
</script>
*/

-- ────────────────────────────────────────────────────────────
-- 17. SAMPLE AGENT DATA (comment out before production)
-- ────────────────────────────────────────────────────────────
/*
INSERT INTO agents (
  full_name, email, phone, city, agent_code,
  tier, status, commission_rate, experience,
  total_bookings, confirmed_bookings, total_booking_value, total_commission_earned
) VALUES
(
  'Priya Sharma', 'priya.sharma@gmail.com', '9876543210', 'New Delhi',
  'ZFAPRI123', 'senior', 'active', 7.00, '3-5',
  87, 72, 850000, 59500
),
(
  'Amit Verma', 'amit.verma@gmail.com', '9812345678', 'Mumbai',
  'ZFAAMI456', 'associate', 'active', 5.00, '1-3',
  23, 18, 180000, 9000
),
(
  'Sunita Rawat', 'sunita.rawat@gmail.com', '9871234567', 'Dehradun',
  'ZFASUN789', 'elite', 'active', 10.00, '5+',
  312, 280, 4200000, 420000
);
*/


-- ────────────────────────────────────────────────────────────
-- DONE ✅
--
-- Tables:    agents, agent_commissions, agent_payouts, agent_clicks
-- Enums:     agent_tier, agent_status, payout_status
-- Triggers:  auto updated_at, auto agent_code, auto tier upgrade
-- Functions: record_agent_commission, process_agent_payout,
--            sync_agent_stats, generate_agent_code
-- Views:     v_agents_overview, v_agent_payouts_pending,
--            v_agent_leaderboard, v_agent_monthly_report
-- RLS:       agents see own, admins see all, anon can insert clicks
-- ────────────────────────────────────────────────────────────
