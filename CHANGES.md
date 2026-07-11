# Changes in this package vs. your original upload

## Removed (superseded — see below)
- `zoomfly-final-fix.sql`
- `supabase/setup-new-features.sql`
- `supabase/migrations/001_schema.sql`
- `supabase/migrations/002_audit_fixes.sql`
- `supabase/migrations/003_security_hardening.sql`
- `supabase/migrations/zoomfly_admin_extras.sql`
- `supabase/migrations/zoomfly_agents_schema_fixed.sql`
- `supabase/migrations/zoomfly_bookings_schema_fixed.sql`
- `supabase/migrations/zoomfly_loyalty_schema_fixed.sql`
- `supabase/migrations/zoomfly_vendors_schema_fixed.sql`
- `assets/og-image-README.txt` (no longer needed — the image now exists)

## Added
- `supabase/migrations/00_zoomfly_master_schema.sql` — single consolidated
  schema replacing all 10 files above, with several security fixes folded
  in (full detail in the file's own header comment):
  - Closed a profiles-role self-escalation hole (any user could make
    themselves admin)
  - Closed a hole letting anyone fabricate a "paid/confirmed" booking
    for free
  - Closed a public PII/financial leak in `payment_links`
  - Added internal authorization checks to 7 admin-only RPC functions
    that had none (`approve_vendor`, `confirm_payment`, etc.)
  - Stopped customers/vendors/agents from editing their own commission
    rate, tier, status, or loyalty points balance directly
  - Fixed the signup trigger trusting client-supplied role data
  - Fixed a broken "grant admin" block that referenced a non-existent
    column and an illegal role value
- `.gitignore` — wasn't present before; prevents committing `.env`, OS
  files, etc.
- `.env.example` — documents every environment variable your edge
  functions and `api/config.js` need, with no real values
- `assets/og-image.jpg` — was referenced by every page's meta tags but
  never actually created; generated in your site's brand colors

## Before you push
1. Run `supabase/migrations/00_zoomfly_master_schema.sql` against a
   **staging** Supabase project first and confirm the app still works.
2. Set the real secrets from `.env.example` in your Vercel and Supabase
   dashboards — never commit real values.
3. Edit the admin email list near the bottom of the master schema file
   (section 10) to match the account(s) you want as admin.
4. Read the "READ THIS FIRST" block at the top of the master schema —
   it documents a real schema-drift issue (bookings/vendors tables were
   each defined twice under different column names) that's preserved
   for compatibility but worth cleaning up in a future session.
