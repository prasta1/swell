# Swell Detection Tuning Guide

This document explains how to tune the YOLO detector for better surfer detection.

## Quick Start

### 1. Analyze Current Setup
```bash
# Run the analysis tool
python3 scripts/tune-detection.py cowells
python3 scripts/tune-detection.py steamer-lane
```

### 2. Run the App and Test Visually
1. Build and run Swell
2. Right-click a spot → "View Live Cam"
3. Click "Detections" in the toolbar
4. Click "Re-analyze" to see current detection
5. Click "Edit Region" to adjust water region polygon
6. Click "Save Region" when satisfied

## Detector Parameters (in YOLODetector.swift)

| Parameter | Current | Description | Tuning Tips |
|---|---|---|---|
| `maxTilePx` | 640 | Max tile dimension for inference | Increase for very large crops (distant surfers) |
| `tileOverlap` | 0.2 | Overlap between adjacent tiles | Increase if surfers are missed at tile boundaries |
| `mergeIoU` | 0.45 | IoU threshold for duplicate removal | Decrease if same surfer counted multiple times |
| `minConfidence` | 0.25 | Default minimum score to keep a detection | Decrease to catch more borderline detections. Overridable per call — see below |

## Water Region Analysis

### Cowells (2448×2048)
- **Current region**: `[[0.05,0.45],[0.95,0.40],[0.95,0.75],[0.05,0.80]]`
- **Crop size**: 2203×819 pixels (large!)
- **Tiles**: 4×2 = 8 tiles needed
- **Issue**: Wide crop may include too much beach area

### Steamer Lane (1280×720)
- **Current region**: `[[0.05,0.35],[0.95,0.35],[0.95,0.82],[0.05,0.82]]`
- **Crop size**: 1152×338 pixels
- **Tiles**: 2 tiles needed
- **Status**: Good starting point, may need lineup focus

## Tuning Recommendations

### For Surfers in Lineup (smaller/distant)
If detections are missing surfers in the water:

1. **Try a lower confidence threshold.** This one is a parameter, not just a constant —
   pass it per call without touching the default:

   ```swift
   try detector.count(in: frame, region: region, minConfidence: 0.15)
   ```

   To see the whole curve at once, run the sweep in `DetectionDiagnosticsTests`:

   ```bash
   xcodebuild test -project Swell.xcodeproj -scheme Swell -destination 'platform=macOS' \
     -only-testing:SwellTests/DetectionDiagnosticsTests
   ```

   If the count is flat across the sweep, the threshold is not your bottleneck — the water
   region or tile size is. Change `YOLODetector.minConfidence` only once a sweep shows a
   value you want as the new default.

2. **Increase tile size** for distant surfers:
   ```swift
   static let maxTilePx: CGFloat = 800  // Default: 640
   ```

3. **Widen overlap** if surfers are missed at boundaries:
   ```swift
   static let tileOverlap: CGFloat = 0.3  // Default: 0.2
   ```

### For Beach Cams (low signal)
If you see false positives from beachgoers:

1. **Narrow the water region** to focus on water only
2. **Keep confidence at 0.25** to filter false positives
3. **Consider marking as `lowSignal`** in spots.json if consistently poor

## Alternative Models

If yolo11n consistently under-detects:

1. **Try yolo11s** (larger, more accurate but slower)
2. **Try yolo11m** (even larger, best accuracy)
3. Export as NMS-pipeline CoreML for compatibility

## Testing Changes

```bash
# Run all tests
xcodebuild test -project Swell.xcodeproj -scheme Swell -destination 'platform=macOS' \
  -skip-testing:SwellTests/FrameSourceIntegrationTests \
  -skip-testing:SwellTests/CowellsImageCaptureTests \
  -skip-testing:SwellTests/CowellsInferenceTests \
  -skip-testing:SwellTests/ForcedDaylightSamplerTests

# Run detector-specific tests
xcodebuild test -project Swell.xcodeproj -scheme Swell -destination 'platform=macOS' -only-testing:SwellTests/TilingTests
```

## Save Water Region Changes

When tuning via the Cam Viewer:
1. Edit region in the UI
2. Click "Save Region"
3. For permanent changes, copy the points into `Resources/spots.json`

The saved regions are stored in UserDefaults under `com.peregrine.Swell.waterRegionOverrides`.