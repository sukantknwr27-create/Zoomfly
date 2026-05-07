# ZoomFly — GitHub File Placement Guide

## YOUR COMPLETE REPO STRUCTURE

```
zoomfly/                                ← Your GitHub repo root
│
├── index.html                          ← REPLACE existing file (new homepage)
│
├── .env.example                        ← ADD this (safe to commit — no real keys)
├── .gitignore                          ← ADD this (see contents below)
├── sitemap.xml                         ← ADD this
├── robots.txt                          ← ADD this
│
├── js/                                 ← CREATE this folder
│   └── supabase.js                     ← ADD this (shared backend client)
│
├── pages/                              ← Already exists in your repo
│   ├── contact.html                    ← REPLACE existing file
│   ├── packages.html                   ← REPLACE existing file
│   ├── hotels.html                     ← REPLACE existing file
│   ├── login.html                      ← ADD this (new file)
│   ├── dashboard.html                  ← ADD this (new file)
│   ├── admin.html                      ← REPLACE existing file
│   ├── vendor.html                     ← ADD this (new file)
│   ├── flights.html                    ← KEEP existing (no changes)
│   ├── bus.html                        ← KEEP existing (no changes)
│   └── about.html                      ← KEEP existing (no changes)
│
└── supabase/                           ← CREATE this folder
    └── functions/                      ← CREATE this folder
        ├── create-razorpay-order/
        │   └── index.ts                ← ADD this
        ├── verify-razorpay-payment/
        │   └── index.ts                ← ADD this
        ├── send-booking-email/
        │   └── index.ts                ← ADD this
        └── razorpay-webhook/
            └── index.ts                ← ADD this

── NOT IN GITHUB (run separately) ──────
supabase/migrations/001_schema.sql      ← Run in Supabase SQL Editor only
.env                                    ← NEVER commit (has your secret keys)
```

---

## WHAT TO DO WITH EACH FILE

### Files you REPLACE (already exist in your repo)
| Your file on GitHub | Replace with |
|---|---|
| `index.html` | The new `index.html` we built |
| `pages/contact.html` | The new `contact.html` we built |
| `pages/packages.html` | The new `packages.html` we built |
| `pages/hotels.html` | The new `hotels.html` we built |
| `pages/admin.html` | The new `admin.html` we built |

### Files you ADD (new files)
| Add to your repo | Where |
|---|---|
| `supabase.js` | Create folder `/js/` → put file inside |
| `login.html` | Inside `/pages/` folder |
| `dashboard.html` | Inside `/pages/` folder |
| `vendor.html` | Inside `/pages/` folder |
| `sitemap.xml` | Repo root (same level as index.html) |
| `robots.txt` | Repo root (same level as index.html) |
| `.env.example` | Repo root |
| `.gitignore` | Repo root |
| `supabase/functions/create-razorpay-order/index.ts` | Create folders & add file |
| `supabase/functions/verify-razorpay-payment/index.ts` | Create folders & add file |
| `supabase/functions/send-booking-email/index.ts` | Create folders & add file |
| `supabase/functions/razorpay-webhook/index.ts` | Create folders & add file |

### Files you DO NOT commit
| File | Why |
|---|---|
| `.env` | Contains your secret keys — NEVER push to GitHub |
| `001_schema.sql` | Run directly in Supabase SQL Editor, not needed in repo |

---

## .gitignore (CREATE this file in repo root)

```
# Environment variables — NEVER commit
.env
.env.local
.env.production

# OS files
.DS_Store
Thumbs.db

# Editor
.vscode/
.idea/

# Logs
*.log
```

---

## STEP-BY-STEP: HOW TO PUSH TO GITHUB

### Option A — GitHub Website (easiest, no coding)

1. Go to your repo: github.com/YOUR_USERNAME/zoomfly
2. For each file listed above:
   - Click the file (to replace) OR navigate to the folder (to add new)
   - Click pencil ✏️ icon to edit, OR click "Add file" → "Create new file"
   - Paste the file contents
   - Click "Commit changes" → "Commit directly to main"
3. Vercel auto-deploys within 30 seconds after each commit

### Option B — Git CLI (if you have the repo cloned locally)

```bash
# 1. Navigate to your project folder
cd path/to/your/zoomfly

# 2. Create new folders
mkdir -p js
mkdir -p supabase/functions/create-razorpay-order
mkdir -p supabase/functions/verify-razorpay-payment
mkdir -p supabase/functions/send-booking-email
mkdir -p supabase/functions/razorpay-webhook

# 3. Copy/paste all the new files into their correct locations
# (copy from the files we built into the right folders)

# 4. Stage, commit and push
git add .
git commit -m "feat: full backend integration — Supabase, Razorpay, email, dashboard"
git push origin main

# 5. Vercel deploys automatically
```

---

## VERCEL ENVIRONMENT VARIABLES
After pushing, add these in Vercel Dashboard → Settings → Environment Variables:

| Key | Value | Where to get it |
|---|---|---|
| `SUPABASE_URL` | `https://xxx.supabase.co` | Supabase → Settings → API |
| `SUPABASE_ANON_KEY` | `eyJ...` | Supabase → Settings → API |
| `RAZORPAY_KEY_ID` | `rzp_test_...` | Razorpay → Settings → API Keys |

> Note: `SUPABASE_SERVICE_ROLE_KEY` and `RAZORPAY_KEY_SECRET` go into
> Supabase Edge Function secrets only — NOT into Vercel.

---

## QUICK CHECKLIST

- [ ] `index.html` replaced in repo root
- [ ] `pages/contact.html` replaced
- [ ] `pages/packages.html` replaced
- [ ] `pages/hotels.html` replaced
- [ ] `pages/admin.html` replaced
- [ ] `pages/login.html` added
- [ ] `pages/dashboard.html` added
- [ ] `pages/vendor.html` added
- [ ] `js/supabase.js` added (update the 2 keys at top of file)
- [ ] `sitemap.xml` added to root
- [ ] `robots.txt` added to root
- [ ] `.env.example` added to root
- [ ] `.gitignore` added to root (with `.env` inside it)
- [ ] `supabase/functions/*/index.ts` — all 4 Edge Functions added
- [ ] `.env` file created locally (NOT pushed to GitHub)
- [ ] `001_schema.sql` run in Supabase SQL Editor
- [ ] Vercel environment variables set
- [ ] Supabase Edge Function secrets set
- [ ] Edge Functions deployed via Supabase CLI
