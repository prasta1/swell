# Changelog

All notable changes to Swell are documented here.

## [Unreleased]

## [1.0.0] — 2026-06-18

### Added
- Menubar app showing live surf conditions for Santa Cruz, CA
- Crowd count via Ultralytics YOLO11n CoreML model (`SurferYOLO.mlpackage`, stock COCO `person` class) applied to live cam frames
- Swell height and period from NDBC buoy 46042
- Tide height and direction from NOAA CO-OPS
- Wind speed and offshore/onshore classification from NWS hourly forecast
- Trend chips showing whether conditions are emptier/busier than usual
- Solar clock daylight gate — sampling only runs during daylight hours
- Sample history stored locally in SQLite via GRDB
- "Sample Now" button for on-demand refresh
- Launch at login via `SMAppService`
- Surf Escape: one-click calendar block with LLM-generated meeting title (EventKit + on-device generation)
- Cam Viewer window with live feed and detection overlay
- Interactive water-region polygon editor for tuning each spot's detection area
- Tiled detection with non-maximum suppression for improved surfer recall
- YouTube live thumbnail support for Steamer Lane cam

### Fixed
- Tide station changed to 9413450 (Monterey) with `date=today` parameter; Santa Cruz station 9413745 has no predictions
- Wind parsing updated for NWS `/forecast/hourly` API response format
- Detection now runs off-main-actor to prevent UI freezing during analysis
