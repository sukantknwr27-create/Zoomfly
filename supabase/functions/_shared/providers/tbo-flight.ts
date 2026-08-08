// ============================================================
// Provider stub: tbo-flight.ts
// File: supabase/functions/_shared/providers/tbo-flight.ts
//
// STATUS: STUB. Tbo's real flight API (auth, search, fare
// revalidation, book/ticket, cancel) is not implemented yet — this
// project has no Tbo credentials or API documentation on
// file as of this commit.
//
// Activating "Tbo" for the flight service in the admin
// panel's API Providers tab, before this class is filled in, will
// make every flight search fail with the error thrown below — by
// design (see getFlightProvider() in ../flight-provider.ts). That's
// intentional: it's safer for a real-money booking platform to fail
// loudly than to silently keep serving mock fares under a provider
// name that implies they're real.
//
// To finish this integration once Tbo sends API docs +
// sandbox credentials:
//   1. Implement each method below against their real endpoints.
//   2. Read auth/config from `credentials` / `config` (populated
//      from the api_providers.credentials / .config JSONB columns —
//      an admin enters these in the admin panel, nothing is
//      hardcoded here).
//   3. Use "Test Connection" in the admin panel (calls search() with
//      a known-good route) before flipping is_active on in production.
// ============================================================

import type {
  FlightProvider,
  FlightSearchParams,
  FlightResult,
  RevalidateResult,
  PassengerInput,
  BookResult,
} from '../flight-provider.ts';

export class TboFlightProvider implements FlightProvider {
  readonly name = 'tbo';

  constructor(
    private credentials: Record<string, string>,
    private config: Record<string, unknown>
  ) {}

  async search(_params: FlightSearchParams): Promise<FlightResult[]> {
    throw new Error(
      'Tbo flight provider is not implemented yet. ' +
      'See supabase/functions/_shared/providers/tbo-flight.ts.'
    );
  }

  async revalidate(_resultId: string): Promise<RevalidateResult> {
    throw new Error('Tbo flight provider is not implemented yet.');
  }

  async book(
    _resultId: string,
    _passengers: PassengerInput[],
    _contact: { email: string; phone: string }
  ): Promise<BookResult> {
    throw new Error('Tbo flight provider is not implemented yet.');
  }

  async cancel(_pnr: string): Promise<{ cancelled: boolean; refundAmount?: number }> {
    throw new Error('Tbo flight provider is not implemented yet.');
  }
}
