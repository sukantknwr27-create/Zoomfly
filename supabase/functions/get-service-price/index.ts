// ============================================================
// Supabase Edge Function: get-service-price
// File: supabase/functions/get-service-price/index.ts
// Deploy: npx supabase functions deploy get-service-price
//
// WHY THIS EXISTS:
// packages.html and hotels.html used to send the price to
// payment.html as a URL query parameter (?amount=12499). Anyone
// could edit that URL before it loads and pay whatever they typed.
// This function is the single source of truth for pricing instead:
// payment.html now asks it "what does THIS package/hotel actually
// cost?" using only the service's database id, and ignores the
// amount in the URL for anything charged or saved.
//
// No auth required — this is a public read of already-public
// catalog prices (same data the packages/hotels listing pages show
// everyone). It does NOT touch bookings or payments.
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
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Vary': 'Origin',
  };
}

// ── RATE LIMITER ─────────────────────────────────────────────
const _rateWindows = new Map<string, number[]>();
const RATE_LIMIT_MAX    = 30;      // 30 lookups per window per IP — this backs live UI, so more generous
const RATE_LIMIT_WINDOW = 60_000;

function isRateLimited(ip: string): boolean {
  const now = Date.now();
  const calls = (_rateWindows.get(ip) || []).filter(t => now - t < RATE_LIMIT_WINDOW);
  calls.push(now);
  _rateWindows.set(ip, calls);
  return calls.length > RATE_LIMIT_MAX;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });

  const ip = req.headers.get('x-forwarded-for')?.split(',')[0].trim() || 'unknown';
  if (isRateLimited(ip)) {
    return new Response(JSON.stringify({ error: 'Too many requests. Please try again later.' }), {
      status: 429,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json', 'Retry-After': '60' },
    });
  }

  try {
    const { service_type, service_id, room_name } = await req.json();
    if (!service_type || !service_id) throw new Error('service_type and service_id are required');

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    if (service_type === 'package') {
      const { data: pkg, error } = await supabase
        .from('packages')
        .select('id, title, price, is_active, nights')
        .eq('id', service_id)
        .eq('is_active', true)
        .single();
      if (error || !pkg) throw new Error('Package not found or no longer available.');

      return new Response(JSON.stringify({
        service_name:  pkg.title,
        base_per_unit: Number(pkg.price),
        unit: 'person',
        nights: pkg.nights,
      }), { headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } });
    }

    if (service_type === 'hotel') {
      const { data: hotel, error } = await supabase
        .from('hotels')
        .select('id, name, rooms, price_per_night, is_active')
        .eq('id', service_id)
        .eq('is_active', true)
        .single();
      if (error || !hotel) throw new Error('Hotel not found or no longer available.');

      const rooms = Array.isArray(hotel.rooms) ? hotel.rooms : [];
      let room = rooms.find((r: any) =>
        room_name && String(r.name).toLowerCase() === String(room_name).toLowerCase()
      );
      if (!room) room = rooms[0]; // fall back to first listed room

      const perNight = room ? Number(room.price) : Number(hotel.price_per_night || 0);
      if (!perNight || perNight <= 0) throw new Error('This hotel has no valid rate configured.');

      return new Response(JSON.stringify({
        service_name:  hotel.name,
        base_per_unit: perNight,
        unit: 'room',
        room_name: room?.name || 'Standard Room',
      }), { headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } });
    }

    throw new Error(`Unsupported service_type: ${service_type}`);
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 400,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }
});
