# Swell — Design Spec

**Date:** 2026-06-17
**Status:** Approved (pending spec review)
**Author:** Patrick (with Claude)

## Purpose

A macOS menubar app that monitors publicly available webcams at Santa Cruz–area
surf spots, counts surfers in the water, and surfaces a glanceable "should I go
surf?" read — crowd level relative to what's typical for the time, alongside
basic surf conditions. Runs continuously on an always-on Mac and keeps local
history so it can say "emptier than usual," not just "4 surfers."

## Goals / Non-goals

**Goals (v1)**
- Continuous background sampling of public cams (~15 min cadence, daylight only).
- Count surfers in a per-cam water region using a local, on-device model.
- Show per-spot crowd level *relative to that spot's own typical* for weekday×hour.
- Show basic conditions (swell, tide, wind) from free public APIs.
- Single glanceable menubar dropdown.
- Keep local history for trend baselines.

**Non-goals (v1)**
- iOS/watchOS app (possible later; the data layer stays reusable).
- Surfline or any paywalled/account-gated cams.
- YouTube Live cams (deliberately deferred — see Coverage below).
- Cloud sync, accounts, notifications/alerts (possible v2).

## Decisions (locked during brainstorming)

| Topic | Decision |
|---|---|
| Core mode | Continuous monitoring + local history |
| Host | Always-on Mac (no NAS, no cloud) |
| Interface | Single SwiftUI `MenuBarExtra` app; monitors + displays |
| Cam sources | Strictly public cams in v1; **source layer pluggable** so YouTube can be added later without rework |
| Conditions | Yes — swell/tide/wind from free NOAA/NDBC/NWS APIs |
| "Busy" metric | Surfers counted in a per-cam water region |
| Counting engine | Local YOLO via Core ML, behind a `SurferDetector` protocol (swappable) |
| Storage | GRDB/SQLite (append-only time-series; easy median queries) |

## Coverage reality (drives the design)

Verified public cams (discovery workflow `wf_12aee607-ccf`): 7 distinct live
public streams. The marquee spots — Steamer Lane lineup, Pleasure Point, The
Hook, Capitola — have **no public cam** (Surfline/YouTube only). Implications:

- The app delivers a strong read for **Cowells** (the one publicly visible real
  point/cove lineup) and the **Aptos/Pajaro beachbreaks**.
- Beach/inside cams (Main Beach, Wharf, Seabright) are included but flagged
  "low signal" because their framing rarely shows a true lineup.
- Gap spots are listed but **locked** in the UI, with the pluggable-source seam
  visible, so adding a YouTube source later is a drop-in.

### Cam registry (v1 seed)

| Spot | View | Source type | Endpoint | Surf value |
|---|---|---|---|---|
| Cowells | Dream Inn cam2, WNW over cove → Lighthouse Pt | JPEG snapshot (~30 min) | `cmgp-coastcam.s3-us-west-2.amazonaws.com/cameras/dreaminn/latest/c2_snap.jpg` | Good (real lineup) |
| Main Beach / Cowell inside | Dream Inn cam1, looking E | JPEG snapshot | `…/dreaminn/latest/c1_snap.jpg` | Low signal |
| Seacliff (Aptos) | State Parks, cement-ship beachbreak | HLS | `video.parks.ca.gov/Seacliff/Seacliff.stream/playlist.m3u8` | OK beachbreak |
| SC Wharf / Main Beach | WebCOOS, NE toward Boardwalk | HLS | `stage-ams.srv.axds.co/stream/adaptive/cencoos/santacruzwharf/hls.m3u8` | Low signal |
| Walton Lighthouse / Seabright | UCSC/WebCOOS | HLS | `stage-ams-nfs.srv.axds.co/stream/adaptive/ucsc/walton_lighthouse/hls.m3u8` | Low signal |
| Pajaro Dunes | HD Relay beachbreak | HLS | `manage.hdrelay.com/player/63a4e361d0964a1867dc17a2` | OK beachbreak |
| HD Relay (location TBD) | unidentified | HLS | `manage.hdrelay.com/player/eaef7bd0-f716-4b37-9d9a-9ed172069e9d` | Verify before include |

Each cam entry carries a hand-drawn **water-region polygon** (normalized coords)
marking where surfers appear, used to crop before detection.

## Architecture

Single SwiftUI app, `MenuBarExtra` scene, launch-at-login. Background sampling
and the glanceable UI live in one process. Modules talk through protocols so
each is independently testable and the ML / cam-source pieces are swappable.

| Unit | Responsibility | Seam |
|---|---|---|
| `SpotRegistry` | Loads bundled `spots.json`: spots, source descriptors, water-region polygons | Codable decode |
| `FrameSource` (protocol) | `currentFrame() async throws -> CGImage` for one cam. Impls: `SnapshotSource` (HTTP JPEG GET), `HLSSource` (one-frame grab via AVFoundation/ffmpeg). Future: `YouTubeSource` | **Pluggable cam layer** |
| `SurferDetector` (protocol) | `count(in frame: CGImage, region: Polygon) -> Detection` (count + boxes). Impl: `YOLODetector` (Core ML, tiled inference, NMS, person class) | Swappable ML |
| `Sampler` | Scheduler: every ~15 min during daylight, walk registry → source → crop → detect → persist | Daylight gate from solar times |
| `HistoryStore` | Append-only `(spotID, timestamp, count, confidence, conditionsSnapshot)`; computes per-spot weekday×hour rolling median | GRDB/SQLite |
| `ConditionsService` | ~hourly fetch: NDBC buoy 46042 (swell ht/period), NOAA tide, NWS wind; cached | Independent of vision path |
| `MenuBarController` + SwiftUI views | Glanceable dropdown: trend chip, count, conditions strip, freshness, locked gap spots | Observes `HistoryStore` |

### Data flow (per sample)

```
Sampler.tick (daylight)
  └─ for each spot in SpotRegistry:
       FrameSource.currentFrame()      // JPEG GET or HLS frame grab
         → crop to water-region polygon
         → YOLODetector.count(in:region:)   // tiled, NMS, person class
         → HistoryStore.append(spotID, count, confidence, conditions)
ConditionsService.tick (hourly) → cache → attached to each sample row
UI observes HistoryStore → renders count + trend-vs-typical + freshness
```

### Why these boundaries

- **Snapshot vs HLS asymmetry is real.** Cowells (best lineup) is a ~30-min
  JPEG snapshot, so its freshness is capped regardless of sample cadence. Every
  count is stored and displayed with its true frame timestamp.
- **"Busy" requires a baseline.** Raw counts are meaningless without context;
  `HistoryStore` provides per-spot, per-(weekday×hour) rolling medians, and the
  UI renders the *relative* trend.
- **Low-signal honesty.** Detector confidence + cam framing quality gate whether
  a count is shown as a real reading or flagged "low signal."

## UI

Menubar dropdown (mockup approved):
- Header: app + last-update time.
- Conditions strip: swell (ht·period), tide (value + direction), wind (speed + on/offshore).
- Spot rows (best-surf-value first): name, count, trend chip
  (green "emptier than usual" / amber "about typical" / red "busier than usual"),
  per-row freshness ("snapshot · 11 min ago" vs "live · 1 min ago").
- Marginal cams dimmed + "low signal".
- Gap spots listed but locked ("—", "no public cam — source pluggable later").
- Footer: Sample now · Settings · Quit.

## Error handling (system boundaries only)

- **Cam fetch failure** (timeout, 404, dead host): mark that spot's reading
  stale; keep last good value with its timestamp; retry next tick. The
  `stage-ams-nfs` Walton host 404s on the `prod` variant — registry pins the
  working host; a host change surfaces as a stale spot, not a crash.
- **Detector failure / empty region**: record a null count (not zero); UI shows
  "—" rather than a misleading 0.
- **Conditions API failure**: show last cached values dimmed; never block the
  vision path.
- No defensive handling beyond these external boundaries.

## Testing

- `SpotRegistry`: decode fixture `spots.json`; polygon parsing.
- `SurferDetector`: run `YOLODetector` against a handful of saved frames with
  known surfer counts; assert within tolerance.
- `HistoryStore`: append + median computation over synthetic weekday×hour data.
- `ConditionsService`: parse fixture NDBC/NOAA/NWS payloads.
- `FrameSource` impls: integration-tested against live endpoints (manual/CI-opt).

## Build / tooling

Per workspace conventions: xcodegen (`project.yml` → generated `.xcodeproj`),
SwiftUI, macOS target. GRDB via SwiftPM. Core ML model bundled. Verify build
with `xcodebuild -project swell.xcodeproj -scheme Swell -destination
'platform=macOS' build` after Swift changes.

## Open items (resolve during planning/impl)

1. Identify HD Relay cam #7's location; include only if it shows a real break.
2. Source a YOLO Core ML model (e.g. YOLOv8n converted) and confirm small/distant
   surfer recall is adequate; tiling parameters per cam.
3. HLS single-frame grab approach: AVFoundation `AVAssetImageGenerator` on the
   live playlist vs. bundling ffmpeg. Prefer AVFoundation (no dependency).
4. Confirm NDBC 46042 is the right buoy for Santa Cruz inner bay vs. an
   alternative; tide station id.
