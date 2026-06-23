-- ============================================================
--  ZOOMFLY AGENTS SCHEMA - FIXED (No ENUM conflicts)
--  Uses TEXT columns instead of ENUM types
--  Run this in Supabase SQL Editor
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Agents table
CREATE TABLE IF NOT EXISTS agents (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID UNIQUE,
  full_name       TEXT NOT NULL DEFAULT '',
  email           TEXT NOT NULL DEFAULT '',
  phone           TEXT NOT NULL DEFAULT '',
  whatsapp        TEXT,
  city            TEXT,
  state           TEXT,
  pan             TEXT,
  agent_code      TEXT UNIQUE NOT NULL DEFAULT 'ZFA000000',
  tier            TEXT NOT NULL DEFAULT 'associate',
  status          TEXT NOT NULL DEFAULT 'active',
  experience      TEXT,
  commission_rate NUMERIC(5,2) DEFAULT 5.00,
  parent_agent_id UUID,
  sub_agent_commission NUMERIC(5,2) DEFAULT 1.00,
  bank_acc_name   TEXT,
  bank_acc_num    TEXT,
  bank_ifsc       TEXT,
  bank_name       TEXT,
  bank_branch     TEXT,
  total_bookings        INTEGER DEFAULT 0,
  confirmed_bookings    INTEGER DEFAULT 0,
  total_booking_value   NUMERIC(14,2) DEFAULT 0,
  total_commission_earned NUMERIC(14,2) DEFAULT 0,
  total_commission_paid   NUMERIC(14,2) DEFAULT 0,
  affiliate_clicks      INTEGER DEFAULT 0,
  affiliate_conversions INTEGER DEFAULT 0,
  internal_notes  TEXT,
  approved_by     TEXT,
  approved_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_active_at  TIMESTAMPTZ
);

-- Add missing columns safely
DO $$ BEGIN ALTER TABLE agents ADD COLUMN user_id UUID UNIQUE; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN full_name TEXT NOT NULL DEFAULT ''; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN email TEXT NOT NULL DEFAULT ''; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN phone TEXT NOT NULL DEFAULT ''; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN whatsapp TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN city TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN pan TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN agent_code TEXT UNIQUE; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN tier TEXT NOT NULL DEFAULT 'associate'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN status TEXT NOT NULL DEFAULT 'active'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN experience TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN commission_rate NUMERIC(5,2) DEFAULT 5.00; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN parent_agent_id UUID; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN sub_agent_commission NUMERIC(5,2) DEFAULT 1.00; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN bank_acc_name TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN bank_acc_num TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN bank_ifsc TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN bank_name TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN total_bookings INTEGER DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN confirmed_bookings INTEGER DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN total_booking_value NUMERIC(14,2) DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN total_commission_earned NUMERIC(14,2) DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN total_commission_paid NUMERIC(14,2) DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN affiliate_clicks INTEGER DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN affiliate_conversions INTEGER DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN internal_notes TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN approved_by TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN approved_at TIMESTAMPTZ; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(); EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agents ADD COLUMN last_active_at TIMESTAMPTZ; EXCEPTION WHEN duplicate_column THEN NULL; END $$;

-- Agent commissions table
CREATE TABLE IF NOT EXISTS agent_commissions (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  agent_id         UUID NOT NULL,
  booking_id       UUID,
  booking_ref      TEXT NOT NULL DEFAULT '',
  booking_amount   NUMERIC(12,2) NOT NULL DEFAULT 0,
  commission_rate  NUMERIC(5,2) NOT NULL DEFAULT 5,
  commission_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  parent_agent_id  UUID,
  parent_commission NUMERIC(12,2) DEFAULT 0,
  status           TEXT NOT NULL DEFAULT 'pending',
  payout_id        UUID,
  notes            TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add missing columns for agent_commissions
DO $$ BEGIN ALTER TABLE agent_commissions ADD COLUMN agent_id UUID NOT NULL DEFAULT uuid_generate_v4(); EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agent_commissions ADD COLUMN booking_id UUID; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agent_commissions ADD COLUMN booking_ref TEXT NOT NULL DEFAULT ''; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agent_commissions ADD COLUMN booking_amount NUMERIC(12,2) NOT NULL DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agent_commissions ADD COLUMN commission_rate NUMERIC(5,2) NOT NULL DEFAULT 5; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agent_commissions ADD COLUMN commission_amount NUMERIC(12,2) NOT NULL DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agent_commissions ADD COLUMN parent_agent_id UUID; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agent_commissions ADD COLUMN parent_commission NUMERIC(12,2) DEFAULT 0; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agent_commissions ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agent_commissions ADD COLUMN payout_id UUID; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agent_commissions ADD COLUMN notes TEXT; EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE agent_commissions ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(); EXCEPTION WHEN duplicate_column THEN NULL; END $$;

-- Agent payouts table
CREATE TABLE IF NOT EXISTS agent_payouts (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  agent_id      UUID NOT NULL,
  amount        NUMERIC(12,2) NOT NULL DEFAULT 0,
  tds_deducted  NUMERIC(12,2) NOT NULL DEFAULT 0,
  net_amount    NUMERIC(12,2) NOT NULL DEFAULT 0,
  payout_status TEXT NOT NULL DEFAULT 'pending',
  payout_method TEXT DEFAULT 'neft',
  utr_number    TEXT,
  payout_date   DATE,
  commission_ids UUID[],
  booking_count INTEGER DEFAULT 0,
  processed_by  TEXT,
  notes         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Agent clicks table
CREATE TABLE IF NOT EXISTS agent_clicks (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  agent_code  TEXT NOT NULL,
  page        TEXT,
  ip_hash     TEXT,
  user_agent  TEXT,
  converted   BOOLEAN DEFAULT FALSE,
  booking_ref TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto updated_at triggers
CREATE OR REPLACE FUNCTION agents_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at:=NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_agents_updated_at ON agents;
CREATE TRIGGER trg_agents_updated_at BEFORE UPDATE ON agents FOR EACH ROW EXECUTE FUNCTION agents_updated_at();

DROP TRIGGER IF EXISTS trg_acomm_updated_at ON agent_commissions;
CREATE TRIGGER trg_acomm_updated_at BEFORE UPDATE ON agent_commissions FOR EACH ROW EXECUTE FUNCTION agents_updated_at();

DROP TRIGGER IF EXISTS trg_apayout_updated_at ON agent_payouts;
CREATE TRIGGER trg_apayout_updated_at BEFORE UPDATE ON agent_payouts FOR EACH ROW EXECUTE FUNCTION agents_updated_at();

-- Auto generate agent code
CREATE OR REPLACE FUNCTION generate_agent_code()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.agent_code IS NULL OR NEW.agent_code = '' OR NEW.agent_code = 'ZFA000000' THEN
    NEW.agent_code := 'ZFA' || UPPER(SUBSTRING(MD5(COALESCE(NEW.user_id::TEXT,'') || NOW()::TEXT),1,6));
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_generate_agent_code ON agents;
CREATE TRIGGER trg_generate_agent_code BEFORE INSERT ON agents FOR EACH ROW EXECUTE FUNCTION generate_agent_code();

-- Auto upgrade tier based on performance
CREATE OR REPLACE FUNCTION auto_upgrade_agent_tier()
RETURNS TRIGGER AS $$
DECLARE new_tier TEXT; new_rate NUMERIC(5,2);
BEGIN
  IF (NEW.confirmed_bookings IS NOT DISTINCT FROM OLD.confirmed_bookings) AND
     (NEW.total_booking_value IS NOT DISTINCT FROM OLD.total_booking_value) THEN
    RETURN NEW;
  END IF;
  new_tier := CASE
    WHEN NEW.confirmed_bookings >= 200 OR NEW.total_booking_value >= 2500000 THEN 'elite'
    WHEN NEW.confirmed_bookings >= 50  OR NEW.total_booking_value >= 500000  THEN 'senior'
    ELSE 'associate'
  END;
  new_rate := CASE new_tier WHEN 'elite' THEN 10.00 WHEN 'senior' THEN 7.00 ELSE 5.00 END;
  IF new_tier != OLD.tier THEN
    NEW.tier := new_tier;
    NEW.commission_rate := new_rate;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auto_upgrade_tier ON agents;
CREATE TRIGGER trg_auto_upgrade_tier BEFORE UPDATE ON agents FOR EACH ROW EXECUTE FUNCTION auto_upgrade_agent_tier();

-- Indexes
CREATE INDEX IF NOT EXISTS idx_agents_user_id    ON agents(user_id);
CREATE INDEX IF NOT EXISTS idx_agents_code       ON agents(agent_code);
CREATE INDEX IF NOT EXISTS idx_agents_tier       ON agents(tier);
CREATE INDEX IF NOT EXISTS idx_agents_status     ON agents(status);
CREATE INDEX IF NOT EXISTS idx_acomm_agent_id    ON agent_commissions(agent_id);
CREATE INDEX IF NOT EXISTS idx_acomm_booking_ref ON agent_commissions(booking_ref);
CREATE INDEX IF NOT EXISTS idx_acomm_status      ON agent_commissions(status);
CREATE INDEX IF NOT EXISTS idx_apayout_agent_id  ON agent_payouts(agent_id);
CREATE INDEX IF NOT EXISTS idx_agent_clicks_code ON agent_clicks(agent_code);
CREATE INDEX IF NOT EXISTS idx_agent_clicks_date ON agent_clicks(created_at DESC);

-- Record commission function
CREATE OR REPLACE FUNCTION record_agent_commission(
  p_booking_id UUID, p_booking_ref TEXT,
  p_booking_amount NUMERIC, p_agent_code TEXT
)
RETURNS agent_commissions AS $$
DECLARE
  agent_rec    agents;
  comm_amount  NUMERIC;
  parent_comm  NUMERIC := 0;
  result       agent_commissions;
BEGIN
  SELECT * INTO agent_rec FROM agents WHERE agent_code=p_agent_code AND status='active';
  IF NOT FOUND THEN RETURN NULL; END IF;
  comm_amount := ROUND(p_booking_amount*(agent_rec.commission_rate/100.0),2);
  IF agent_rec.parent_agent_id IS NOT NULL THEN
    parent_comm := ROUND(p_booking_amount*(agent_rec.sub_agent_commission/100.0),2);
  END IF;
  INSERT INTO agent_commissions (agent_id, booking_id, booking_ref, booking_amount, commission_rate, commission_amount, parent_agent_id, parent_commission, status)
  VALUES (agent_rec.id, p_booking_id, p_booking_ref, p_booking_amount, agent_rec.commission_rate, comm_amount, agent_rec.parent_agent_id, parent_comm, 'earned')
  RETURNING * INTO result;
  UPDATE agents SET confirmed_bookings=confirmed_bookings+1, total_booking_value=total_booking_value+p_booking_amount,
    total_commission_earned=total_commission_earned+comm_amount, last_active_at=NOW()
  WHERE id=agent_rec.id;
  RETURN result;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

-- Sync agent stats
CREATE OR REPLACE FUNCTION sync_agent_stats(p_agent_code TEXT)
RETURNS VOID AS $$
DECLARE agent_rec agents;
BEGIN
  SELECT * INTO agent_rec FROM agents WHERE agent_code=p_agent_code;
  IF NOT FOUND THEN RETURN; END IF;
  UPDATE agents SET
    total_bookings=(SELECT COUNT(*) FROM bookings WHERE booking_source='agent_'||p_agent_code),
    confirmed_bookings=(SELECT COUNT(*) FROM bookings WHERE booking_source='agent_'||p_agent_code AND status IN ('confirmed','completed')),
    total_booking_value=(SELECT COALESCE(SUM(total_amount),0) FROM bookings WHERE booking_source='agent_'||p_agent_code AND payment_status='paid'),
    total_commission_earned=(SELECT COALESCE(SUM(commission_amount),0) FROM agent_commissions WHERE agent_id=agent_rec.id),
    total_commission_paid=(SELECT COALESCE(SUM(commission_amount),0) FROM agent_commissions WHERE agent_id=agent_rec.id AND status='paid'),
    last_active_at=NOW()
  WHERE id=agent_rec.id;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

-- Admin views
CREATE OR REPLACE VIEW v_agents_overview AS
SELECT a.id, a.agent_code, a.full_name, a.email, a.phone, a.city, a.tier, a.status,
  a.commission_rate, a.total_bookings, a.confirmed_bookings, a.total_booking_value,
  a.total_commission_earned, a.total_commission_paid,
  GREATEST(0, a.total_commission_earned-a.total_commission_paid) AS pending_payout,
  a.affiliate_clicks, a.affiliate_conversions,
  a.created_at, a.last_active_at
FROM agents a ORDER BY a.total_commission_earned DESC NULLS LAST;

CREATE OR REPLACE VIEW v_agent_payouts_pending AS
SELECT a.id AS agent_id, a.agent_code, a.full_name, a.email, a.phone,
  a.bank_acc_name, a.bank_acc_num, a.bank_ifsc, a.bank_name, a.tier,
  COALESCE(SUM(ac.commission_amount),0) AS pending_amount,
  COUNT(ac.id) AS commission_count,
  CASE WHEN SUM(ac.commission_amount) > 5000 THEN ROUND(SUM(ac.commission_amount)*0.05,2) ELSE 0 END AS tds_amount,
  CASE WHEN SUM(ac.commission_amount) > 5000 THEN SUM(ac.commission_amount)-ROUND(SUM(ac.commission_amount)*0.05,2)
  ELSE SUM(ac.commission_amount) END AS net_payout
FROM agents a
LEFT JOIN agent_commissions ac ON ac.agent_id=a.id AND ac.status='earned' AND ac.payout_id IS NULL
WHERE a.status='active'
GROUP BY a.id, a.agent_code, a.full_name, a.email, a.phone,
  a.bank_acc_name, a.bank_acc_num, a.bank_ifsc, a.bank_name, a.tier
HAVING COALESCE(SUM(ac.commission_amount),0) >= 500
ORDER BY pending_amount DESC;

CREATE OR REPLACE VIEW v_agent_leaderboard AS
SELECT ROW_NUMBER() OVER (ORDER BY total_commission_earned DESC) AS rank,
  agent_code, full_name, city, tier, total_bookings, confirmed_bookings,
  total_booking_value, total_commission_earned
FROM agents WHERE status='active'
ORDER BY total_commission_earned DESC LIMIT 50;

-- RLS
ALTER TABLE agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_commissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_payouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_clicks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Agent view own"          ON agents;
DROP POLICY IF EXISTS "Agent update own"        ON agents;
DROP POLICY IF EXISTS "Agent insert own"        ON agents;
DROP POLICY IF EXISTS "Service role agents"     ON agents;
DROP POLICY IF EXISTS "Admin view all agents"   ON agents;
DROP POLICY IF EXISTS "Agent view own comms"    ON agent_commissions;
DROP POLICY IF EXISTS "Service role comms"      ON agent_commissions;
DROP POLICY IF EXISTS "Admin view all comms"    ON agent_commissions;
DROP POLICY IF EXISTS "Agent view own payouts"  ON agent_payouts;
DROP POLICY IF EXISTS "Service role payouts"    ON agent_payouts;
DROP POLICY IF EXISTS "Admin view all payouts"  ON agent_payouts;
DROP POLICY IF EXISTS "Anon insert clicks"      ON agent_clicks;
DROP POLICY IF EXISTS "Service role clicks"     ON agent_clicks;
DROP POLICY IF EXISTS "Admin view clicks"       ON agent_clicks;

CREATE POLICY "Agent view own"          ON agents FOR SELECT USING (auth.uid()=user_id);
CREATE POLICY "Agent update own"        ON agents FOR UPDATE USING (auth.uid()=user_id) WITH CHECK (auth.uid()=user_id);
CREATE POLICY "Agent insert own"        ON agents FOR INSERT WITH CHECK (auth.uid()=user_id);
CREATE POLICY "Service role agents"     ON agents FOR ALL USING (auth.role()='service_role');
CREATE POLICY "Admin view all agents"   ON agents FOR ALL USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id=auth.uid() AND profiles.role='admin'));
CREATE POLICY "Agent view own comms"    ON agent_commissions FOR SELECT USING (agent_id IN (SELECT id FROM agents WHERE user_id=auth.uid()));
CREATE POLICY "Service role comms"      ON agent_commissions FOR ALL USING (auth.role()='service_role');
CREATE POLICY "Admin view all comms"    ON agent_commissions FOR ALL USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id=auth.uid() AND profiles.role='admin'));
CREATE POLICY "Agent view own payouts"  ON agent_payouts FOR SELECT USING (agent_id IN (SELECT id FROM agents WHERE user_id=auth.uid()));
CREATE POLICY "Service role payouts"    ON agent_payouts FOR ALL USING (auth.role()='service_role');
CREATE POLICY "Admin view all payouts"  ON agent_payouts FOR ALL USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id=auth.uid() AND profiles.role='admin'));
CREATE POLICY "Anon insert clicks"      ON agent_clicks FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "Service role clicks"     ON agent_clicks FOR ALL USING (auth.role()='service_role');
CREATE POLICY "Admin view clicks"       ON agent_clicks FOR SELECT USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id=auth.uid() AND profiles.role='admin'));

-- Grants
GRANT SELECT, INSERT, UPDATE ON agents TO authenticated;
GRANT SELECT ON agent_commissions TO authenticated;
GRANT SELECT ON agent_payouts TO authenticated;
GRANT INSERT ON agent_clicks TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON agents TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON agent_commissions TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON agent_payouts TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON agent_clicks TO service_role;
GRANT SELECT ON v_agents_overview TO authenticated;
GRANT SELECT ON v_agent_payouts_pending TO authenticated;
GRANT SELECT ON v_agent_leaderboard TO authenticated;
GRANT EXECUTE ON FUNCTION record_agent_commission(UUID,TEXT,NUMERIC,TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION sync_agent_stats(TEXT) TO authenticated, service_role;

-- DONE
