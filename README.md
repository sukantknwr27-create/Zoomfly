# ZoomFly — Delivery

## Documentation
All project documentation (setup guides + full changelog history) lives
in [`docs/`](docs/INDEX.md) instead of being scattered across the repo
root. **Start there** — `docs/INDEX.md` is the map, and its changelog
table is in chronological order (oldest → newest) so you can see what
shipped, when.

## What to actually run right now
This file intentionally does **not** list specific migrations or
action items — those change every round, and a static list here goes
stale the moment the next round ships (which already happened once —
this file used to say "that's it, no other changes needed" after
Round 5, which stopped being true as soon as Round 6 shipped).

For the current "what do I need to run/deploy" list:
1. Open `docs/INDEX.md` → find the **last row** in the Changelogs
   table — that's the most recent round.
2. Open that file's own "Before you deploy" / "Files changed" section
   — each changelog is self-contained and lists exactly what's new for
   that round.
3. If you're not sure whether an earlier migration was ever run
   against your live DB, migrations are idempotent (`IF NOT EXISTS` /
   `ON CONFLICT DO NOTHING` throughout) — safe to re-run in order if
   in doubt, staging first. All 19 migrations (`00` through `18`) are
   present in `supabase/migration/`, no gaps.

## Note on image uploads
Image uploads stay on **Supabase Storage**. No separate setup needed —
uploads work the same way across every round covered in `docs/`.

## Reading order for a new contributor
See `docs/INDEX.md` → "Reading order for a new contributor." Note that
`SETUP_GUIDE.md` and `FILE_PLACEMENT_GUIDE.md` in `docs/` describe the
**original, earliest** version of the project (single migration file,
4 edge functions, `js/` instead of `assets/js/`) and are kept only as
historical background — see the notice at the top of each for what's
actually current.

## Known open items (not blockers, tracked deliberately)
- `pages/destination.html` (singular) still runs on hardcoded
  `DEST_DATA`, not the live `destinations` table — flagged in
  `CHANGES_EMOJI_REMOVAL_AND_ICON_FIXES.md` as needing a scoping
  decision before rebuilding.
- The site's icon system uses styled emoji (`<span class="emoji-icon">`),
  not SVG, despite an earlier changelog claiming an SVG pass — see the
  correction note at the top of `CHANGES_EMOJI_REMOVAL_AND_ICON_FIXES.md`.
  It works and is visually consistent; whether to redo it as SVG is a
  design call, not a bug.
- No real flight/rail consolidator (TBO/Tripjack/Riya/railYatri) is
  wired in yet — everything runs on `MockFlightProvider`/`MockRailProvider`,
  clearly labelled `isMock:true`. Activating a real provider from
  Admin → API Providers before it's implemented fails loudly by design
  rather than silently serving mock data as real.
