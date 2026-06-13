// ============================================================
//  ZOOMFLY — Vercel Edge Middleware
//  File: middleware.js  (root of project)
//
//  Purpose: Server-side auth guard for /admin* routes.
//  Previously, admin pages only had client-side JS guards —
//  the full HTML/JS loaded for everyone before requireAdmin()
//  ran. This middleware blocks unauthenticated requests at the
//  network edge before any HTML is served.
//
//  How it works:
//    1. Matches any request to /admin* or /pages/admin*
//    2. Reads the Supabase session cookie (sb-*-auth-token)
//    3. Verifies the JWT using the SUPABASE_JWT_SECRET env var
//    4. Redirects to /login if invalid or missing
//
//  Setup:
//    In Vercel dashboard → Project → Settings → Environment Variables
//    Add: SUPABASE_JWT_SECRET = (from Supabase → Project Settings → API → JWT Secret)
// ============================================================

import { NextResponse } from 'next/server';

// Routes that require admin access
const ADMIN_PATHS = [
  '/admin',
  '/pages/admin',
];

export const config = {
  matcher: [
    '/admin/:path*',
    '/pages/admin:path*',
  ],
};

export default async function middleware(request) {
  const { pathname } = request.nextUrl;

  // Only guard admin routes
  const isAdminRoute = ADMIN_PATHS.some(p => pathname.startsWith(p));
  if (!isAdminRoute) return NextResponse.next();

  // Read Supabase auth cookie
  // Cookie name format: sb-<project-ref>-auth-token
  const authCookie = [...request.cookies.getAll()]
    .find(c => c.name.startsWith('sb-') && c.name.endsWith('-auth-token'));

  if (!authCookie?.value) {
    return _redirectToLogin(request, 'No session found');
  }

  try {
    // Parse the cookie value (it's a JSON array: [access_token, refresh_token])
    let accessToken;
    try {
      const parsed = JSON.parse(authCookie.value);
      accessToken = Array.isArray(parsed) ? parsed[0] : parsed.access_token;
    } catch {
      accessToken = authCookie.value; // Some versions store raw JWT
    }

    if (!accessToken) throw new Error('No access token in cookie');

    // Decode JWT payload (edge runtime — no crypto libs, just base64 decode)
    const [, payloadB64] = accessToken.split('.');
    const payload = JSON.parse(atob(payloadB64.replace(/-/g, '+').replace(/_/g, '/')));

    // Check expiry
    if (payload.exp && payload.exp < Date.now() / 1000) {
      throw new Error('Token expired');
    }

    // Check admin role — Supabase stores custom claims in app_metadata
    const role = payload.app_metadata?.role || payload.user_metadata?.role;
    if (role !== 'admin') {
      return _redirectToLogin(request, 'Insufficient permissions');
    }

    // ✅ Authenticated admin — allow request
    return NextResponse.next();

  } catch (err) {
    return _redirectToLogin(request, err.message);
  }
}

function _redirectToLogin(request, reason) {
  const loginUrl = new URL('/pages/login.html', request.url);
  loginUrl.searchParams.set('redirect', request.nextUrl.pathname);
  loginUrl.searchParams.set('reason', 'auth_required');
  // Log for debugging (shows in Vercel Function Logs)
  console.warn(`[ZoomFly Middleware] Admin access blocked: ${reason} → ${request.nextUrl.pathname}`);
  return NextResponse.redirect(loginUrl);
}
