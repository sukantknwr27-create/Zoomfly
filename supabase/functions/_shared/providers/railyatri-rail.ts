// ============================================================
// Provider stub: railyatri-rail.ts
// File: supabase/functions/_shared/providers/railyatri-rail.ts
//
// STATUS: STUB. Railyatri's real rail/IRCTC B2B API is not
// implemented yet — this project has no Railyatri rail
// credentials or API documentation on file as of this commit.
//
// Activating "Railyatri" for the rail service in the admin
// panel's API Providers tab, before this class is filled in, will
// make every rail search fail with the error thrown below — by
// design (see getRailProvider() in ../rail-provider.ts).
//
// Remember: even once this is implemented for search(), actual
// ticketing stays a manual admin step via rail_ticketing_queue —
// IRCTC has no open consolidator API for direct programmatic
// booking. Only checkPnrStatus() (if Railyatri offers a real
// PNR-status endpoint) and search() belong in this class; there is
// no book() on the RailProvider interface.
// ============================================================

import type { RailProvider, RailSearchParams, RailTrainResult } from '../rail-provider.ts';

export class RailyatriRailProvider implements RailProvider {
  readonly name = 'railyatri';

  constructor(
    private credentials: Record<string, string>,
    private config: Record<string, unknown>
  ) {}

  async search(_params: RailSearchParams): Promise<RailTrainResult[]> {
    throw new Error(
      'Railyatri rail provider is not implemented yet. ' +
      'See supabase/functions/_shared/providers/railyatri-rail.ts.'
    );
  }

  async checkPnrStatus(_pnr: string): Promise<{ status: string; details: string }> {
    throw new Error('Railyatri rail provider does not implement PNR status yet.');
  }
}
