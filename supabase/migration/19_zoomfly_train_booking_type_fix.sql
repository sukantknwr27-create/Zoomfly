-- ============================================================
-- Migration: 19_zoomfly_train_booking_type_fix.sql
--
-- ROOT CAUSE: bookings_booking_type_check (00_zoomfly_master_schema.sql)
-- was defined as:
--   CHECK (booking_type IS NULL OR booking_type IN
--          ('package','hotel','flight','bus','cab'))
--
-- When migration 18 (rail booking) shipped, rail-create-booking/index.ts
-- was written to insert booking_type: 'train' — but 'train' was never
-- added to this constraint. Every train booking attempt has been
-- failing at the DB layer with:
--   "new row for relation "bookings" violates check constraint
--    "bookings_booking_type_check""
--
-- FIX: idempotent, targeted (per project convention) — drop and
-- recreate the constraint with 'train' included. Safe to run on the
-- live DB; does not touch existing rows (all pre-existing values are
-- already within the allowed set).
-- ============================================================

ALTER TABLE public.bookings DROP CONSTRAINT IF EXISTS bookings_booking_type_check;
ALTER TABLE public.bookings ADD CONSTRAINT bookings_booking_type_check
  CHECK (booking_type IS NULL OR booking_type IN ('package','hotel','flight','bus','cab','train'));
