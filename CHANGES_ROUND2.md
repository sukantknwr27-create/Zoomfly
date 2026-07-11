# Changes in this round

Implements the highest-priority items from the owner/customer/vendor/investor
review: the security fix, the fake social proof, real availability, the
vendor payout ledger, and the agent tier/commission consistency bug.

## 1. Security — Razorpay webhook
`supabase/functions/razorpay-webhook/index.ts`
- Signature comparison was a plain `===`, which is a timing side-channel
  (an attacker can, in theory, recover the correct signature one character
  at a time by measuring response times). Replaced with a constant-time
  comparison. Also now rejects requests with no signature header outright.

## 2. Honest social proof (was fabricated)
`index.html`
- The "Priya from Delhi just booked..." popup and its rotation array were
  100% hardcoded — same 8 fake names/times on every visit. Replaced with a
  live query against a new view, `public_recent_activity` (see migration
  below), which only ever contains real, confirmed + paid bookings from
  the last 14 days, reduced to first-name + last-initial. If there's no
  real recent activity, the widget now simply stays hidden — it no longer
  invents activity to fill the silence.

## 3. Real date availability on package pages
`pages/package-detail.html`
- The `package_availability` table (blackout dates, set by ops/vendors)
  existed in the schema but was never queried by the customer-facing page.
  Picking a travel date now checks that table and shows a genuine
  "✅ Available" / "🚫 Not available — reason" message, and disables the
  booking button on a blocked date (with a server-side-equivalent guard
  in `bookNow()` too, in case the disabled state is bypassed client-side).

## 4. Vendor payout ledger (new)
`supabase/migration/01_zoomfly_growth_features.sql` + `pages/vendor-portal.html`
- Vendors previously only saw a *computed* running commission estimate —
  no record of what was actually paid, when, or by what reference. Added
  a `vendor_payouts` table (mirrors the existing `agent_payouts` design)
  with RLS so a vendor can only read their own rows, and a new
  "Payout History" table in the vendor portal showing period, bookings
  covered, net amount, status, paid-on date, and UTR/bank reference.
  **Admin-side UI to create/update these payout rows isn't built yet** —
  today they'd be inserted directly in Supabase or via a future
  admin-vendors.html addition. Flagging this as the natural next step.

## 5. Agent tier / commission consistency bug (found + fixed)
`supabase/migration/01_zoomfly_growth_features.sql` + `pages/agent-portal.html`
This was a real, pre-existing bug, not a hypothetical:
- The DB trigger `auto_upgrade_agent_tier` promotes agents to
  `silver` / `gold` / `platinum` based on lifetime booking value, but
  never updated `commission_rate` — so a "gold" agent in the database
  could still be paid the base 5% rate everywhere.
- Separately, `agent-portal.html` used its own tier vocabulary
  (`associate` / `senior` / `elite`) with different thresholds and a
  hardcoded `COMM_RATES` map that didn't include `silver`/`gold`/`platinum`
  at all — so any agent the database actually promoted would render an
  unstyled tier badge and silently fall back to the 5% rate in every
  commission calculation on the page.
- Fixed by: (a) making the trigger set `commission_rate` alongside
  `tier`, (b) rewriting the frontend to use the same four tier names and
  thresholds as the database, and (c) having the UI read
  `agents.commission_rate` directly instead of maintaining a second,
  independent rate table that can drift out of sync.
- Added a real tier-progress bar (₹ remaining to next tier, based on
  actual `total_booking_value`) so agents can see progress instead of
  just a static tier badge.

## 6. Admin panel audit (checked, one real gap fixed)
Went through all 11 admin pages plus the shared auth guard.

**What's solid:** every admin page calls a shared `requireAdmin()` guard
before rendering, and — more importantly — the actual data access is
gated server-side by an `is_admin()` `SECURITY DEFINER` function backing
RLS on `bookings`/`vendors`/`agents`/`profiles`. Traced the self-escalation
fix end to end: `handle_new_user()` hardcodes new signups to
`role='customer'` regardless of what the client sends, and a
`protect_profile_privileged_columns` trigger pins `role`/`is_active` back
to their old value on UPDATE unless the request comes from `service_role`.
This is a real fix, not just a comment.

**Gap found and fixed:** `requireAdmin()` (`assets/js/supabase.js`),
`checkAdminRole()` (`admin-login.html`), and the post-login redirect logic
(`login.html`) all checked `user.app_metadata?.role || user.user_metadata?.role`.
`app_metadata` is safe (only settable via the service-role admin API), but
`user_metadata` is user-editable from the browser
(`supabase.auth.updateUser({data:{role:'admin'}})` — anyone can call this
on themselves). A non-admin exploiting this would have gotten the admin UI
*shell* to render, but not real data, since every actual query is still
blocked by the DB-side `is_admin()` check, which never looks at
`user_metadata`. Fixed by dropping the `user_metadata` fallback in all
three places — `app_metadata` (or, failing that, a real `profiles` table
lookup) is now the only path to an "is admin" answer anywhere in the app.

## 7. Payment replay across bookings (found and fixed) — CRITICAL
`supabase/functions/verify-razorpay-payment/index.ts`

`create-razorpay-order` correctly stamps each booking with the exact
`razorpay_order_id` it was created for. But `verify-razorpay-payment`
took `booking_id` and `razorpay_order_id` as two **independent**
parameters from the client and never checked that they belonged to
each other. A valid signature only proves *some* real Razorpay payment
exists — not which booking it was for. Practical exploit: pay once for
a real ₹9,999 booking, then create any number of *other* bookings
priced at exactly ₹9,999 (same package again, or a different one that
costs the same) and replay that one real order_id/payment_id/signature
against each new booking_id — each gets marked "paid" for free. This
runs through the service-role key, so it completely bypasses RLS; none
of the database-level fixes elsewhere in this project touch it.

Fixed by requiring `booking.razorpay_order_id === razorpay_order_id`
(the order actually created for *this* booking) before accepting the
payment, plus a check that the same `razorpay_payment_id` hasn't
already confirmed a different booking. Also fixed the same
timing-unsafe `!==` signature comparison the webhook had (now uses a
constant-time compare).

## 8. Unauthenticated email relay (found and fixed) — CRITICAL
`supabase/functions/send-booking-email/index.ts`

This function accepted a full `booking`/`enquiry` object straight from
the request body — including the recipient address — and emailed it
verbatim, with **no authentication and no check that any of it
referred to something real**. Anyone who found the function's URL
(visible in any browser network tab on the site) could send an
arbitrarily worded, ZoomFly-branded email to any address in the world,
at your Resend account's expense: an open, unauthenticated phishing
relay riding on a verified sending domain, with real risk of getting
that domain blacklisted.

Fixed by rewriting the function to accept only a `booking_id` /
`enquiry_id`, fetch the real row server-side with the service role,
and build every field of the email — including the recipient — from
that trusted database row. The callers (`contact.html`,
`verify-razorpay-payment`) now pass IDs instead of raw objects. Also
added a rule that a "Booking Confirmed" email can only ever be sent
for a booking whose `payment_status` is actually `'paid'` in the
database, and HTML-escaped every freeform text field (name, message,
destination, etc.) before it goes into the email template, since
unescaped user-typed text in outbound HTML mail is an injection vector
in its own right even from a legitimate sender.

## 10. "Any amount for any package" — the deepest gap found this round
`supabase/functions/verify-razorpay-payment/index.ts`,
`supabase/functions/razorpay-webhook/index.ts`, `pages/payment.html`

`get-service-price` (built earlier to stop URL-parameter price
tampering) turned out to only protect the *displayed* price and the
*initial* Razorpay checkout amount — not the actual database write or
either of the two functions that mark a booking "paid." The
`bookings` table's INSERT policy is `WITH CHECK (TRUE)` (deliberately
permissive, since guest checkout needs to create a row before an
account exists), which means anyone can bypass the payment page
entirely and insert a booking claiming *any* `total_amount` for a
real, named, expensive package or hotel, then genuinely pay that
self-chosen (tiny) amount via Razorpay:

- `verify-razorpay-payment` only checked that the Razorpay-captured
  amount matched the booking's own `total_amount` — never that
  `total_amount` was the real catalog price. Fixed by looking up the
  actual price from `packages`/`hotels` (using the package/hotel a
  booking now records, see below) and rejecting anything claiming
  less than half the real price, flagging it for review instead of
  silently confirming. (The 50% floor is a deliberate, conservative
  tolerance for legitimate promo codes — an exact-match check would
  need to re-derive promo/add-on/EMI logic server-side, which is
  worth doing as a dedicated follow-up.)
- `razorpay-webhook`'s `payment.captured` handler was worse: it did
  a blind `.update(...).eq('razorpay_order_id', payment.order_id)`
  with **no amount check whatsoever**, and matched on `order_id`
  alone — a value the client can set to anything at insert time. That
  meant one single real (even tiny, unrelated) payment could confirm
  every booking row an attacker had set to share that same order_id.
  Fixed with the same amount + catalog check, applied per matching
  booking row instead of a blind bulk update.
- Neither function could actually check a catalog price before now
  because `payment.html`'s `createBooking()` calls never included
  `package_id`/`hotel_id`/`service_id` on the booking row at all —
  fixed that too, so the reference exists for the checks above to use.

This is a deeper issue than #7 (payment replay) — that was about
reusing one real payment across bookings; this is about a booking's
claimed price never being checked against reality in the first place.
Both are now closed, but the underlying permissive INSERT policy is
still there by design (needed for guest checkout) — a database-level
trigger validating price against the catalog at insert/update time
would be a more robust, defense-in-depth version of this fix, and is
worth a dedicated follow-up rather than folding into this pass.

## 11. Promo-code discount was a second bypass of #10 (found and fixed)
`supabase/functions/verify-razorpay-payment/index.ts`,
`supabase/functions/razorpay-webhook/index.ts`

The #10 fix initially checked `base_amount` against the catalog price
— but `discount_amount` (which subtracts from base to produce
`total_amount`) is entirely client-supplied too. The promo-code
lookup on the frontend (`validatePromoCode()`) only reads the
`promo_codes` table for display purposes and is never re-verified
server-side; someone could leave `base_amount` matching the catalog
price and simply set an oversized `discount_amount` to drive
`total_amount` near zero, sailing straight past the #10 check. Fixed
by checking `total_amount` (what's actually paid) against the catalog
floor instead of `base_amount` — this also happens to be a more
direct check of the thing that actually matters. The `promo_codes`
table itself is admin-write-only, so codes/discount values can't be
forged; only the amount actually *applied* to a given booking was
unverified.

## 12. Stored XSS on public pages via admin-only content (found and fixed)
`pages/hotels.html`, `pages/packages.html`, `assets/js/main.js` (`tourCard()`)

Same class of bug as #9, but on **public, unauthenticated** pages
this time rather than admin-only ones — and the shared `tourCard()`
card renderer in `main.js` is used across the homepage, destination
pages, and packages listing, so fixing it once fixes it everywhere.
The `hotels` and `packages` tables are admin-write-only today, so this
isn't exploitable by an outside attacker directly right now — but it
converts "one admin account gets phished or pastes an untrusted hotel
description" into "every visitor to the site runs the attacker's
script," which is a much bigger blast radius than the admin-only
findings in #9. Fixed by escaping hotel/package name, description,
location, badges, amenities, itinerary text, and inclusions/exclusions
before they go into `innerHTML`.

**Not yet audited this round:** `flights.html`, `cabs.html`,
`bus.html`, `destination.html`'s per-destination content blocks
(stats/tips/FAQs), and `search-results.html` — lower-traffic pages I
haven't checked for the same pattern yet. Given the hit rate tonight,
I'd expect at least one of them has it too.

## 13. Reviews: broken feature + moderation bypass (found and fixed)
`pages/package-detail.html`, new migration block in
`01_zoomfly_growth_features.sql`

Two separate real bugs stacked on the same table:

- **The review feature currently doesn't work at all.** Both the
  submission code and the display query reference a column called
  `is_approved` — but the actual schema only has `is_published`
  (`is_approved` doesn't exist anywhere). Every review submission has
  been failing outright (rejected insert), and the display query
  fails the same way, so the whole "Reviews" tab has been silently
  showing "No reviews yet" regardless of what's actually in the
  database. Fixed by correcting the column name in both places.
- **That fix alone would have been dangerous on its own.**
  `reviews.is_published` defaults to `TRUE`, and the INSERT policy
  only checks `user_id = auth.uid()` — it doesn't restrict any other
  column. The submission code does send `is_published: false`
  (intending "pending admin approval"), but nothing stopped a user
  from bypassing the page entirely and inserting a review with
  `is_published: true` directly, publishing arbitrary text on a
  public package page instantly. There is also **no admin UI anywhere
  in this project to approve, reject, or unpublish a review** — so
  simply fixing the column name without anything else would have
  quietly turned back on an unmoderated public comment system with no
  way to ever moderate it. Fixed with a trigger (same pattern as the
  earlier profiles-role fix) that forces `is_published`/`is_verified`
  to `false` on insert server-side, regardless of what the client
  sends, unless the caller is admin/service_role.

**Still needed, not built here:** an admin page to actually review and
publish pending reviews — right now fixing the bug means reviews will
correctly go into a pending queue, but nothing can promote them out of
it except editing the database directly. Worth doing as a dedicated
follow-up rather than folding into this pass.

## 14. Unlimited referral-point farming (found and fixed)
`award_referral_bonus()` in the new migration

Had no check for whether a user had already been credited for a
referral before awarding +500 points to the referrer and +250 to the
new signup. Since loyalty points redeem for real discounts (₹0.25
each, via `redeem_loyalty_points`) and this RPC is granted to any
`authenticated` user — callable directly via the Supabase client SDK
regardless of whether a page's UI calls it (a repo-wide search found
no current caller; `referral.html` only stores the incoming code in
`sessionStorage` and never actually invokes this function yet) —
anyone could call it in a loop with their own account and mint
unlimited points for themselves and an accomplice account, right now,
without needing the referral feature to be fully wired up in the UI
first. Fixed by using the existing `referred_by` column as a one-time
marker: a user can only ever be credited for a referral once. Worth
noting separately: the page's own copy says credit is awarded "when
they make their first booking," but the RPC as written awards it on
signup alone with no booking check — a product-logic gap, not a
security one, but worth resolving before this feature actually goes
live in the UI.

## 15. Messages preview panel wasn't escaped (found and fixed)
`pages/messages.html`

The chat bubble view already escaped message content correctly via an
existing `escHtml()` helper — but the thread-list sidebar preview
(showing a snippet of the last message) didn't. Message threads are
two-party (customer and admin/staff only, per the `messages` RLS
policies), so the main risk this closes isn't a random attacker — it's
a compromised or malicious staff account being able to run script in
a *customer's* browser via the preview panel, not just an admin
session. Fixed by applying the same escaping helper there.

## 16. Direct self-confirmation of bookings — the real root cause (found and fixed) — CRITICAL
New trigger in `01_zoomfly_growth_features.sql`

This is more fundamental than #7/#10/#11 above, and arguably the most
important fix of the entire session: `bookings_update_own_or_admin` in
the master schema has a `USING` clause (checks row ownership) but
**no `WITH CHECK` clause**. Per Postgres RLS semantics, when an UPDATE
policy omits `WITH CHECK`, the `USING` expression is reused as the
check on the resulting row — meaning this policy only ever verified
`user_id = auth.uid()` on the new row. It never restricted *which
columns* a user could change on their own booking. Concretely, any
logged-in user could call

```js
supabase.from('bookings')
  .update({ status: 'confirmed', payment_status: 'paid' })
  .eq('id', theirOwnBookingId)
```

directly, right now, and get any booking marked paid and confirmed for
free — without ever creating a Razorpay order, without a webhook
firing, without `verify-razorpay-payment` running at all. Every fix in
sections 7, 10, and 11 is still correct and still worth having (they
close the payment-gateway side properly), but none of them matter if
the gateway can simply be skipped by editing the booking directly.
This is the same shape of bug as the original profiles-role
self-escalation issue from the first round of fixes, just on the one
table where it matters most, and it was sitting underneath everything
else fixed tonight.

Fixed with a trigger rather than a `WITH CHECK` clause, because a
single static check can't express "allow `status` to change to
exactly one value (`cancelled`) but pin everything else" — customers
legitimately need to be able to cancel their own booking (the existing
`cancelBooking()` self-service feature depends on this), so `status`
can't simply be locked the way the payment/pricing fields can. The
trigger pins `payment_status`, `paid_at`, `paid_amount`,
`razorpay_payment_id`, `razorpay_signature`, `confirmed_at`,
`completed_at`, all refund fields, and all pricing/catalog-reference
fields (`base_amount`, `tax_amount`, `discount_amount`, `total_amount`,
`service_id`/`package_id`/`hotel_id`/`service_type`) back to their
existing values for any non-admin, non-service-role caller, and allows
`status` to move only to `cancelled` — never to `confirmed`,
`processing`, or `completed` — unless the caller is an admin or the
service role. Verified this doesn't break the one legitimate
non-admin, non-cancel `bookings` UPDATE call site
(`vendor-portal.html`, which only ever sets `status:'cancelled'`) or
the admin-only `updateBookingStatus()` helper (exempted via the same
`is_admin()` check used everywhere else in this schema).

## 9. Stored XSS across five admin pages (found and fixed)
Most admin pages already had an `esc()`/`_esc()` HTML-escaping helper
and used it consistently — good practice. But it was inconsistently
applied, in a way that forms a real pattern worth knowing about:

- **`admin-reminders.html`** never defined an escaping helper at all.
  Customer name, phone, service name, and booking ref went straight
  into `innerHTML` unescaped in the reminders queue table.
- **`admin.html`** (the main dashboard) had `esc()` defined and used
  20 times, but missed it on the enquiries table (name/phone/email,
  including inside `tel:`/`mailto:` href attributes), the bookings
  table (`guest_name`), the customers table (`full_name`/`phone`),
  and the packages grid (`title`).
- **`admin-customers.html`** escaped everywhere except three
  `tel:`/`wa.me`/`mailto:` href attributes on the customer detail
  panel — an attribute-injection variant (a phone number containing
  a stray `"` could break out of the `href` and add an event handler).
- **`admin-vendors.html`** and **`admin-agents.html`** both have a
  small `infoItem()`/`ii()` helper that builds a label/value row —
  but the helper itself doesn't escape its `value` argument, and most
  call sites passed raw vendor/agent-supplied fields (business name,
  contact name, city, GSTIN/PAN, website, **bank account name/bank
  name**) straight through. This one matters more than the others:
  vendors and agents can edit these fields themselves through their
  own self-service portals, so this was a real, low-effort path for
  a malicious vendor/agent signup to run script in an **admin's**
  authenticated session the moment staff opened that vendor's or
  agent's detail drawer to review or approve them — a stored XSS
  targeting the highest-privilege user in the system, not just a
  customer-facing one.

Fixed by escaping every one of these call sites (added the missing
helper to `admin-reminders.html`; applied the existing helper to the
missed fields elsewhere). Nothing about the RLS/authorization model
needed to change here — this was purely an output-encoding gap.

## 17. Guest booking lookup didn't actually work (found and fixed)
`pages/my-bookings.html`

The "Track Without Account" panel queried the `bookings` table
directly via the client SDK — but that table only grants `SELECT` to
`authenticated` (no grant to `anon` at all), so a genuinely logged-out
guest could never successfully run this query; it would only "work"
for someone already logged in, and even then RLS correctly restricts
results to their own bookings — which defeats the purpose of a
no-account tracker. This is a functional gap, not a security one (RLS
was protecting it correctly the whole time), but it meant a real,
advertised feature silently did nothing for the people it was built
for. The `get-guest-booking` edge function was already built to handle
exactly this case (booking ref + the email on file, checked
server-side) but nothing on this page called it. Added an email field
to the form and wired it to that function instead.

## Before you deploy

1. Run `01_zoomfly_growth_features.sql` on **staging** first, after `00_...`.
   **Before anything else, run the section 16 trigger** — it closes a way
   to mark any booking paid/confirmed with zero payment, via a direct
   table update, completely bypassing Razorpay. This one matters more
   than everything else in this file combined.
2. Re-deploy the `razorpay-webhook` edge function
   (`npx supabase functions deploy razorpay-webhook`).
3. The tier-fix migration backfills existing agents' tier/commission_rate
   immediately (`UPDATE public.agents SET updated_at = NOW()`), which will
   change some agents' displayed commission rate the moment you run it —
   worth a heads-up to your agent partners if any are currently
   misclassified.
4. Vendor payout rows still need to be created by an admin process (manual
   or a future admin UI) — this migration only builds the ledger vendors
   can *see*, not the workflow that populates it.
5. Redeploy `verify-razorpay-payment` and `send-booking-email` — both had
   critical fixes this round. If any *existing* bookings in production
   were ever confirmed via the replay path in #7, it's worth spot-checking
   recent `bookings` rows where `payment_status = 'paid'` against the
   Razorpay dashboard's actual captured payments, to see if any total
   doesn't reconcile.
6. Redeploy `razorpay-webhook` again (second fix this round, #10) and
   spot-check historical `bookings` rows for `internal_notes` starting
   with "⚠️" going forward — that's now where both the webhook and
   verify-razorpay-payment flag anything suspicious instead of silently
   confirming it.
