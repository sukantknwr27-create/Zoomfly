# ZoomFly Admin Portal — Setup Guide

## The Problem You Were Seeing

1. **Admin opened without login** — `requireAdmin()` was not imported in sub-pages, causing a `ReferenceError` that crashed the auth check entirely
2. **Clicking did nothing** — same crash prevented event listeners from attaching
3. **Data not loading** — same crash blocked all `loadData()` calls

All three root causes are now fixed.

---

## Admin Subdomain Deployment (Vercel)

The admin portal should run on `admin.zoomfly.in` as a separate Vercel deployment.

### Step 1 — Create a new Vercel project for admin

```bash
# In your Vercel dashboard:
# 1. New Project → Import the same GitHub repo
# 2. Set Root Directory to: (leave blank — uses repo root)
# 3. Framework: Other
```

### Step 2 — Set the admin subdomain

In Vercel Dashboard → Your Admin Project → Settings → Domains:
- Add domain: `admin.zoomfly.in`
- In your DNS provider, add a CNAME: `admin` → `cname.vercel-dns.com`

### Step 3 — Set Environment Variables

In Vercel Dashboard → Admin Project → Settings → Environment Variables:

| Variable | Value |
|---|---|
| `RAZORPAY_KEY_ID` | Your Razorpay publishable key |
| `SUPABASE_URL` | `https://ndaurluolurdljrjbxii.supabase.co` |
| `SUPABASE_ANON_KEY` | Your Supabase anon key |

### Step 4 — Deploy

The `admin-portal/vercel.json` routes `/` → admin-login, all paths are protected.

---

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

## Vendor Portal Subdomain (`vendor.zoomfly.in`)

### Step 1 — Create a new Vercel project

```bash
# In your Vercel dashboard:
# 1. New Project → Import the same GitHub repo
# 2. Set Root Directory to: (leave blank — uses repo root)
# 3. Framework: Other
# 4. This will use the SAME repo but its own vercel.json
```

**Important:** Vercel only reads one `vercel.json` per deployment (at the repo root). Since your main site already has `vercel.json` at the root, you have two options for the vendor subdomain:

**Option A (recommended) — Separate repo/branch:**
Push a copy of this repo to a second GitHub repo (or a dedicated branch), and replace the root `vercel.json` with the contents of `vendor-portal-deploy/vercel.json` in that copy. Deploy that repo as its own Vercel project, then point `vendor.zoomfly.in` at it.

**Option B — Vercel Rewrites at the DNS/edge level:**
Keep one deployment. In your main Vercel project → Settings → Domains, add `vendor.zoomfly.in`, then add this rule to your **existing root** `vercel.json` (merge it into your main routes array, near the top, before the catch-all):

```json
{ "src": "^/$", "has": [{ "type": "host", "value": "vendor.zoomfly.in" }], "dest": "/pages/vendor-portal.html" }
```

Option B is simpler if you don't want a second Vercel project.

### Step 2 — DNS

Add a CNAME: `vendor` → `cname.vercel-dns.com` (same as the admin subdomain).

### Step 3 — Vendor role in Supabase

Vendors self-register through the portal's Sign Up tab with `role: 'vendor'` set automatically. No manual SQL needed — but you can verify with:

```sql
SELECT id, email, raw_user_meta_data->>'role' as role, raw_user_meta_data->>'business_name' as business
FROM auth.users
WHERE raw_user_meta_data->>'role' = 'vendor';
```

---

## Navigation Bug Fixes (this update)

| Issue | Root Cause | Fix |
|---|---|---|
| Services dropdown showed nothing on click | `<script>` tags inside `nav.html` never execute — they're injected via `innerHTML`, and browsers strip/ignore scripts added that way | Moved `toggleServicesMenu()` into `main.js` (a real module script) inside `renderNav()` |
| Phone number & Sign In invisible on medium screens | Only breakpoint was 768px (full hamburger swap) — between 768px–1380px, 9 nav links + phone + Sign In + Book Now didn't fit and the flexbox silently crushed items to zero width | Added progressive breakpoints (1320px→900px) that hide non-essential links one at a time before the phone/Sign In/Book Now area is ever touched; `.nav-links` now clips its own overflow instead of shrinking siblings |
