# NightPayCheck

Private, offline-first **night-shift pay checker for US hourly nurses** (RN/LPN/CNA, 3×12 nights).

Confirm 3–6 night shifts from text or a roster photo, set 3 rates (base + night + weekend), and get an itemized gross estimate to compare against a payslip. 40-hour weekly overtime at 1.5× base. Biweekly periods, Monday or Sunday week start. USD only.

Built as a focused sister app to [ShiftClock](../ShiftClock/README.md), reusing its proven patterns:
- Minute-resolution deterministic pay engine (UTC elapsed, time-zone classification)
- SwiftData local snapshot storage, JSON backup / CSV export (25 MB limit)
- Vision on-device roster OCR (review-gated, never auto-saves)
- StoreKit 2 lifetime unlock ($6.99, free 2 pay-period checks)

## 6 screens max

1. Welcome / privacy — offline, no account
2. Confirm roster — paste/photo → confirm shifts
3. Rates — 3 fields + night window + live sample
4. Estimate — Regular / Night / Weekend / OT / Total + assumptions footer
5. Compare — enter gross, confirm employer labels and category totals, and review the remaining difference. Saved periods retain their original line estimates. Apple Intelligence can suggest categories on supported devices; manual matching works offline.
6. Settings — backup/export, reminders, purchase/restore, delete

## Getting started

Mac + Xcode with an iOS simulator runtime (iOS 26.5 deployment target, Xcode 27 / Swift 6).

    cd NightPayCheck
    open NightPayCheck.xcodeproj

Select the **NightPayCheck** scheme and an iPhone simulator, then run.

| Command | Purpose |
| --- | --- |
| make build | Compile for an available iPhone simulator |
| make run | Build, boot simulator, install, launch |
| make test | Run the host Swift Testing suite (11 mandatory fixtures) |

## Locked v1 rules

- Pattern: 19:00–07:00 ±, 30 min unpaid meal default (0–120 configurable, paid/unpaid)
- Rates: base + night flat $/hr + weekend flat $/hr (Sat–Sun)
- OT: weekly 40h @ 1.5× base replaces regular; night + weekend **add** (same minute can earn both)
- Period: biweekly (14 days), Mon-Sun or Sun-Sat selectable
- Money: integer cents / Decimal, never Double; per-line half-up rounding, then sum
- Explicitly out: multipliers, double-time, holidays, daily OT, stacking options, tax/net, employer sync, accounts

## Verification

`make test` runs the 11 mandatory fixtures from the research blueprint §7.5:
standard 11.5h night, Fri–Sat midnight split, biweekly boundary, spring DST,
break-once, 40h edge, night+weekend stacking, overlap rejection, $1,500.75 spec
example, actuals replace plan, determinism.

Release blockers: 1¢ silent error, DST ambiguity without prompt, lost shift,
unrestorable backup, undisclosed upload, restore failure.

- [Calculation contract](docs/ENGINE.md)
- [Build blueprint](NightPayCheck_Development_Research.md)
