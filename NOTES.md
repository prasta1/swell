# Swell — Working Notes

Surf crowd-monitoring menubar app for Santa Cruz. **Shipping on `main`** — builds,
runs, warning-free; 38 deterministic tests green.

---

## Status — 2026-06-18

App is well past MVP. On `main` now:

**Core (initial build):** MenuBarExtra UI, GRDB history, SpotRegistry (10 spots),
YOLO CoreML crowd counting, NDBC/NOAA/NWS conditions, SolarClock daylight gate,
launch-at-login, onboarding window.

**This session's work (PRs #2–#4 merged):**
- **Calendar "Surf Escape"** — Settings popover (gear icon): calendar picker,
  LLM title-backend selector (Static / MLX), "Test" button. Persists last-used
  duration (T14). Permission-denied state with "Open Settings" button + duration
  in the success toast (T13). Full-width "Go Surf" button, even footer spacing.
- **Conditions fixes** — Tide and Wind were blank. Tide now uses station **9413450**
  (Monterey) + `date=today`, picking the prediction nearest *now* (9413745 has no
  predictions; `begin_date=today` was invalid). Wind now parses the real
  `/forecast/hourly` shape (string speed + compass `windDirection` → degrees).
- **Cam Viewer window** (PR #2) — `NavigationSplitView`: sidebar of spots + the
  selected feed. Live HLS via `AVPlayer`; snapshot stills auto-refresh. Opened
  from a right-click row context menu (**View Live Cam** / **Open Cam in Browser**).
- **Detection overlay** (PR #3) — **Live / Detections** toggle in the window.
  Detections mode shows a frozen analyzed frame with the water-region polygon +
  per-surfer boxes + count, and a **Re-analyze** button.
- **Tiled detection / recall fix** (PR #4) — region is split into overlapping
  ~640px tiles, detected per-tile, merged with NMS. On a real Main Beach frame
  this took the same region from **1 → 16 detections** (avg conf 0.29 → 0.98).
  Detection now runs off the main actor (sampler + overlay). Tunables in
  `YOLODetector`: `maxTilePx`, `tileOverlap`, `mergeIoU`, `minConfidence`.

---

## ▶ Next steps (resume here)

1. **Visual GUI verification (do first).** Nothing in the cam window has been run
   in the live app yet — only proven headlessly. Build, right-click a spot →
   **View Live Cam → Detections → Re-analyze**. Confirm: HLS feeds play, snapshot
   refreshes, overlay boxes align on the frame, the Live/Detections toggle works,
   and the window comes to the front (`NSApp.activate()`).
2. **Surfer-specific detector tuning.** Beachgoers detect great; surfers in a
   lineup are smaller/lower-contrast. Use the overlay on a real **Cowells** daytime
   lineup and tune `maxTilePx` / `minConfidence` / `tileOverlap`. If yolo11n still
   under-detects, try **yolo11s** (and/or a surfboard cross-check).
3. **Login-item in dev** — `SMAppService.mainApp.register()` (`SwellApp.swift`) is
   still unconditional, registering DerivedData builds as login items. Gate behind
   `#if !DEBUG` or a Settings toggle.
4. **YouTube / coverage gap** — marquee spots (Steamer Lane, Pleasure Point, The
   Hook, Capitola) are `youtube`/locked placeholders with no public cam.
   `Sampler.makeSource` falls back to `SnapshotSource` for `.youtube`. Decide:
   revisit the YouTube-Live exclusion, or build a real `YouTubeSource`.
5. **HD Relay cam #7** location still unconfirmed; not bundled.
6. **Housekeeping** — plan-doc checkboxes in `docs/superpowers/plans/` are stale
   (work done); `CHANGELOG.md` has duplicate `0.6969-beta` / `1.0.0` entries.

---

## Dev workflow (tribal knowledge)

- **Build:** `xcodebuild build -project Swell.xcodeproj -scheme Swell -destination 'platform=macOS'`
- **Deterministic tests** (skip the live-cam/network integration suites):
  ```
  xcodebuild test -project Swell.xcodeproj -scheme Swell -destination 'platform=macOS' \
    -skip-testing:SwellTests/FrameSourceIntegrationTests \
    -skip-testing:SwellTests/CowellsImageCaptureTests \
    -skip-testing:SwellTests/CowellsInferenceTests \
    -skip-testing:SwellTests/ForcedDaylightSamplerTests
  ```
  Those four hit live cams and fail offline; the other 38 are deterministic.
- **New source/test files require `xcodegen generate`** (`project.yml` → the
  generated `Swell.xcodeproj`, which is gitignored). Editing existing files does not.
- Swift 5.9 mode; build is currently **warning-free** (keep it that way).

---

## Reference

### Decisions locked in
| Question | Decision |
|---|---|
| Core mode | Continuous monitoring + history (trends, "busier than usual") |
| Monitor host | Always-on Mac (no NAS, no cloud) |
| Interface | macOS menubar app; iOS maybe later |
| Cam sources | **Strictly public cams only** — no Surfline, no YouTube Live (under review, see gap) |
| "Busy" metric | Surfers in the water (count in a per-cam water region) |
| Counting engine | Local YOLO via Core ML, tiled inference over the water region |

### Cam list (bundled in `Resources/spots.json`)
| Spot | Type | Surf value |
|---|---|---|
| **Cowells** (Dream Inn cam2) | JPEG snapshot | **GOOD — real lineup** |
| Main Beach · Wharf (Dream Inn cam1) | JPEG snapshot | low signal (mostly beach) |
| **Seacliff · Aptos** | HLS | OK beachbreak |
| SC Wharf | HLS | low signal |
| Walton Lighthouse · Seabright | HLS | low signal |
| **Pajaro Dunes** | HLS (HD Relay) | OK beachbreak |
| Pleasure Point / The Hook / Steamer Lane / Capitola | — | **locked, no public cam** |

### ⚠️ Coverage gap
The marquee spots (Steamer Lane, Pleasure Point, The Hook, Capitola) have **no
genuinely-public cam** — only Surfline (excluded) and often YouTube Live (excluded).
So strictly-public coverage = Cowells + beach/inside zones + Aptos/Pajaro
beachbreaks. Cowells is the one real point-break lineup publicly visible. May
warrant revisiting the YouTube-Live exclusion (see next-steps #4).

### Specs / plans
- Design spec: `docs/superpowers/specs/2026-06-17-swell-design.md`
- Initial plan: `docs/superpowers/plans/2026-06-17-swell.md`
- Calendar Surf Escape plan: `docs/superpowers/plans/2026-06-18-calendar-surf-escape.md`
