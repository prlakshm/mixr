# App Store media (landscape)

## Why the original files failed

| File | Actual | App Store wants |
|---|---|---|
| `build-now.mp4` etc. | **1900 × 874**, most **under 15s** | Previews: **1920 × 886**, **15–30s**, H.264 |
| First Mixr screenshots | **1320 × 2868 portrait** | Screenshots: **2868 × 1320 landscape** (6.9") |

Connect rejects anything that is not an exact pixel size. 1900×874 is 20px short. 10s clips are too short.

## Upload these

### Screenshots — iPhone 6.9" Display (landscape)

Folder: `screenshots/`

1. `01-build-now.png` — mashup timeline
2. `02-clip-menu.png` — clip edit
3. `03-effect-tray.png` — effects row
4. `04-transition-beats.png` — arranged mix
5. `05-sfx-library.png` — SFX panel

All **2868 × 1320**, PNG, no transparency.

Do **not** upload the old portrait files in `screenshots-portrait-unused/`.

### App previews — iPhone 6.9" Display (landscape)

Folder: `previews/`

Apple allows **3 videos max**. Use:

1. `01-build-now.mp4` (15s)
2. `03-effect-tray.mp4` (24s)
3. `02-clip-menu.mp4` (15s)

Spare: `04-transition-beats.mp4`

All **1920 × 886**, H.264 High, 30 fps, 15–30s.

In Connect: drag the **video** into the App Preview slot (left of screenshots), not the screenshot well.
