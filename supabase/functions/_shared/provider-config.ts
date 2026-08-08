// ============================================================
// Shared module: provider-config.ts
// File: supabase/functions/_shared/provider-config.ts
//
// Reads which supplier API is currently active for a given service
// (flight, rail, hotel, bus, cab) from the `api_providers` table
// (see 17_zoomfly_api_providers.sql) instead of a Deno environment
// variable. This is what lets an admin switch providers, add a new
// one, or update credentials from the admin panel — no redeploy.
//
// Every consumer (flight-provider.ts, rail-provider.ts, and any
// future *-provider.ts) calls getActiveProviderConfigs() and picks
// configs[0] as primary; additional entries (ordered by `priority`)
// are there for a future fallback chain (e.g. try Tripjack, then TBO
// if Tripjack's call fails) — not wired into the search/booking
// flows yet, but the data shape already supports it.
// ============================================================

export interface ProviderConfigRow {
  provider_key: string;
  display_name: string;
  credentials: Record<string, string>;
  config: Record<string, unknown>;
  priority: number;
}

const _cache = new Map<string, { rows: ProviderConfigRow[]; fetchedAt: number }>();
const CACHE_TTL_MS = 30_000; // short TTL: admin toggling a provider should take effect within ~30s, not require a redeploy AND not require a DB round-trip on every single request either

export async function getActiveProviderConfigs(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  serviceType: 'flight' | 'rail' | 'hotel' | 'bus' | 'cab'
): Promise<ProviderConfigRow[]> {
  const cached = _cache.get(serviceType);
  if (cached && Date.now() - cached.fetchedAt < CACHE_TTL_MS) {
    return cached.rows;
  }

  const { data, error } = await supabase
    .from('api_providers')
    .select('provider_key, display_name, credentials, config, priority')
    .eq('service_type', serviceType)
    .eq('is_active', true)
    .order('priority', { ascending: true });

  if (error) {
    console.error(`[provider-config] lookup failed for service_type=${serviceType}:`, error.message);
    // Don't cache a failed lookup — retry on next call rather than
    // pinning every request to "no provider" for 30 seconds because
    // of one transient DB error.
    return cached?.rows || [];
  }

  const rows = (data || []) as ProviderConfigRow[];
  _cache.set(serviceType, { rows, fetchedAt: Date.now() });
  return rows;
}
