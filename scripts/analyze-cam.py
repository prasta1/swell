#!/usr/bin/env python3
"""
Swell Detection Analyzer
Fetches cam frames, runs YOLO detection, and outputs tuning recommendations.
Requires: pip install Pillow (for image analysis)
"""

import io
import json
import sys
import urllib.request
from pathlib import Path

from PIL import Image

# Constants matching YOLODetector.swift
MAX_TILE_PX = 640
TILE_OVERLAP = 0.2
MERGE_IU = 0.45
MIN_CONFIDENCE = 0.25


def load_spots():
    spots_path = Path(__file__).parent.parent / "Resources" / "spots.json"
    with open(spots_path) as f:
        return json.load(f)


def fetch_image(url):
    """Fetch image from URL."""
    try:
        with urllib.request.urlopen(url, timeout=10) as response:
            if response.status == 200:
                data = response.read()
                return Image.open(io.BytesIO(data))
    except Exception as e:
        print(f"  Fetch error: {e}")
    return None


def region_bounds(points, img_width, img_height):
    xs = [p[0] * img_width for p in points]
    ys = [p[1] * img_height for p in points]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    return (min_x, min_y), (max_x, max_y), (max_x - min_x, max_y - min_y)


def tile_grid(crop_w, crop_h):
    cols = max(1, int(crop_w / MAX_TILE_PX + 0.999))
    rows = max(1, int(crop_h / MAX_TILE_PX + 0.999))
    return cols, rows, cols * rows


def analyze_spot(spot, fetch=False):
    print(f"\n===== {spot['name']} =====\n")

    url = spot.get("source", {}).get("url", "")
    kind = spot.get("source", {}).get("kind", "")
    surf_val = spot.get("surfValue", "")

    print(f"Source: {kind}")
    print(f"Surf value: {surf_val}")

    points = spot.get("waterRegion", {}).get("points", [])
    if not points:
        print("No water region configured")
        return

    if fetch and url:
        print(f"Fetching frame...")
        img = fetch_image(url)
        if img:
            img_w, img_h = img.size
            print(f"Actual frame: {img_w}x{img_h}")
        else:
            print("Could not fetch frame, using typical dimensions")
            img_w, img_h = (1280, 720) if kind == "youtube" else (2448, 2048)
    else:
        # Typical dimensions for each source type
        img_w, img_h = (1280, 720) if kind == "youtube" else (2448, 2048)

    (min_x, min_y), (max_x, max_y), (crop_w, crop_h) = region_bounds(
        points, img_w, img_h
    )

    print(
        f"\nWater region crop: ({int(min_x)}, {int(min_y)}) to ({int(max_x)}, {int(max_y)})"
    )
    print(f"Crop size: {int(crop_w)}x{int(crop_h)} pixels")

    cols, rows, n_tiles = tile_grid(crop_w, crop_h)
    print(f"Tile grid: {cols}×{rows} = {n_tiles} tiles (max {MAX_TILE_PX}px)")

    # Tuning suggestions
    print("\n🔧 Tuning suggestions:")

    if n_tiles > 1:
        step_x = crop_w / cols
        step_y = crop_h / rows
        overlap_px_x = step_x * TILE_OVERLAP
        overlap_px_y = step_y * TILE_OVERLAP
        tile_w = step_x + 2 * overlap_px_x
        tile_h = step_y + 2 * overlap_px_y
        print(
            f"  - Each tile: ~{int(tile_w)}x{int(tile_h)} pixels ({int(step_x)}×{int(step_y)} steps + {int(TILE_OVERLAP * 100)}% overlap)"
        )

    if crop_w > 1500 or crop_h > 700:
        print(f"  - Consider narrowing region to reduce tiles and focus on lineup")

    if surf_val == "good":
        print(f"  - Good surf spot: ensure region captures the peak/lineup")
    elif surf_val == "lowSignal":
        print(f"  - Low signal: this cam may not show surfers clearly")

    if n_tiles == 0:
        print(f"  - Warning: region may be degenerate (too small to tile)")


def main():
    spots = load_spots()
    args = sys.argv[1:]

    fetch = "--fetch" in args
    show_list = "--list" in args
    args = [a for a in args if not a.startswith("--")]

    if show_list:
        for s in spots:
            print(f"  {s['id']}: {s['name']} ({s['surfValue']})")
    elif args:
        target = args[0].lower()
        spot = next((s for s in spots if s["id"].lower() == target), None)
        if spot:
            analyze_spot(spot, fetch=fetch)
        else:
            print(f"Spot '{target}' not found. Use --list to see available spots.")
    else:
        print("Analyzing all active spots...\n")
        for spot in spots:
            surf_val = spot.get("surfValue", "")
            if surf_val != "locked" and spot.get("source", {}).get("url"):
                analyze_spot(spot, fetch=fetch)


if __name__ == "__main__":
    main()
