# NightPayCheck calculation and storage contract

Locked v1 rules — any change requires a fixture update and a version bump.

## Calculation contract

- Supported dates 1900–2200, whole minutes, half-open `[start, end)`. Overnight shifts stay one record; UTC instants determine elapsed time, the pay time zone classifies each minute.
- Default shift 19:00–07:00 with a single 30-minute meal break at the end of the shift (configurable 0–120 min, paid/unpaid). Paid breaks count toward paid minutes and overtime; unpaid breaks are excluded from worked and paid minutes.
- Weekly 40-hour overtime only (2400 min), fixed 1.5× base. Overtime replaces base for qualifying minutes, never doubles. Every paid minute counts toward the 40h week, including earlier shifts in the same week even outside the selected pay period.
- Night window default 19:00–07:00 (configurable; equal endpoints = all day). Weekend = Saturday + Sunday in the pay time zone.
- Precedence (shown in UI): **OT replaces regular; night + weekend ADD** — the same minute can earn both differentials. No stacking options in v1.
- Each Regular / Overtime / Night / Weekend line rounds half up to the cent, then lines sum. Money is Decimal, never Double. USD only.
- Overlapping shifts block the whole estimate instead of double-counting.
- Biweekly periods (14 days) from a user-chosen anchor; week start Monday or Sunday selectable and shared between OT grouping and preferences.
- Changing rates recalculates estimates; saved payslip entries retain their original total. Currency is fixed to USD in v1.

## Worked reference (fictional rates)

Base $38, night +$4.50, weekend +$3.00. Mon 19:00–07:00 (30m unpaid) = 11.5h → $488.75 (no weekend minutes). Fri night includes Sat 00:00–06:30 = 390 weekend minutes ($19.50) → $508.25. Sat night = $523.25. Fri + Sat + Mon = **$1,520.25** with no OT (covered by automated fixture). The blueprint's $1,500.75 simplified weekend by start day; per-minute overlap (§7.2 formula) is authoritative here.

## Storage / privacy

- SwiftData single-snapshot local store, no account, no tracking SDK.
- JSON backup preserves schedule + rates + comparisons (unencrypted, 25 MB limit shared with import). CSV exports calculation lines for one pay period.
- Roster photos and pasted text live only in the unsaved confirm flow, never in the backup.
- Reminders: next-night (1h before, up to 60 shifts) scheduled on demand; refresh after roster edits.

## Performance note

Engine is minute-resolution over ≤14-day periods plus one week of OT context (same design as ShiftClock, measured ~17 ms per 14-day estimate on host). No caching beyond the current period; failed edits preserve existing data and its estimate.
