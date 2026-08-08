// ============================================================
// Shared module: flight-provider.ts
// File: supabase/functions/_shared/flight-provider.ts
//
// Every flight consolidator (TBO, Tripjack, Riya Travel, Akbar B2B,
// ...) has its own request/response shape and auth scheme. Nothing
// in flight-search / flight-select-fare / flight-ticket-processor
// should know which one is in use — they only talk to the
// `FlightProvider` interface below. Swapping or adding a
// consolidator later means writing one new file that implements
// this interface and adding one line to getFlightProvider(); it
// does NOT mean touching the edge functions or the frontend.
//
// STATUS: no consolidator is wired up yet (no TBO/Tripjack/etc.
// credentials exist in this project as of this migration). The
// only implementation right now is MockFlightProvider, which
// returns clearly-labelled placeholder data so the full booking
// pipeline (search → lock → pay → ticket → confirm) can be built,
// tested, and deployed end-to-end before a real consolidator
// contract is signed. Every mock result is tagged isMock:true and
// every mock airline/flight number is obviously fake (see below) so
// it can never be confused with a real fare — do not remove those
// tags when wiring in a real provider; instead, delete
// MockFlightProvider's usage from getFlightProvider() entirely.
// ============================================================

export interface FlightSearchParams {
  origin: string;        // IATA code, e.g. "DEL"
  destination: string;   // IATA code, e.g. "BOM"
  departDate: string;    // YYYY-MM-DD
  returnDate?: string;   // YYYY-MM-DD, round-trip only
  adults: number;
  children: number;
  infants: number;
  cabinClass: 'economy' | 'business' | 'first';
  tripType: 'one-way' | 'round' | 'multi';
}

export interface FlightFare {
  base: number;
  taxes: number;
  total: number;
  currency: string;
}

export interface FlightSegment {
  airlineCode: string;
  airlineName: string;
  flightNumber: string;
  from: string;
  to: string;
  departTime: string;   // ISO 8601
  arriveTime: string;   // ISO 8601
  durationMinutes: number;
}

export interface FlightResult {
  resultId: string;          // provider's own reference — MUST be passed back unchanged to revalidate()/book()
  provider: string;
  segments: FlightSegment[];
  stops: number;
  fare: FlightFare;
  refundable: boolean;
  seatsLeft: number;
  baggage: { checkIn: string; cabin: string };
  isMock?: boolean;
}

export interface RevalidateResult {
  stillAvailable: boolean;
  fare: FlightFare;          // the current, authoritative price — may differ from the search-time fare
  resultId: string;          // provider may issue a new token when revalidating; always use this going forward
}

export interface PassengerInput {
  title: 'Mr' | 'Mrs' | 'Ms' | 'Master' | 'Miss';
  firstName: string;
  lastName: string;
  dob: string;              // YYYY-MM-DD
  gender: 'M' | 'F';
  type: 'adult' | 'child' | 'infant';
  passportNumber?: string;  // required for international
}

export interface BookResult {
  pnr: string;
  ticketNumbers: string[];  // one per passenger
  status: 'ticketed';
}

export interface FlightProvider {
  readonly name: string;
  search(params: FlightSearchParams): Promise<FlightResult[]>;
  revalidate(resultId: string): Promise<RevalidateResult>;
  book(resultId: string, passengers: PassengerInput[], contact: { email: string; phone: string }): Promise<BookResult>;
  cancel(pnr: string): Promise<{ cancelled: boolean; refundAmount?: number }>;
}

// ────────────────────────────────────────────────────────────
// MOCK PROVIDER — deterministic placeholder data, clearly fake.
// ────────────────────────────────────────────────────────────
const MOCK_AIRLINES = [
  { code: 'ZM', name: 'Mock Air (test data)' },
  { code: 'ZT', name: 'Test Airways (test data)' },
];

function hashSeed(str: string): number {
  let h = 0;
  for (let i = 0; i < str.length; i++) h = (h * 31 + str.charCodeAt(i)) >>> 0;
  return h;
}

export class MockFlightProvider implements FlightProvider {
  readonly name = 'mock';

  async search(params: FlightSearchParams): Promise<FlightResult[]> {
    const seed = hashSeed(`${params.origin}${params.destination}${params.departDate}${params.cabinClass}`);
    const isIntl = params.destination.length === 3 && !['DEL','BOM','BLR','MAA','CCU','HYD','GOI','COK','IXL','IXZ','PNQ','AMD'].includes(params.destination);
    const baseFare = isIntl ? 18000 : 3500;
    const classMul = params.cabinClass === 'business' ? 3.2 : params.cabinClass === 'first' ? 5.5 : 1;

    return MOCK_AIRLINES.map((al, i) => {
      const depHour = 6 + ((seed + i * 7) % 15);
      const durationMinutes = isIntl ? 240 + ((seed + i * 13) % 180) : 60 + ((seed + i * 11) % 120);
      const departTime = new Date(`${params.departDate}T${String(depHour).padStart(2, '0')}:00:00Z`);
      const arriveTime = new Date(departTime.getTime() + durationMinutes * 60_000);
      const fareBase = Math.round((baseFare * (0.85 + i * 0.15) * classMul) / 10) * 10;
      const taxes = Math.round(fareBase * 0.12);

      return {
        resultId: `MOCK-${seed}-${i}-${params.origin}${params.destination}`,
        provider: this.name,
        segments: [{
          airlineCode: al.code,
          airlineName: al.name,
          flightNumber: `${al.code}${1000 + ((seed + i * 37) % 899)}`,
          from: params.origin,
          to: params.destination,
          departTime: departTime.toISOString(),
          arriveTime: arriveTime.toISOString(),
          durationMinutes,
        }],
        stops: i === 0 ? 0 : 1,
        fare: { base: fareBase, taxes, total: fareBase + taxes, currency: 'INR' },
        refundable: i % 2 === 0,
        seatsLeft: 2 + ((seed + i) % 8),
        baggage: { checkIn: '15kg', cabin: '7kg' },
        isMock: true,
      };
    }).sort((a, b) => a.fare.total - b.fare.total);
  }

  async revalidate(resultId: string): Promise<RevalidateResult> {
    // Simulates the real-world case where a fare has drifted slightly
    // since search — deterministic so tests are repeatable.
    const seed = hashSeed(resultId);
    const drift = (seed % 100) < 15; // ~15% of the time, price moves
    const parts = resultId.split('-');
    const baseGuess = 3500 + (seed % 15000);
    const total = drift ? Math.round(baseGuess * 1.05) : baseGuess;
    return {
      stillAvailable: (seed % 50) !== 0, // ~2% simulated sold-out
      fare: { base: Math.round(total * 0.88), taxes: Math.round(total * 0.12), total, currency: 'INR' },
      resultId,
    };
  }

  async book(resultId: string, passengers: PassengerInput[], _contact: { email: string; phone: string }): Promise<BookResult> {
    const seed = hashSeed(resultId + passengers.map(p => p.firstName).join(''));
    // Simulates an occasional booking failure so the retry/refund path is exercisable in testing.
    if (seed % 37 === 0) {
      throw new Error('MOCK_PROVIDER: simulated ticketing failure (seat no longer available)');
    }
    return {
      pnr: `MOCK${(seed % 900000 + 100000)}`,
      ticketNumbers: passengers.map((_, i) => `MOCKTKT-${seed}-${i}`),
      status: 'ticketed',
    };
  }

  async cancel(pnr: string): Promise<{ cancelled: boolean; refundAmount?: number }> {
    return { cancelled: true, refundAmount: undefined };
  }
}

// ────────────────────────────────────────────────────────────
// FACTORY — swap in a real provider here once consolidator
// credentials exist. Example for later:
//
//   if (Deno.env.get('FLIGHT_PROVIDER') === 'tbo') {
//     const { TboFlightProvider } = await import('./providers/tbo.ts');
//     return new TboFlightProvider(Deno.env.get('TBO_USERNAME')!, Deno.env.get('TBO_PASSWORD')!);
//   }
// ────────────────────────────────────────────────────────────
export function getFlightProvider(): FlightProvider {
  const configured = Deno.env.get('FLIGHT_PROVIDER');
  if (configured && configured !== 'mock') {
    throw new Error(
      `FLIGHT_PROVIDER is set to "${configured}" but no real provider implementation exists yet. ` +
      `Implement it in supabase/functions/_shared/providers/${configured}.ts and wire it into getFlightProvider().`
    );
  }
  return new MockFlightProvider();
}
