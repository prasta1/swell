# Swell

<img src="swell.png" width="120" alt="Swell icon" />

A macOS menubar app that monitors surf conditions and crowd counts at Santa Cruz, CA.

![macOS](https://img.shields.io/badge/macOS-15%2B-blue) ![Swift](https://img.shields.io/badge/Swift-6-orange)

## What it does

Swell lives in your menubar and gives you a quick read on whether it's worth paddling out:

- **Crowd count** — downloads frames from live surf cams and runs a YOLOv8 CoreML model to count surfers in the water
- **Swell** — wave height (ft) and period (s) from the NDBC 46042 buoy off Monterey
- **Tide** — current tide height and direction from NOAA CO-OPS
- **Wind** — speed and offshore/onshore classification from NWS
- **Trend chips** — shows whether conditions are improving or deteriorating over recent samples
- **Daylight gating** — only samples during daylight hours via a solar clock
- **History** — stores samples in a local SQLite database (GRDB) for trend analysis
- **Launch at login** — registers with `SMAppService`

## Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI `MenuBarExtra` |
| Computer Vision | YOLOv8 via CoreML (`SurferYOLO.mlpackage`) |
| Surf data | NDBC buoy · NOAA CO-OPS · NWS hourly |
| Video | HLS stream + snapshot frame sources |
| Storage | GRDB (SQLite) |
| Language | Swift 6 |
| Platform | macOS 15+ |

## Project layout

```
Sources/
  Conditions/     — NDBC / NOAA / NWS fetchers and parsers
  Detection/      — SurferDetector protocol + YOLODetector CoreML implementation
  Model/          — Conditions, Sample, Spot, Trend value types
  Registry/       — SpotRegistry (loads spots.json)
  Sampler/        — Orchestrates periodic sampling + SolarClock daylight gate
  Sources/        — HLSSource and SnapshotSource frame providers
  Store/          — HistoryStore (GRDB)
  UI/             — MenuContentView, MenuViewModel, ConditionsStrip, SpotRow
Resources/
  spots.json            — Spot definitions (name, cam URL, water region)
  SurferYOLO.mlpackage  — Trained CoreML model
```

## Building

Open `Swell.xcworkspace` in Xcode 16+ and build the **Swell** scheme. No additional setup required — GRDB is included as a local Swift package.

## Data sources

All data sources are free and public:

| Source | Feed |
|---|---|
| NDBC buoy 46042 | `ndbc.noaa.gov/data/realtime2/46042.txt` |
| NOAA CO-OPS tide (station 9413450, Monterey) | `api.tidesandcurrents.noaa.gov` |
| NWS hourly forecast | `api.weather.gov/gridpoints/MTR/97,82/forecast/hourly` |
| Surf cams | Public HLS / MJPEG streams |
