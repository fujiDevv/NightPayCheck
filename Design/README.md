# NightPayCheck design assets

## Screenshot set

Open `AppStore/preview.png` to review the five iPhone panels in order. The upload PNGs are in `AppStore/exports`, grouped by display size, and packaged in `AppStore/NightPayCheck-App-Store-Screenshots.zip`. The original simulator images are in `AppStore/captures`.

The editable iPhone layout is in `AppStore/source/NightPayCheck-Master.svg`. To rebuild the exports after replacing a capture or editing the copy in the generator, use Python with Pillow and resvg-py and run `python3 Design/AppStore/source/build.py` from the project directory.

## Fictional roster

The populated iPhone 17 Pro Max simulator is named **NightPayCheck Screenshots**. To reproduce the data on a different test device, open **Settings → Records → Restore from backup** and choose `SampleData/NightPayCheck-demo.json`. Restore replaces the records on that device.

The fixture follows a Chicago hospital nurse working three 19:00–07:00 shifts a week with a 30-minute unpaid meal break. The configured hourly rates are $38 base, $4.50 extra for nights and $3 extra for weekend hours. Week boundaries start on Monday.

| Pay period | Roster | Paid time | Estimated gross |
| --- | --- | --- | --- |
| Oct 19–Nov 1, 2026 | Six actual shifts, including two extended handoffs and an early start | 69h 25m | $2,988.85 |
| Nov 2–15, 2026 | Two actual and four planned shifts | 69h 10m | $2,993.58 |

For the comparison capture, select October 23 in the pay-period picker and enter **2969.35**. The app displays **$19.50 below** the completed period's estimate. A saved comparison for the same amount is included in the backup.

## Brand assets

`Mascot/NightOwl.png` is the transparent owl illustration. `BrandArchive/NightPayCheck-Icon.png` is the opaque 1024-pixel icon master used by the app.
