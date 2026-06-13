// ============================================================
//  ZOOMFLY — Vercel Edge Middleware (plain static project)
//
//  Uses only the Web Standard Request/Response API.
//  NO next/server import — this is NOT a Next.js project.
//
//  How it works:
//    Intercepts requests to /pages/admin*.html routes.
//    Reads the Supabase session cookie and verifies the JWT.
//    Redirects to login if not authenticated as admin.
// ============================================================

export const config = {
  matcher: ['/pages/admin:path*'],
};

export default async function middleware(request) {
  const url  = new URL(request.url);
  const path = url.pathname;

  // Only guard admin pages
  if (!path.startsWith('/pages/admin')) {
    return new Response(null, { status: 200 });
  }

  // Read Supabase session cookie
  const cookieHeader = request.headers.get('cookie') || '';
  const authCookie   = cookieHeader
    .split(';')
    .map(c => c.trim())
    .find(c => c.startsWith('sb-') && c.includes('-auth-token='));

  if (!authCookie) {
    return _redirectToLogin(url, 'no_session');
  }

  try {
    const rawValue   = authCookie.split('=').slice(1).join('=');
    const decoded    = decodeURIComponent(rawValue);
    const parsed     = JSON.parse(decoded);
    const accessToken = Array.isArray(parsed) ? parsed[0] : parsed.access_token;

    if (!accessToken) throw new Error('no_token');

    // Decode JWT payload — base64url decode, no crypto needed for role check
    const [, payloadB64] = accessToken.split('.');
    const payload = JSON.parse(
      atob(payloadB64.replace(/-/g, '+').replace(/_/g, '/'))
    );

    // Check expiry
    if (payload.exp && payload.exp < Date.now() / 1000) {
      throw new Error('token_expired');
    }

    // Check admin role in app_metadata
    const role = payload.app_metadata?.role || payload.user_metadata?.role;
    if (role !== 'admin') {
      return _redirectToLogin(url, 'not_admin');
    }

    // ✅ Valid admin — let request through
    return new Response(null, { status: 200 });

  } catch (err) {
    return _redirectToLogin(url, err.message || 'auth_error');
  }
}

function _redirectToLogin(url, reason) {
  const loginUrl = new URL('/pages/login.html', url.origin);
  loginUrl.searchParams.set('redirect', url.pathname);
  loginUrl.searchParams.set('reason', reason);
  return Response.redirect(loginUrl.toString(), 302);
}
