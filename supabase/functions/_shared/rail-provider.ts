// ============================================================
// Shared module: rail-provider.ts
// File: supabase/functions/_shared/rail-provider.ts
//
// Same pattern as flight-provider.ts, with one structural difference
// that's a hard constraint, not a design choice: IRCTC has no open
// consolidator API. Every B2B rail provider (Tripjack Rail, TBO Rail,
// railYatri, ...) ultimately books through an authorized-agent flow,
// not a live programmatic Book/Ticket call the way flight
// consolidators offer. So RailProvider.search() gives real (or, for
// MockRailProvider, clearly-labelled placeholder) schedule/fare/
// indicative-availability data — but there is no book() that returns
// an instant PNR. The actual ticket is always issued by a human
// admin working the rail_ticketing_queue (see
// 18_zoomfly_rail_booking.sql and rail-create-booking/index.ts),
// regardless of which search provider is active.
//
// STATUS: only MockRailProvider is implemented. It replaces
// trains.html's previous fake backend (hardcoded TRAIN_DB schedule,
// Math.random() seat availability, a synthetic fare multiplier) with
// the same seeded-deterministic approach flight's MockFlightProvider
// uses, so results are reproducible and every result is tagged
// isMock:true. The stub classes in ./providers/ (tbo-rail.ts,
// tripjack-rail.ts, railyatri-rail.ts) throw clear "not implemented"
// errors until a real provider's API docs are in hand — same honesty
// contract as the flight stubs.
// ============================================================

import { getActiveProviderConfigs } from './provider-config.ts';

export interface RailSearchParams {
  from: string;    // station code, e.g. "NDLS"
  to: string;      // station code, e.g. "HWH"
  date: string;    // YYYY-MM-DD
  quota: 'GN' | 'TQ' | 'PT' | 'LD' | 'SS';
}

export interface RailClassAvailability {
  classCode: string;   // 1A, 2A, 3A, SL, CC, EC, 2S
  status: 'AVAILABLE' | 'WL' | 'RAC' | 'NOT_AVAILABLE';
  label: string;        // e.g. "Available", "WL12", "RAC4"
  fare: { perPerson: number; tax: number; total: number; currency: string };
}

export interface RailTrainResult {
  trainNumber: string;
  trainName: string;
  from: string;
  to: string;
  departTime: string;   // HH:MM
  arriveTime: string;   // HH:MM, may carry a "+1"/"+2" day suffix
  durationMinutes: number;
  runsOn: number[];     // 7 entries, 0=Sun..6=Sat, 1=runs
  trainType: string;    // Rajdhani, Shatabdi, Duronto, Superfast, Mail, Express, Intercity
  classes: RailClassAvailability[];
  provider: string;
  isMock?: boolean;
}

export interface RailProvider {
  readonly name: string;
  search(params: RailSearchParams): Promise<RailTrainResult[]>;
  /**
   * Real-time PNR status. Optional because most rail providers (and
   * MockRailProvider) don't offer this — when absent, the frontend
   * points the customer to irctc.co.in directly instead of showing a
   * fabricated status. NEVER implement this by generating a random
   * result; only real providers with an actual PNR-status API should
   * implement it.
   */
  checkPnrStatus?(pnr: string): Promise<{ status: string; details: string }>;
}

// ────────────────────────────────────────────────────────────
// STATION DATA — moved server-side from trains.html so search
// validation and autocomplete both use one source of truth.
// ────────────────────────────────────────────────────────────
// Merged from this file's previous 18-entry list and trains.html's
// previous separate 78-entry client-side list, which had drifted out
// of sync with each other (and disagreed on at least one code: CSTM
// vs. the correct current CSMT for Mumbai CSMT — CSMT kept). This is
// now the single source of truth; trains.html fetches from the
// mode:'stations' sub-endpoint below instead of hardcoding its own
// copy. Covers major junctions/state capitals only — not a full
// IRCTC station master (~7,000+ stations). That should come from a
// live supplier (Tripjack) station-master feed once connected, not
// further hand-typed entries here.
export const STATIONS = [
  { code: 'ADI',  name: 'Ahmedabad Jn', city: 'Ahmedabad' },
  { code: 'AF',   name: 'Agra Fort', city: 'Agra' },
  { code: 'AGC',  name: 'Agra Cantt', city: 'Agra' },
  { code: 'AII',  name: 'Ajmer Junction', city: 'Ajmer' },
  { code: 'ALD',  name: 'Prayagraj Junction', city: 'Prayagraj' },
  { code: 'ANVT', name: 'Anand Vihar Terminal', city: 'Delhi' },
  { code: 'ASN',  name: 'Asansol Junction', city: 'Asansol' },
  { code: 'ASR',  name: 'Amritsar Junction', city: 'Amritsar' },
  { code: 'BBS',  name: 'Bhubaneswar', city: 'Bhubaneswar' },
  { code: 'BCT',  name: 'Mumbai Borivali', city: 'Mumbai' },
  { code: 'BE',   name: 'Bareilly', city: 'Bareilly' },
  { code: 'BKN',  name: 'Bikaner Junction', city: 'Bikaner' },
  { code: 'BPL',  name: 'Bhopal Jn', city: 'Bhopal' },
  { code: 'BRC',  name: 'Vadodara Junction', city: 'Vadodara' },
  { code: 'BSB',  name: 'Varanasi Junction', city: 'Varanasi' },
  { code: 'BSP',  name: 'Bilaspur Junction', city: 'Bilaspur' },
  { code: 'BZA',  name: 'Vijayawada Junction', city: 'Vijayawada' },
  { code: 'CBE',  name: 'Coimbatore Junction', city: 'Coimbatore' },
  { code: 'CDG',  name: 'Chandigarh', city: 'Chandigarh' },
  { code: 'CNB',  name: 'Kanpur Central', city: 'Kanpur' },
  { code: 'CSMT', name: 'Chhatrapati Shivaji Maharaj T.', city: 'Mumbai' },
  { code: 'DBRG', name: 'Dibrugarh', city: 'Dibrugarh' },
  { code: 'DDN',  name: 'Dehradun', city: 'Dehradun' },
  { code: 'DHN',  name: 'Dhanbad Junction', city: 'Dhanbad' },
  { code: 'DLI',  name: 'Delhi Junction', city: 'Delhi' },
  { code: 'ERS',  name: 'Ernakulam Jn', city: 'Kochi' },
  { code: 'GHY',  name: 'Guwahati', city: 'Guwahati' },
  { code: 'GKP',  name: 'Gorakhpur Junction', city: 'Gorakhpur' },
  { code: 'GWL',  name: 'Gwalior Junction', city: 'Gwalior' },
  { code: 'HW',   name: 'Haridwar Junction', city: 'Haridwar' },
  { code: 'HWH',  name: 'Howrah Jn', city: 'Kolkata' },
  { code: 'HYB',  name: 'Hyderabad Deccan', city: 'Hyderabad' },
  { code: 'INDB', name: 'Indore Junction', city: 'Indore' },
  { code: 'JAT',  name: 'Jammu Tawi', city: 'Jammu' },
  { code: 'JBP',  name: 'Jabalpur', city: 'Jabalpur' },
  { code: 'JP',   name: 'Jaipur Jn', city: 'Jaipur' },
  { code: 'JU',   name: 'Jodhpur Jn', city: 'Jodhpur' },
  { code: 'KCG',  name: 'Kacheguda', city: 'Hyderabad' },
  { code: 'KJM',  name: 'Krishnarajapuram', city: 'Bangalore' },
  { code: 'KOAA', name: 'Kolkata', city: 'Kolkata' },
  { code: 'KOTA', name: 'Kota Junction', city: 'Kota' },
  { code: 'KRMI', name: 'Karmali', city: 'Goa' },
  { code: 'LDH',  name: 'Ludhiana Junction', city: 'Ludhiana' },
  { code: 'LJN',  name: 'Lucknow Junction', city: 'Lucknow' },
  { code: 'LKO',  name: 'Lucknow', city: 'Lucknow' },
  { code: 'LTT',  name: 'Lokmanya Tilak Terminus', city: 'Mumbai' },
  { code: 'MAO',  name: 'Madgaon', city: 'Goa' },
  { code: 'MAS',  name: 'MGR Chennai Central', city: 'Chennai' },
  { code: 'MB',   name: 'Moradabad', city: 'Moradabad' },
  { code: 'MDU',  name: 'Madurai Junction', city: 'Madurai' },
  { code: 'MGS',  name: 'Mughal Sarai (DDU)', city: 'Varanasi' },
  { code: 'MMCT', name: 'Mumbai Central', city: 'Mumbai' },
  { code: 'MSC',  name: 'Chennai Egmore', city: 'Chennai' },
  { code: 'MYS',  name: 'Mysuru Junction', city: 'Mysore' },
  { code: 'NDLS', name: 'New Delhi', city: 'Delhi' },
  { code: 'NGP',  name: 'Nagpur Junction', city: 'Nagpur' },
  { code: 'NJP',  name: 'New Jalpaiguri', city: 'Siliguri' },
  { code: 'NLR',  name: 'Nellore', city: 'Nellore' },
  { code: 'NZM',  name: 'Hazrat Nizamuddin', city: 'New Delhi' },
  { code: 'PNBE', name: 'Patna Jn', city: 'Patna' },
  { code: 'PUNE', name: 'Pune Jn', city: 'Pune' },
  { code: 'PURI', name: 'Puri', city: 'Puri' },
  { code: 'RJPB', name: 'Rajendranagar Terminal', city: 'Patna' },
  { code: 'RNC',  name: 'Ranchi Junction', city: 'Ranchi' },
  { code: 'RPR',  name: 'Raipur Junction', city: 'Raipur' },
  { code: 'RTM',  name: 'Ratlam Junction', city: 'Ratlam' },
  { code: 'SBC',  name: 'KSR Bengaluru', city: 'Bengaluru' },
  { code: 'SC',   name: 'Secunderabad Junction', city: 'Hyderabad' },
  { code: 'SDAH', name: 'Sealdah', city: 'Kolkata' },
  { code: 'SLN',  name: 'Sultanpur', city: 'Sultanpur' },
  { code: 'ST',   name: 'Surat', city: 'Surat' },
  { code: 'TPJ',  name: 'Tiruchchirappalli Junction', city: 'Trichy' },
  { code: 'TPTY', name: 'Tirupati', city: 'Tirupati' },
  { code: 'TVC',  name: 'Thiruvananthapuram Central', city: 'Trivandrum' },
  { code: 'UBL',  name: 'Hubballi Junction', city: 'Hubli' },
  { code: 'UDZ',  name: 'Udaipur City', city: 'Udaipur' },
  { code: 'UHP',  name: 'Udhampur', city: 'Udhampur' },
  { code: 'UJN',  name: 'Ujjain Junction', city: 'Ujjain' },
  { code: 'VSKP', name: 'Visakhapatnam', city: 'Visakhapatnam' },
  { code: 'YPR',  name: 'Yesvantpur Junction', city: 'Bangalore' },
];

function hashSeed(str: string): number {
  let h = 0;
  for (let i = 0; i < str.length; i++) h = (h * 31 + str.charCodeAt(i)) >>> 0;
  return h;
}

const MOCK_TRAIN_TYPES = ['Rajdhani', 'Shatabdi', 'Duronto', 'Superfast', 'Mail', 'Express', 'Intercity'];
const BASE_FARE: Record<string, number> = { '1A': 2500, '2A': 1500, '3A': 900, 'SL': 300, 'CC': 600, 'EC': 1200, '2S': 150 };
const TYPE_MUL: Record<string, number> = { Rajdhani: 1.6, Duronto: 1.5, Shatabdi: 1.4, Superfast: 1.2, Mail: 1.0, Express: 1.0, Intercity: 0.9 };
const QUOTA_MUL: Record<string, number> = { GN: 1, TQ: 1.3, PT: 1.5, LD: 1, SS: 0.7 };
const CLASSES_BY_TYPE: Record<string, string[]> = {
  Rajdhani: ['1A', '2A', '3A'],
  Duronto: ['1A', '2A', '3A'],
  Shatabdi: ['CC', 'EC'],
  Superfast: ['1A', '2A', '3A', 'SL'],
  Mail: ['2A', '3A', 'SL', '2S'],
  Express: ['1A', '2A', '3A', 'SL'],
  Intercity: ['CC', '2S'],
};

/**
 * Deterministic fare + indicative-availability calculation, shared by
 * search() and getFare() so a fare quoted at search time and the fare
 * re-derived server-side at booking time (see rail-create-booking)
 * always agree for the same inputs — the rail equivalent of a flight
 * fare hold, without needing a literal hold table, since these fares
 * don't fluctuate the way live flight inventory does.
 */
export function calcMockFare(trainType: string, classCode: string, quota: string, seed: number) {
  const base = (BASE_FARE[classCode] || 500) * (TYPE_MUL[trainType] || 1) * (QUOTA_MUL[quota] || 1);
  const perPerson = Math.round(base / 50) * 50;
  const tax = Math.round(perPerson * 0.05);
  return { perPerson, tax, total: perPerson + tax, currency: 'INR' };
}

function mockAvailability(seed: number): { status: RailClassAvailability['status']; label: string } {
  const r = seed % 100;
  if (r >= 55) {
    const seats = 1 + (seed % 40);
    return { status: 'AVAILABLE', label: `Available ${seats}` };
  }
  if (r >= 25) {
    const wl = 1 + (seed % 30);
    return { status: 'WL', label: `WL${wl}` };
  }
  if (r >= 10) {
    const rac = 1 + (seed % 15);
    return { status: 'RAC', label: `RAC${rac}` };
  }
  return { status: 'NOT_AVAILABLE', label: 'Not Available' };
}

export class MockRailProvider implements RailProvider {
  readonly name = 'mock';

  async search(params: RailSearchParams): Promise<RailTrainResult[]> {
    const routeSeed = hashSeed(`${params.from}${params.to}${params.date}`);
    const count = 3 + (routeSeed % 5); // 3–7 trains per route, deterministic

    const results: RailTrainResult[] = [];
    for (let i = 0; i < count; i++) {
      const seed = hashSeed(`${routeSeed}-${i}`);
      const trainType = MOCK_TRAIN_TYPES[seed % MOCK_TRAIN_TYPES.length];
      const depHour = 4 + (seed % 20);
      const depMin = (seed * 7) % 60;
      const durationMinutes = 180 + (seed % 1500);
      const arrTotalMin = depHour * 60 + depMin + durationMinutes;
      const dayOffset = Math.floor(arrTotalMin / 1440);
      const arrHour = Math.floor((arrTotalMin % 1440) / 60);
      const arrMin = arrTotalMin % 60;

      const classes = (CLASSES_BY_TYPE[trainType] || ['SL']).map((cls, ci) => {
        const clsSeed = hashSeed(`${seed}-${cls}-${ci}`);
        const avail = mockAvailability(clsSeed);
        return {
          classCode: cls,
          status: avail.status,
          label: avail.label,
          fare: calcMockFare(trainType, cls, params.quota, clsSeed),
        };
      });

      results.push({
        trainNumber: String(12000 + (seed % 8000)),
        trainName: `${trainType} Express`,
        from: params.from,
        to: params.to,
        departTime: `${String(depHour).padStart(2, '0')}:${String(depMin).padStart(2, '0')}`,
        arriveTime: `${String(arrHour).padStart(2, '0')}:${String(arrMin).padStart(2, '0')}${dayOffset > 0 ? `+${dayOffset}` : ''}`,
        durationMinutes,
        runsOn: [0, 1, 2, 3, 4, 5, 6].map(d => ((seed + d) % 3 === 0 ? 0 : 1)),
        trainType,
        classes,
        provider: this.name,
        isMock: true,
      });
    }

    return results.sort((a, b) => a.departTime.localeCompare(b.departTime));
  }
  // No checkPnrStatus — MockRailProvider deliberately does not
  // fabricate PNR status. See the interface comment above.
}

// ────────────────────────────────────────────────────────────
// FACTORY — DB-driven, identical pattern to getFlightProvider().
// ────────────────────────────────────────────────────────────
type RailProviderFactory = (
  credentials: Record<string, string>,
  config: Record<string, unknown>
) => Promise<RailProvider>;

const RAIL_PROVIDER_FACTORIES: Record<string, RailProviderFactory> = {
  tbo: async (credentials, config) => {
    const { TboRailProvider } = await import('./providers/tbo-rail.ts');
    return new TboRailProvider(credentials, config);
  },
  tripjack: async (credentials, config) => {
    const { TripjackRailProvider } = await import('./providers/tripjack-rail.ts');
    return new TripjackRailProvider(credentials, config);
  },
  railyatri: async (credentials, config) => {
    const { RailyatriRailProvider } = await import('./providers/railyatri-rail.ts');
    return new RailyatriRailProvider(credentials, config);
  },
};

// deno-lint-ignore no-explicit-any
export async function getRailProvider(supabase: any): Promise<RailProvider> {
  const configs = await getActiveProviderConfigs(supabase, 'rail');
  const primary = configs[0];

  if (!primary || primary.provider_key === 'mock') {
    return new MockRailProvider();
  }

  const factory = RAIL_PROVIDER_FACTORIES[primary.provider_key];
  if (!factory) {
    throw new Error(
      `Rail provider "${primary.provider_key}" is active in the admin panel but has no ` +
      `implementation registered. Add supabase/functions/_shared/providers/${primary.provider_key}-rail.ts ` +
      `and register it in RAIL_PROVIDER_FACTORIES (rail-provider.ts).`
    );
  }

  return factory(primary.credentials, primary.config);
}
