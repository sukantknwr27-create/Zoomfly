// ============================================================
// Supabase Edge Function: delete-customer-account
// File: supabase/functions/delete-customer-account/index.ts
// Deploy: npx supabase functions deploy delete-customer-account
//
// Full right-to-erasure delete for a customer: removes their Supabase
// Auth identity (login), not just their `profiles` row. Admin.html's
// client-side "Delete Customer" button only had the anon key and could
// never do this — deleting an auth.users row requires the
// service_role key, which only lives here, server-side.
//
// public.profiles.id REFERENCES auth.users(id) ON DELETE CASCADE, so
// deleting the auth user cascades the profile automatically, along
// with every other table whose user_id/booking-owner FK is already
// ON DELETE CASCADE (co_travellers, price_alerts, loyalty_accounts,
// loyalty_transactions, etc. — see 00_zoomfly_master_schema.sql).
//
// bookings.user_id is ON DELETE SET NULL, so past orders are KEPT for
// accounting/audit, just detached from the deleted identity — this is
// deliberate, matching how deleteCustomer() in admin.html already
// documented that bookings shouldn't disappear.
//
// A few older FK columns were added with no ON DELETE clause at all
// (default RESTRICT), which would make auth.admin.deleteUser() fail
// with a foreign-key error if the customer ever sent a chat message,
// had a payment link issued to them, or submitted a train enquiry
// while logged in. Rather than let that surface as a confusing
// Postgres error in the admin panel, this function nulls those FK
// columns out first (never deletes the rows — just detaches them from
// the identity being erased), then deletes the auth user.
// ============================================================

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const ALLOWED_ORIGINS = [
  'https://www.zoomfly.in',
  'https://zoomfly.in',
  'http://localhost:3000',
  'http://127.0.0.1:5500',
];

function corsHeaders(req: Request) {
  const origin = req.headers.get('origin') || '';
  const allowed = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    'Access-Control-Allow-Origin': allowed,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-application',
    'Vary': 'Origin',
  };
}

// Columns that reference auth.users(id) with no ON DELETE clause
// (default RESTRICT). Each is nullable — we detach, never delete the
// row itself. Add to this list if a future migration introduces
// another un-cascaded FK to auth.users.
const RESTRICT_FK_CLEANUPS: Array<{ table: string; column: string }> = [
  { table: 'payment_links', column: 'user_id' },
  { table: 'messages', column: 'sender_id' },
  { table: 'train_enquiries', column: 'user_id' },
  { table: 'reminder_log', column: 'sent_by' },
];

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });

  try {
    const { userId } = await req.json();
    if (!userId) throw new Error('userId is required.');

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    // Caller must be an admin — same fail-closed pattern used by
    // test-api-provider: both "no user" and "user isn't an admin"
    // are rejected before anything else runs.
    const authHeader = req.headers.get('Authorization');
    const { data: { user } } = await supabase.auth.getUser(authHeader?.replace('Bearer ', '') || '');
    if (!user) throw new Error('Authentication required.');
    const { data: callerProfile } = await supabase.from('profiles').select('role').eq('id', user.id).maybeSingle();
    if (callerProfile?.role !== 'admin') throw new Error('Admin access required.');

    // Refuse to let an admin delete their own account through this
    // customer-deletion tool — that's a footgun this function isn't
    // meant to enable.
    if (user.id === userId) throw new Error("Can't delete your own account through this tool.");

    // Detach RESTRICT-only FK references before the hard delete, so
    // one old chat message or payment link can't block the whole
    // erasure with an opaque foreign-key error.
    for (const { table, column } of RESTRICT_FK_CLEANUPS) {
      const { error: cleanupErr } = await supabase.from(table).update({ [column]: null }).eq(column, userId);
      // A missing table (e.g. reminder_log not yet migrated on an
      // older install) shouldn't block the delete — log and continue.
      if (cleanupErr && cleanupErr.code !== '42P01') {
        throw new Error(`Could not detach ${table}.${column}: ${cleanupErr.message}`);
      }
    }

    const { error: deleteErr } = await supabase.auth.admin.deleteUser(userId);
    if (deleteErr) throw deleteErr;

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });

  } catch (err) {
    return new Response(JSON.stringify({ success: false, message: err instanceof Error ? err.message : String(err) }), {
      status: 400,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }
});
