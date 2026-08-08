# ZoomFly — Documentation Index

All project documentation now lives in this `docs/` folder instead of
being scattered across the repo root. This file is the map — start
here.

## Setup & Reference

| Doc | What it's for |
|---|---|
| [SETUP_GUIDE.md](SETUP_GUIDE.md) | Complete backend setup — Supabase, Razorpay, Resend, env vars, deployment |
| [ADMIN_SETUP.md](ADMIN_SETUP.md) | Admin portal setup — creating the first admin account, login flow |
| [FILE_PLACEMENT_GUIDE.md](FILE_PLACEMENT_GUIDE.md) | Where each delivered file goes in the GitHub repo / deployment structure |
| [SESSION_SUMMARY.md](SESSION_SUMMARY.md) | Snapshot of the full site's state as of that session — useful as a "what exists" reference |
| [AUDIT_ISSUES.md](AUDIT_ISSUES.md) | Full code-level audit — what was checked, what was fixed, what's confirmed working, what's an open design decision |

## Changelogs (chronological — oldest first)

| Doc | What it covers |
|---|---|
| [CHANGES.md](CHANGES.md) | Earliest recorded delivery vs. original upload |
| [CHANGES_ROUND2.md](CHANGES_ROUND2.md) | Round 2 fixes |
| [CHANGES_ADMIN_PHASE1.md](CHANGES_ADMIN_PHASE1.md) | Admin panel — quick wins |
| [CHANGES_ADMIN_PHASE2.md](CHANGES_ADMIN_PHASE2.md) | Admin panel — Blog / FAQ / Careers CMS |
| [CHANGES_ADMIN_PHASE3.md](CHANGES_ADMIN_PHASE3.md) | Admin panel — customer communication visibility |
| [CHANGES_ADMIN_PHASE4.md](CHANGES_ADMIN_PHASE4.md) | Admin panel — site settings overhaul |
| [CHANGES_FULL_ADMIN_CONSOLIDATION.md](CHANGES_FULL_ADMIN_CONSOLIDATION.md) | Consolidating admin functionality into one page |
| [CHANGES_EMOJI_REMOVAL_AND_ICON_FIXES.md](CHANGES_EMOJI_REMOVAL_AND_ICON_FIXES.md) | Site-wide emoji removal, real-photo rendering, icon bug fixes |
| [CHANGES_ROUND5.md](CHANGES_ROUND5.md) | Round 5 — fixes from the issues PDF |
| [CHANGES_ROUND6.md](CHANGES_ROUND6.md) | Round 6 fixes |
| [CHANGES_FLIGHT_BOOKING.md](CHANGES_FLIGHT_BOOKING.md) | Real flight booking backend — six-stage pipeline, pluggable `FlightProvider` |
| [CHANGES_API_PROVIDERS_AND_RAIL.md](CHANGES_API_PROVIDERS_AND_RAIL.md) | **Latest.** Pluggable, admin-editable API provider system (flight + rail) and the real train booking pipeline replacing the old fake `TRAIN_DB` |

## Reading order for a new contributor

1. `SETUP_GUIDE.md` — get the backend running
2. `ADMIN_SETUP.md` — get into the admin panel
3. `SESSION_SUMMARY.md` — see what already exists
4. Changelogs, oldest → newest, for the *why* behind each decision

## Convention going forward

New changelogs get added to this folder (not the repo root) and get
a row added to the table above, in date order. Keep the root clean —
`README.md` is the only markdown file that stays at the top level, as
the entry point that points here.
