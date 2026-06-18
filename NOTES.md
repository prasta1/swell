# Swell — Brainstorm Progress (2026-06-11)

Surf crowd-monitoring app for Santa Cruz spots. Mid-design via the
superpowers:brainstorming skill — **design not yet presented/approved, no code written.**

## Decisions locked in

| Question | Decision |
|---|---|
| Core mode | Continuous monitoring + history (trends, "busier than usual") |
| Monitor host | Always-on Mac (no NAS, no cloud) |
| Interface | macOS menubar app — single app does monitoring + display; iOS maybe later |
| Cam sources | **Strictly public cams only** — no Surfline (paywalled/ToS), no YouTube Live |
| Conditions | Yes — basic swell/tide/wind from free NOAA/NDBC/NWS APIs alongside crowds |
| "Busy" metric | Surfers in the water (count in a per-cam water region) |
| Counting engine | **Local YOLO via Core ML** (tiled inference over cropped water region), behind a swappable `CrowdCounter` protocol. Rejected: Apple Vision (misses tiny surfers), Claude API (~$10-14/mo, chosen against) |

## Sketch of the design (not yet approved)

Single SwiftUI menubar app (MenuBarExtra, launch-at-login):
CamRegistry (config of spots/cam URLs/water regions) → FrameGrabber (JPEG snapshot
or HLS frame) → SurferDetector (YOLO/CoreML, tile + NMS, person class) → local store
(history) → menubar UI with counts, trends, conditions strip. Scheduler samples every
~10-15 min during daylight only. Conditions fetched on a slower cadence.

## Cam discovery RESULTS (workflow wf_12aee607-ccf, completed 2026-06-17)

29 candidates → 7 distinct GENUINELY-PUBLIC verified live streams:

| # | Spot / view | Type | Stream URL | Surf value |
|---|---|---|---|---|
| 1 | **Cowells** (Dream Inn cam2, WNW over cove → Lighthouse Pt) | JPEG snapshot (~30 min) | cmgp-coastcam.s3-us-west-2.amazonaws.com/cameras/dreaminn/latest/c2_snap.jpg | **GOOD — real lineup** |
| 2 | Cowell inside / Main Beach (Dream Inn cam1, looking E) | JPEG snapshot | …/dreaminn/latest/c1_snap.jpg | Marginal (mostly beach) |
| 3 | **Seacliff State Beach** (Aptos, cement-ship beachbreak) | HLS | video.parks.ca.gov/Seacliff/Seacliff.stream/playlist.m3u8 | OK beachbreak |
| 4 | SC Wharf / Main Beach (WebCOOS, NE toward Boardwalk) | HLS | stage-ams.srv.axds.co/stream/adaptive/cencoos/santacruzwharf/hls.m3u8 | Marginal |
| 5 | Walton Lighthouse / Seabright-Twin Lakes (UCSC/WebCOOS) | HLS | stage-ams-nfs.srv.axds.co/stream/adaptive/ucsc/walton_lighthouse/hls.m3u8 | Marginal (mostly beach) |
| 6 | **Pajaro Dunes** (far south, Watsonville beachbreak) | HLS (HD Relay) | manage.hdrelay.com/player/63a4e361d0964a1867dc17a2 | OK beachbreak |
| 7 | HD Relay cam (location not fully pinned) | HLS | manage.hdrelay.com/player/eaef7bd0-f716-4b37-9d9a-9ed172069e9d | TBD |

Rejected: Santa Cruz Harbor launch-ramp/channel cam (no surf), digsantacruz "Harbor Beach"
page (dead DNS; real feed = #5).

### ⚠️ KEY COVERAGE GAP (decision needed)
The marquee spots — **Steamer Lane lineup, Pleasure Point, The Hook/38th Ave, Capitola** —
have NO genuinely-public cam. Their only cams are **Surfline** (excluded) and, often,
**YouTube Live** (excluded by earlier decision). So strictly-public coverage = Cowells +
beach/inside zones + Aptos/Pajaro beachbreaks. Cowells is the one real point-break lineup
publicly visible. This may warrant revisiting the YouTube-Live exclusion.

## ▶ STATUS: all 12 tasks implemented (2026-06-17)

**Branch:** `feature/initial-build`. App builds, launches, runs. **13/13 tests green.**
All 12 plan tasks committed (T1 `b42e05a` … T12 `410931f`).

**Verified working:** scaffold + GRDB + MenuBarExtra; model types; SpotRegistry +
10-spot cam list (now actually bundled); HistoryStore + weekday×hour median + trend;
ConditionsService parsers; FrameSource/Snapshot/HLS; YOLODetector (Vision pipeline
proven — 3 detections on canonical image); SolarClock + Sampler; menubar UI; app
wiring + launch-at-login. App launches, creates its SQLite store, daylight gate
correctly suppresses night sampling.

### ⚠️ Two real follow-ups (not done)
1. **Detector recall** — yolo11n at 640px finds 0 surfers on a real Cowells frame
   (too small/distant). Needs the plan's Task 9 Step 5: tile the water region
   (and/or yolo11s, and/or surfboard cross-check), tuned against real daytime
   frames with your eyes. The pipeline is correct; recall is the open work.
2. **Login-item in dev** — `SMAppService.mainApp.register()` runs unconditionally,
   so it registered the DerivedData build as a login item. Consider gating behind
   `#if !DEBUG` or a Settings toggle. Was registered once during launch test.

### Also pending
- Populated-UI visual check (best in daylight, ~6am–8pm, when cams have surfers
  and conditions fetch fires).
- HD Relay cam #7 location + buoy/tide/NWS-gridpoint URL confirmation (spec open items).

**Build/test:** `xcodebuild test -project Swell.xcodeproj -scheme Swell -destination 'platform=macOS'`

## Completed steps

1. ✅ Cam-discovery workflow → 7 verified public cams (see table above)
2. ✅ Design presented + approved (architecture + cam list + menubar mockup)
3. ✅ Spec: `docs/superpowers/specs/2026-06-17-swell-design.md`
4. ✅ Plan: `docs/superpowers/plans/2026-06-17-swell.md` (12 tasks)
5. ⏳ Implementing — Task 1 done, Tasks 2–12 remain
