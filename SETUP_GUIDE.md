# ZoomFly — Complete Backend Setup Guide
## Stack: Supabase + Razorpay + Resend + Vercel

---

## FOLDER STRUCTURE

```
zoomfly/
├── index.html                        ← Homepage
├── js/
│   └── supabase.js                   ← Shared Supabase client (ALL pages import this)
├── pages/
│   ├── packages.html
│   ├── hotels.html
│   ├── contact.html
│   ├── login.html
│   ├── dashboard.html                ← Customer dashboard (NEW)
│   ├── admin.html
│   └── vendor.html
└── supabase/
    ├── functions/
    │   ├── create-razorpay-order/index.ts
    │   ├── verify-razorpay-payment/index.ts
    │   ├── send-booking-email/index.ts
    │   └── razorpay-webhook/index.ts
    └── migrations/
        └── 001_schema.sql
```

---

## STEP 1 — Supabase Project Setup

1. Go to https://supabase.com → New Project
2. Name it **zoomfly**, choose a strong DB password, select region **South Asia (Mumbai)**
3. Wait ~2 minutes for project to start

### Run the Database Schema
1. In Supabase Dashboard → **SQL Editor** → **New Query**
2. Paste the entire contents of `supabase/migrations/001_schema.sql`
3. Click **Run** — this creates all 10 tables, indexes, triggers, RLS policies, and seed data

### Enable Google OAuth (for social login)
1. Supabase Dashboard → **Authentication** → **Providers** → **Google**
2. Enable it, then go to Google Cloud Console → Create OAuth credentials
3. Paste Client ID & Secret back into Supabase
4. Add `https://YOUR_PROJECT_ID.supabase.co/auth/v1/callback` to Google's Authorized redirect URIs

### Get your API Keys
1. Supabase Dashboard → **Settings** → **API**
2. Copy:
   - **Project URL** → `SUPABASE_URL`
   - **anon public** key → `SUPABASE_ANON_KEY`
   - **service_role** key → `SUPABASE_SERVICE_ROLE_KEY` (KEEP SECRET — never expose in frontend)

---

## STEP 2 — Update Frontend Config

Open `js/supabase.js` and replace:
```js
const SUPABASE_URL  = 'https://YOUR_PROJECT_ID.supabase.co';
const SUPABASE_ANON = 'YOUR_ANON_PUBLIC_KEY';
```
with your actual values from Step 1.

---

## STEP 3 — Razorpay Setup

1. Go to https://razorpay.com → Sign up → Complete KYC
2. For testing, use **Test Mode** (no KYC needed)
3. Dashboard → **Settings** → **API Keys** → Generate Test Key
4. Copy **Key ID** and **Key Secret**

### Set up Webhook
1. Razorpay Dashboard → **Settings** → **Webhooks** → **Add New Webhook**
2. URL: `https://YOUR_PROJECT_ID.supabase.co/functions/v1/razorpay-webhook`
3. Secret: create a random strong string (save as `RAZORPAY_WEBHOOK_SECRET`)
4. Events to enable: `payment.captured`, `payment.failed`, `refund.created`

---

## STEP 4 — Email Setup (Resend — Free)

1. Go to https://resend.com → Sign up free
2. Dashboard → **API Keys** → Create Key → Copy it
3. Add your domain or use `onboarding@resend.dev` for testing
4. Set `FROM_EMAIL` and `ADMIN_EMAIL` in your env vars

---

## STEP 5 — Deploy Supabase Edge Functions

Install Supabase CLI:
```bash
npm install -g supabase
```

Login & link your project:
```bash
supabase login
supabase link --project-ref YOUR_PROJECT_ID
```

Set environment secrets:
```bash
supabase secrets set RAZORPAY_KEY_ID=rzp_test_xxx
supabase secrets set RAZORPAY_KEY_SECRET=xxx
supabase secrets set RAZORPAY_WEBHOOK_SECRET=xxx
supabase secrets set RESEND_API_KEY=re_xxx
supabase secrets set FROM_EMAIL=hello@zoomfly.in
supabase secrets set ADMIN_EMAIL=admin@zoomfly.in
```

Deploy all functions:
```bash
supabase functions deploy create-razorpay-order
supabase functions deploy verify-razorpay-payment
supabase functions deploy send-booking-email
supabase functions deploy razorpay-webhook
```

---

## STEP 6 — Update HTML pages to use real Supabase APIs

Each page that was previously using fake/hardcoded data now needs to import `supabase.js`.

### contact.html — Real enquiry submission
Replace the fake `submitForm()` function with:
```html
<script type="module">
import { submitEnquiry, supabase } from '../js/supabase.js';

async function submitForm() {
  const data = {
    name: document.getElementById('name').value,
    email: document.getElementById('email').value,
    phone: document.getElementById('phone').value,
    interest: selectedInterests,
    travel_date: document.getElementById('travel-date').value || null,
    travellers: document.getElementById('travellers').value,
    budget: document.getElementById('budget').value,
    destination: document.getElementById('destination').value,
  };
  try {
    const result = await submitEnquiry(data);
    // Send email notifications
    await supabase.functions.invoke('send-booking-email', {
      body: { type: 'enquiry', enquiry: data }
    });
    showSuccess(data);
  } catch(e) {
    document.getElementById('error-banner').classList.add('visible');
  }
}
window.submitForm = submitForm;
</script>
```

### packages.html — Load real packages from DB
Replace the hardcoded `packages` array with:
```html
<script type="module">
import { getPackages, addToWishlist, removeFromWishlist, getUser } from '../js/supabase.js';

async function loadPackages() {
  const data = await getPackages();
  // Use data array instead of hardcoded packages
  renderCards(data);
}
loadPackages();
</script>
```

### hotels.html — Load real hotels from DB
```html
<script type="module">
import { getHotels, createBooking, getUser } from '../js/supabase.js';

async function loadHotels() {
  const data = await getHotels();
  renderHotels(data);
}
loadHotels();
</script>
```

### login.html — Real auth
```html
<script type="module">
import { signIn, signUp, signInWithGoogle } from '../js/supabase.js';

async function doLogin() {
  try {
    await signIn({ email, password });
    window.location.href = 'dashboard.html';
  } catch(e) { showError(e.message); }
}

async function doSignup() {
  try {
    await signUp({ email, password, fullName, phone });
    showOTP(); // or redirect to email verification
  } catch(e) { showError(e.message); }
}
</script>
```

### admin.html — Real admin data
```html
<script type="module">
import { admin, requireAdmin, subscribeToEnquiries } from '../js/supabase.js';

await requireAdmin(); // redirect non-admins

const stats = await admin.getStats();
const enquiries = await admin.getAllEnquiries();
const bookings = await admin.getAllBookings();

// Live updates
subscribeToEnquiries((payload) => {
  showNotification('New enquiry from ' + payload.new.name);
  loadEnquiries(); // refresh table
});
</script>
```

---

## STEP 7 — Set Admin Role

After you sign up at your site, go to Supabase → **Table Editor** → `profiles` → find your row → change `role` from `customer` to `admin`.

---

## STEP 8 — Deploy to Vercel

1. Push your entire project to GitHub
2. Go to https://vercel.com → Import Project → Select your repo
3. No build settings needed (pure HTML/JS)
4. Add Environment Variables in Vercel Dashboard → Settings → Environment Variables:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `RAZORPAY_KEY_ID`

5. Click **Deploy** → your site is live!

---

## STEP 9 — Test the Full Flow

### Enquiry Flow
1. Go to `/pages/contact.html`
2. Fill and submit the form
3. Check Supabase → Table Editor → `enquiries` → new row should appear
4. Check your admin email for the alert
5. Check customer email for acknowledgement

### Booking + Payment Flow
1. Log in at `/pages/login.html`
2. Go to Hotels or Packages → Book
3. Fill guest details → Confirm Booking
4. Razorpay checkout opens (use test card: 4111 1111 1111 1111, any CVV, any future date)
5. Payment succeeds → booking confirmed
6. Check Supabase → `bookings` → status = confirmed, payment_status = paid
7. Check email for booking confirmation

### Admin Flow
1. Log in as admin → `/pages/admin.html`
2. Real enquiries and bookings load from Supabase
3. New enquiries appear live (realtime subscription)
4. Click "Done" → enquiry status updates in DB

---

## API ENDPOINTS SUMMARY

| Function | URL | Method | Description |
|---|---|---|---|
| create-razorpay-order | `/functions/v1/create-razorpay-order` | POST | Creates Razorpay payment order |
| verify-razorpay-payment | `/functions/v1/verify-razorpay-payment` | POST | Verifies payment signature |
| send-booking-email | `/functions/v1/send-booking-email` | POST | Sends confirmation/enquiry emails |
| razorpay-webhook | `/functions/v1/razorpay-webhook` | POST | Handles Razorpay payment events |

## DATABASE TABLES SUMMARY

| Table | Purpose |
|---|---|
| profiles | User accounts & roles |
| packages | Tour packages (admin-managed) |
| hotels | Hotel inventory |
| enquiries | Contact form submissions |
| bookings | All customer bookings |
| payments | Razorpay payment records |
| vendors | Partner registrations |
| reviews | Customer reviews |
| wishlists | Saved packages per user |
| promo_codes | Discount codes |

---

## SECURITY CHECKLIST

- [ ] `SUPABASE_SERVICE_ROLE_KEY` is ONLY in Edge Functions — never in frontend HTML
- [ ] `RAZORPAY_KEY_SECRET` is ONLY in Edge Functions — never in frontend
- [ ] RLS (Row Level Security) is enabled on all tables (done in schema)
- [ ] Payment signature is verified server-side before confirming booking
- [ ] Admin routes check `role = 'admin'` before returning data
- [ ] `.env` is in `.gitignore` — never committed to GitHub

---

## SUPPORT

- Supabase Docs: https://supabase.com/docs
- Razorpay Docs: https://razorpay.com/docs
- Resend Docs: https://resend.com/docs
- Questions: hello@zoomfly.in
