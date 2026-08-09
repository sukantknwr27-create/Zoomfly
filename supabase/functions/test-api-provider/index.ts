// ============================================================
// Supabase Edge Function: test-api-provider
// File: supabase/functions/test-api-provider/index.ts
// Deploy: npx supabase functions deploy test-api-provider
//
// Called by the admin panel's "Test Connection" button (API
// Providers tab). Loads ONE specific api_providers row by id
// (regardless of whether it's currently active), instantiates that
// provider directly against its stored credentials, and runs a
// single canned search — without touching what's live for real
// customer traffic. Records the result back onto that row
// (last_tested_at / last_test_status / last_test_message) so the
// admin panel can show it without a second round-trip.
//
// Deliberately does NOT flip is_active — testing a provider and
// activating it are two separate admin actions, so a failed test
// can never accidentally go live.
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

// Canned, always-valid test queries — a route/date that should
// return *something* from a working provider regardless of which
// consolidator is being tested.
const TEST_FLIGHT_PARAMS = {
  origin: 'DEL', destination: 'BOM',
  departDate: new Date(Date.now() + 7 * 86_400_000).toISOString().slice(0, 10),
  adults: 1, children: 0, infants: 0,
  cabinClass: 'economy' as const, tripType: 'one-way' as const,
};
const TEST_RAIL_PARAMS = {
  from: 'NDLS', to: 'HWH',
  date: new Date(Date.now() + 7 * 86_400_000).toISOString().slice(0, 10),
  quota: 'GN' as const,
};

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });

  try {
    const { providerId } = await req.json();
    if (!providerId) throw new Error('providerId is required.');

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    // Caller must be an admin — this function is only ever invoked
    // from admin.html with the admin's own JWT forwarded, and
    // service-role bypasses this check entirely (used by nothing
    // else today, but kept for defense-in-depth).
    //
    // FIXED: this used to be `if (user) { ...check role... }` — when
    // there was no valid user at all (missing/invalid Authorization
    // header), the admin check was skipped entirely rather than
    // failing closed, letting an unauthenticated caller trigger a
    // live test call against any configured supplier's stored
    // credentials and read back success/failure + error text. Both
    // "no user" and "user isn't an admin" must now reject.
    const authHeader = req.headers.get('Authorization');
    const { data: { user } } = await supabase.auth.getUser(authHeader?.replace('Bearer ', '') || '');
    if (!user) throw new Error('Authentication required.');
    const { data: profile } = await supabase.from('profiles').select('role').eq('id', user.id).maybeSingle();
    if (profile?.role !== 'admin') throw new Error('Admin access required.');

    const { data: row, error: rowError } = await supabase
      .from('api_providers').select('*').eq('id', providerId).single();
    if (rowError || !row) throw new Error('Provider configuration not found.');

    let success = false;
    let message = '';
    const startedAt = Date.now();

    try {
      if (row.service_type === 'flight') {
        let instance;
        if (row.provider_key === 'mock') {
          const { MockFlightProvider } = await import('../_shared/flight-provider.ts');
          instance = new MockFlightProvider();
        } else {
          const mod = await import(`../_shared/providers/${row.provider_key}-flight.ts`);
          const ClassName = Object.keys(mod).find(k => k.endsWith('FlightProvider'));
          instance = new mod[ClassName!](row.credentials || {}, row.config || {});
        }
        const results = await instance.search(TEST_FLIGHT_PARAMS);
        success = Array.isArray(results);
        message = success ? `Search returned ${results.length} result(s) in ${Date.now() - startedAt}ms.` : 'Search returned no usable results.';
      } else if (row.service_type === 'rail') {
        let instance;
        if (row.provider_key === 'mock') {
          const { MockRailProvider } = await import('../_shared/rail-provider.ts');
          instance = new MockRailProvider();
        } else {
          const mod = await import(`../_shared/providers/${row.provider_key}-rail.ts`);
          const ClassName = Object.keys(mod).find(k => k.endsWith('RailProvider'));
          instance = new mod[ClassName!](row.credentials || {}, row.config || {});
        }
        const results = await instance.search(TEST_RAIL_PARAMS);
        success = Array.isArray(results);
        message = success ? `Search returned ${results.length} result(s) in ${Date.now() - startedAt}ms.` : 'Search returned no usable results.';
      } else {
        throw new Error(`Testing service_type "${row.service_type}" is not supported yet.`);
      }
    } catch (testErr) {
      success = false;
      message = testErr instanceof Error ? (testErr.message || String(testErr)) : String(testErr);
    }

    await supabase.from('api_providers').update({
      last_tested_at: new Date().toISOString(),
      last_test_status: success ? 'success' : 'failed',
      last_test_message: message,
    }).eq('id', providerId);

    return new Response(JSON.stringify({ success, message }), {
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });

  } catch (err) {
    return new Response(JSON.stringify({ success: false, message: err instanceof Error ? err.message : String(err) }), {
      status: 400,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }
});
