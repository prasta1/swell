# Changelog

All notable changes to Swell are documented here.

## [Unreleased]

## [1.0.0] — 2026-06-18

### Added
- Menubar app showing live surf conditions for Santa Cruz, CA
- Crowd count via YOLOv8 CoreML model (`SurferYOLO.mlpackage`) applied to live cam frames
- Swell height and period from NDBC buoy 46042
- Tide height and direction from NOAA CO-OPS (station 9413745)
- Wind speed and offshore/onshore classification from NWS hourly forecast
- Trend chips showing whether conditions are improving or deteriorating
- Solar clock daylight gate — sampling only runs during daylight hours
- Sample history stored locally in SQLite via GRDB
- "Sample Now" button for on-demand refresh
- Launch at login via `SMAppService`
- Surf Escape: one-click calendar block with LLM-generated meeting title (EventKit + on-device generation)
