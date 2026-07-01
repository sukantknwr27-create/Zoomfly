# ZoomFly Admin Portal — Setup Guide

## The Problem You Were Seeing

1. **Admin opened without login** — `requireAdmin()` was not imported in sub-pages, causing a `ReferenceError` that crashed the auth check entirely
2. **Clicking did nothing** — same crash prevented event listeners from attaching
3. **Data not loading** — same crash blocked all `loadData()` calls

All three root causes are now fixed.

---

## Admin & Vendor Subdomains (Vercel) — ONE Project, Multiple Domains

You do **not** need separate Vercel projects or separate deployments. One Vercel
project serves `zoomfly.in`, `admin.zoomfly.in`, and `vendor.zoomfly.in` — all
from the same codebase, same build, same deploy. This is handled entirely by
`vercel.json` using host-based routing (the `has: [{ "type": "host", ... }]`
condition), which is already configured in this repo.

### Step 1 — Attach the subdomains to your existing Vercel project

In your **single** Vercel project → Settings → Domains:
1. Add `admin.zoomfly.in`
2. Add `vendor.zoomfly.in`
3. Add `agent.zoomfly.in`

### Step 2 — DNS

In your DNS provider, add three CNAME records:
- `admin` → `cname.vercel-dns.com`
- `vendor` → `cname.vercel-dns.com`
- `agent` → `cname.vercel-dns.com`

### Step 3 — That's it

`vercel.json` already contains routing rules that check the incoming `Host`
header:

```json
{
  "src": "^/$",
  "has": [{ "type": "host", "value": "admin.zoomfly.in" }],
  "dest": "/pages/admin-login.html"
}
```

- Visiting `admin.zoomfly.in` → serves `/pages/admin-login.html`
- Visiting `admin.zoomfly.in/pages/admin-bookings.html` → works directly (assets/pages pass through untouched on any host)
- Visiting `vendor.zoomfly.in` → serves `/pages/vendor-portal.html`
- Visiting `agent.zoomfly.in` → serves `/pages/agent-portal.html`
- `/assets/*` (CSS, JS) is shared across all four domains — one copy, no duplication

No second project, no second deploy, no separate build step. Every `git push` updates all three domains simultaneously since they're the same deployment.

## Supabase — Setting Admin Role

To make a user an admin, run in Supabase SQL Editor:

```sql
-- Option 1: Set role in profiles table
UPDATE profiles 
SET role = 'admin' 
WHERE email = 'admin@zoomfly.in';

-- Option 2: Set in auth.users app_metadata (recommended — more secure)
UPDATE auth.users 
SET raw_app_meta_data = raw_app_meta_data || '{"role":"admin"}'
WHERE email = 'admin@zoomfly.in';
```

---

## Supabase — Required Tables

The admin panel expects these tables. Run in SQL Editor if missing:

```sql
-- Enquiries
CREATE TABLE IF NOT EXISTS enquiries (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name text, email text, phone text,
  service_type text, package_name text, message text,
  status text DEFAULT 'new',
  created_at timestamptz DEFAULT now()
);

-- Bookings (may already exist)
CREATE TABLE IF NOT EXISTS bookings (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  booking_ref text UNIQUE,
  user_id uuid REFERENCES auth.users(id),
  booking_type text, guest_name text, guest_email text,
  total_amount numeric DEFAULT 0,
  status text DEFAULT 'pending',
  payment_status text DEFAULT 'pending',
  created_at timestamptz DEFAULT now()
);

-- Agents
CREATE TABLE IF NOT EXISTS agents (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  full_name text, email text, phone text,
  status text DEFAULT 'active',
  created_at timestamptz DEFAULT now()
);

-- Vendors
CREATE TABLE IF NOT EXISTS vendors (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  business_name text, name text, email text, phone text,
  status text DEFAULT 'active',
  created_at timestamptz DEFAULT now()
);

-- Profiles
CREATE TABLE IF NOT EXISTS profiles (
  id uuid REFERENCES auth.users(id) PRIMARY KEY,
  full_name text, email text, role text DEFAULT 'user',
  created_at timestamptz DEFAULT now()
);

-- Packages
CREATE TABLE IF NOT EXISTS packages (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  title text, description text, price numeric,
  duration text, category text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

-- Hotels
CREATE TABLE IF NOT EXISTS hotels (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name text, city text, state text,
  stars int DEFAULT 4, price_per_night numeric,
  status text DEFAULT 'active',
  created_at timestamptz DEFAULT now()
);

-- Destinations
CREATE TABLE IF NOT EXISTS destinations (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name text, country text, emoji text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
```

### RLS Policies for Admin

```sql
-- Allow admin to read/write all tables
CREATE POLICY "admin_all" ON bookings FOR ALL 
USING (
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
  OR (SELECT raw_app_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) = 'admin'
);

-- Apply same policy to other tables (enquiries, agents, vendors, profiles, packages, hotels, destinations)
```

---

## What Was Fixed

| Issue | Fix |
|---|---|
| Admin pages open without login | `requireAdmin()` now imported in ALL 8 sub-pages |
| Clicking nothing in sub-pages | Import crash fixed — event listeners now attach |
| Data not loading | Auth now passes → `loadAll()` / `loadBookings()` etc. now execute |
| `signOut()` broken in sub-pages | `signOut` now imported in all sub-pages |
| `loadNav()` in reminders (wrong IDs) | Removed `loadNav` import; admin pages don't use public nav |
| admin-login blue colors | Updated to gold/navy theme |
| Admin subdomain | Created `admin-portal/vercel.json` with clean URL routing |

---

## Navigation Bug Fixes (this update)

| Issue | Root Cause | Fix |
|---|---|---|
| Services dropdown showed nothing on click | `<script>` tags inside `nav.html` never execute — they're injected via `innerHTML`, and browsers strip/ignore scripts added that way | Moved `toggleServicesMenu()` into `main.js` (a real module script) inside `renderNav()` |
| Phone number & Sign In invisible on medium screens | Only breakpoint was 768px (full hamburger swap) — between 768px–1380px, 9 nav links + phone + Sign In + Book Now didn't fit and the flexbox silently crushed items to zero width | Added progressive breakpoints (1320px→900px) that hide non-essential links one at a time before the phone/Sign In/Book Now area is ever touched; `.nav-links` now clips its own overflow instead of shrinking siblings |
