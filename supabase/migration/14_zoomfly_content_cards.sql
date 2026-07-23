-- ================================================================
-- ZoomFly — 14_zoomfly_content_cards.sql
-- Run AFTER 00–13, against STAGING first.
--
-- What this file does:
--   Adds ONE reusable table for the small icon+title+description card
--   grids that were hardcoded across several pages with no admin hook:
--     - careers.html          "Why Join Our Team" perks (6 cards)
--     - group-booking.html    "Why Book as a Group" benefit cards (6 cards)
--     - group-booking.html    "Complete Group Travel Services" cards (6 cards, each with a badge)
--     - about.html            "Our Values" cards (6 cards)
--   One table + one admin panel covers all four instead of building
--   four near-identical CRUD sections.
--
--   NOT included here: the "4.8 Customer Rating" / "98% Confirmation
--   Rate" stats on about.html — those were fabricated numbers with no
--   real data behind them, which conflicts with this project's
--   honest-first principle. Rather than making a fake number editable,
--   about.html has been changed to compute both from real `reviews`
--   and `bookings` data instead (see accompanying changelog). No schema
--   change needed for that — it's a page-level fix only.
-- ================================================================

CREATE TABLE IF NOT EXISTS public.content_cards (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  page_key     TEXT NOT NULL,              -- 'careers_perks' | 'group_booking_benefits' | 'group_booking_services' | 'about_values'
  icon         TEXT DEFAULT '✅',           -- emoji shown as the card icon
  title        TEXT NOT NULL,
  description  TEXT,
  badge        TEXT,                       -- optional small tag, e.g. "Up to 20% off" (used by group_booking_services only)
  sort_order   INTEGER NOT NULL DEFAULT 0,
  is_published BOOLEAN NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_content_cards_page ON public.content_cards(page_key, sort_order);

-- Prevents duplicate rows if this migration (or its seed section) is
-- run more than once — matches the idempotent-migration pattern used
-- throughout this project. (CREATE UNIQUE INDEX IF NOT EXISTS is used
-- instead of ADD CONSTRAINT because Postgres has no
-- "ADD CONSTRAINT IF NOT EXISTS" — this index still satisfies
-- ON CONFLICT (page_key, title) below.)
CREATE UNIQUE INDEX IF NOT EXISTS idx_content_cards_page_title_uniq ON public.content_cards(page_key, title);

ALTER TABLE public.content_cards ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS content_cards_public_read ON public.content_cards;
CREATE POLICY content_cards_public_read ON public.content_cards
  FOR SELECT USING (is_published = TRUE OR public.is_admin());

DROP POLICY IF EXISTS content_cards_admin_all ON public.content_cards;
CREATE POLICY content_cards_admin_all ON public.content_cards
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ----------------------------------------------------------------
-- PUBLIC AGGREGATE RPC — about.html's "Confirmation Rate" stat needs
-- a real number, but public.bookings' RLS (correctly) only lets a user
-- see their own bookings, so a plain anon SELECT always returns zero
-- rows for a logged-out visitor — which is most of this page's traffic.
-- This function returns ONLY the aggregate percentage (no booking rows,
-- no PII) so the real number can be shown without loosening bookings'
-- row-level security.
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_booking_confirmation_rate()
RETURNS TABLE(confirmation_rate INT, sample_size INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  total INT;
  confirmed INT;
BEGIN
  SELECT COUNT(*) INTO total FROM public.bookings WHERE status IN ('confirmed','completed','cancelled');
  SELECT COUNT(*) INTO confirmed FROM public.bookings WHERE status IN ('confirmed','completed');
  IF total = 0 THEN
    RETURN QUERY SELECT NULL::INT, 0;
  ELSE
    RETURN QUERY SELECT ROUND(confirmed::NUMERIC / total * 100)::INT, total;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_booking_confirmation_rate() TO anon, authenticated;

-- ----------------------------------------------------------------
-- SEED DATA — migrates the exact hardcoded content that was on each
-- page, so turning on the dynamic fetch doesn't change anything
-- visually until an admin edits these in the admin panel.
-- ----------------------------------------------------------------

INSERT INTO public.content_cards (page_key, icon, title, description, sort_order) VALUES
('careers_perks', '🎁', 'Travel Benefits',   'Discounted packages and flights for you and your family every year.', 1),
('careers_perks', '⏱️', 'Fast Growth',       'Clear career paths with quarterly performance reviews and promotions.', 2),
('careers_perks', '✅', 'Remote Friendly',   'Hybrid work options with flexible hours and WFH days every week.', 3),
('careers_perks', '✅', 'Competitive Pay',   'Market-leading salaries, ESOPs, and performance bonuses every quarter.', 4),
('careers_perks', '💰', 'Learning Budget',   '₹30,000 annual budget for courses, conferences, and certifications.', 5),
('careers_perks', '🛡️', 'Health Insurance',  'Full medical, dental, and vision coverage for you and your family.', 6)
ON CONFLICT (page_key, title) DO NOTHING;

INSERT INTO public.content_cards (page_key, icon, title, description, sort_order) VALUES
('group_booking_benefits', '🏷️', 'Exclusive Group Rates',    'Get upto 30% off standard rates. The larger your group, the better the pricing. We negotiate directly with airlines and hotels.', 1),
('group_booking_benefits', '👤', 'Dedicated Coordinator',     'A single point of contact manages your entire booking — confirmations, changes, on-ground support, and emergency assistance.', 2),
('group_booking_benefits', '💳', 'Flexible Payment',         'Pay in instalments. Secure your booking with 25% advance and settle the balance 30 days before departure.', 3),
('group_booking_benefits', '✅', 'Block Seat Guarantee',      'We block seats together so your group travels on the same flight, same bus, or same hotel floor — nobody gets separated.', 4),
('group_booking_benefits', '📄', 'Custom Itineraries',        'Tailored day-by-day itineraries for your group type — corporate offsite, school trip, family reunion, or pilgrimage tour.', 5),
('group_booking_benefits', '🛡️', 'Group Travel Insurance',    'Optional group travel insurance covering medical emergencies, trip cancellation, and lost baggage for all members.', 6)
ON CONFLICT (page_key, title) DO NOTHING;

INSERT INTO public.content_cards (page_key, icon, title, description, badge, sort_order) VALUES
('group_booking_services', '👥', 'Group Flights',          'Block seating on domestic and international flights. We coordinate with airlines for adjacent seats and special meal requests.', 'Up to 20% off', 1),
('group_booking_services', '🏨', 'Hotel Blocks',           'Entire floors or wings blocked for groups. Special rates, combined check-in, and dedicated banquet/conference facilities.', 'Up to 30% off', 2),
('group_booking_services', '👥', 'Group Coaches',          'Luxury AC coaches for inter-city transfers. Volvo, Mercedes, and Tempo Travellers for groups of any size.', 'Up to 25% off', 3),
('group_booking_services', '✅', 'MICE Packages',          'Complete Meetings, Incentives, Conferences & Exhibitions packages including venue, accommodation, transfers, and F&B.', 'Custom pricing', 4),
('group_booking_services', '✅', 'Pilgrimage Tours',       'Dedicated packages for Char Dham, Vaishno Devi, Tirupati, Shirdi, Amritsar, and international pilgrimages.', 'Up to 20% off', 5),
('group_booking_services', '✅', 'School/College Trips',   'Educational tours with teacher coordination, safety protocols, child-friendly activities, and budget-friendly packages.', 'Up to 25% off', 6)
ON CONFLICT (page_key, title) DO NOTHING;

INSERT INTO public.content_cards (page_key, icon, title, description, sort_order) VALUES
('about_values', '✅', 'Customer First, Always',   'Every feature, every policy, every decision starts with one question: does this make life easier for our travellers? If not, we don''t build it.', 1),
('about_values', '✅', 'Radical Transparency',     'No hidden fees. No fine-print surprises. What you see is what you pay. We believe trust is built through honesty, not marketing.', 2),
('about_values', '✅', 'Built for Bharat',         'We design for all of India — not just metro cities. WhatsApp bookings, local language support, and affordable pricing for every pocket.', 3),
('about_values', '✅', 'Speed & Simplicity',       'Booking travel should take minutes, not hours. We obsess over reducing friction at every step of your journey from search to confirmation.', 4),
('about_values', '🛡️', 'Security You Can Trust',   'Your payments are secured by Razorpay. Your data is protected by Supabase. Your privacy is governed by Indian law and our strict policies.', 5),
('about_values', '🏆', 'Growing Together',         'We grow when our vendors grow and our customers return. We invest in long-term relationships, not short-term transactions.', 6)
ON CONFLICT (page_key, title) DO NOTHING;
