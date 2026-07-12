# Admin Panel — Phase 3 (Customer Communication Visibility)

No schema changes this round — `messages` and `broadcasts` tables already existed with correct RLS. This phase closes the gap between "customers can message you" / "you can send broadcasts" and "you can actually see any of it in the admin panel."

## 1. Messages Inbox — new section (`admin.html`)
- **Problem:** `messages.html` lets a logged-in customer message you about a specific booking (real table, real RLS), but there was no admin-side view at all. Messages were being sent into a black hole from your side.
- **Fix:** New "Messages" nav item (with an unread-count badge, same pattern as Enquiries/Reviews). Lists one row per booking conversation — customer name, booking ref, last message preview, timestamp, unread count. Click "View & Reply" to open the full thread and send a reply, which the customer will see next time they open `messages.html` for that booking. Opening a thread automatically marks the customer's messages in it as read.

## 2. Broadcast History — added to the existing Broadcast modal (`admin-customers.html`)
- **Problem:** The Broadcast feature (📢 button on Customer Management) could already *send* a broadcast — but there was no way to see what you'd sent before, to whom, or when. Every broadcast just vanished from view the moment you closed the modal.
- **Fix:** Added a "Recent Broadcasts" list inside the same modal, showing your last 10 broadcasts (subject, message preview, recipient group, date, recipient count where recorded). Loads automatically when you open the Broadcast modal, and refreshes right after you send a new one.

## Files changed
- `pages/admin.html` (Messages inbox section + modal + JS)
- `pages/admin-customers.html` (Broadcast history list)

## Why not more here
I checked `price_alerts` and `travel_documents` too — both are legitimate tables, but they're **customer self-service data** (a customer sets their own price alert on a package, or uploads their own passport/ID for a trip), already correctly scoped so only that customer can see their own rows. There's no missing admin feature there — building an admin screen to browse other people's uploaded ID documents would be a privacy problem, not a missing feature. I left those alone; flagging so it's clear it was a deliberate skip, not an oversight.

## Next up (Phase 4)
Site Settings overhaul — homepage banner/hero editor, SEO meta fields, social links, and actually wiring the favicon field (it's currently saved but never read into `<head>`). This is the last item from the original audit list.
