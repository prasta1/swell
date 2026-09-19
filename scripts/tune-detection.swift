#!/usr/bin/xcrun swift
//
// Swell Detection Tuning Tool
// Analyzes a frame from a spot and outputs detection statistics for water region tuning
//
// Usage: xcrun swift scripts/tune-detection.swift [spot-id]
//        (xcrun, not plain `swift` — a swiftly toolchain on PATH may shadow Xcode's)
//

import Foundation
import CoreGraphics
import CoreImage

// MARK: - Models
struct NormalizedPoint: Codable, Equatable {
    var x: Double
    var y: Double

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self)
        y = try c.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
    }
}

struct WaterRegion: Codable, Equatable {
    var points: [NormalizedPoint]
}

struct Spot: Codable {
    var id: String
    var name: String
    var source: SourceDescriptor
    var waterRegion: WaterRegion
    var surfValue: String
    var region: String
}

struct SourceDescriptor: Codable {
    var kind: String
    var url: String
}

// MARK: - Spot loading
func loadSpots() throws -> [Spot] {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Resources/spots.json")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode([Spot].self, from: data)
}

// MARK: - Frame fetching
enum FrameSourceError: Error { case unreachable, decodeFailed }

func fetchFrame(from url: URL) async throws -> CGImage {
    let (data, response) = try await URLSession.shared.data(from: url)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw FrameSourceError.unreachable
    }
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        throw FrameSourceError.decodeFailed
    }
    return img
}

// MARK: - Water region analysis
func regionBounds(in image: CGImage, region: WaterRegion) -> (crop: CGRect, fullFrame: Bool) {
    let w = Double(image.width), h = Double(image.height)
    let xs = region.points.map { $0.x * w }
    let ys = region.points.map { $0.y * h }
    guard let minX = xs.min(), let maxX = xs.max(),
          let minY = ys.min(), let maxY = ys.max(), maxX > minX, maxY > minY else {
        return (CGRect(x: 0, y: 0, width: w, height: h), true)
    }
    return (CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY), false)
}

func formatTileGrid(crop: CGRect, maxTile: CGFloat, overlap: CGFloat, imageBounds: CGRect) -> [CGRect] {
    let cols = max(1, Int(ceil(crop.width / maxTile)))
    let rows = max(1, Int(ceil(crop.height / maxTile)))
    let stepX = crop.width / CGFloat(cols)
    let stepY = crop.height / CGFloat(rows)
    let padX = stepX * overlap
    let padY = stepY * overlap
    var rects: [CGRect] = []
    for row in 0..<rows {
        for col in 0..<cols {
            let raw = CGRect(
                x: crop.minX + CGFloat(col) * stepX - padX,
                y: crop.minY + CGFloat(row) * stepY - padY,
                width: stepX + 2 * padX,
                height: stepY + 2 * padY
            )
            let clamped = raw.intersection(imageBounds)
            if !clamped.isNull, clamped.width > 1, clamped.height > 1 {
                rects.append(clamped)
            }
        }
    }
    return rects
}

// MARK: - Analysis output
func analyzeSpot(_ spot: Spot) async {
    print("\n===== \(spot.name) =====\n")

    let url = URL(string: spot.source.url) ?? URL(string: "about:blank")!

    do {
        let image = try await fetchFrame(from: url)
        print("Frame: \(image.width)x\(image.height) @ \(url.lastPathComponent)")

        let (crop, fullFrame) = regionBounds(in: image, region: spot.waterRegion)
        if fullFrame {
            print("Water region: INVALID (degenerate points) - using full frame")
        } else {
            print("Water region crop: \(Int(crop.minX)),\(Int(crop.minY)) to \(Int(crop.maxX)),\(Int(crop.maxY))")
            print("Crop size: \(Int(crop.width))x\(Int(crop.height)) pixels")

            let tiles = formatTileGrid(crop: crop, maxTile: 640, overlap: 0.2,
                                       imageBounds: CGRect(x: 0, y: 0,
                                                           width: CGFloat(image.width),
                                                           height: CGFloat(image.height)))
            print("Tile grid: \(tiles.count) tiles (max 640px)")

            // Suggest adjustments based on crop size
            if crop.width > 1200 || crop.height > 800 {
                print("\n💡 Tuning suggestions:")
                print("   - Large crop detected (\(Int(crop.width))x\(Int(crop.height)))")
                print("   - Consider narrowing region to focus on lineup")
                print("   - Current tiles will be small, distant surfers may be missed")
            }
            if crop.height < 200 {
                print("\n💡 Tuning suggestions:")
                print("   - Very narrow vertical crop may miss surfers")
                print("   - Consider expanding y range")
            }
            if crop.width < 300 && crop.height < 300 {
                print("\n💡 Tuning suggestions:")
                print("   - Small crop may not need tiling")
                print("   - Consider if region captures the lineup correctly")
            }
        }

        // Print current region points
        print("\nCurrent water region points (normalized):")
        for (i, p) in spot.waterRegion.points.enumerated() {
            print("   Point \(i): (\(String(format: "%.3f", p.x)), \(String(format: "%.3f", p.y)))")
        }

        // Format for spots.json
        let pointsStr = spot.waterRegion.points.map { p in
            String(format: "%.2f,%.2f", p.x, p.y)
        }.joined(separator: "], [")
        print("\nFor spots.json:")
        print("   \"waterRegion\": {\"points\": [[\(pointsStr)]]}")

    } catch {
        // Only `snapshot` (plain JPEG) sources decode here — HLS playlists and
        // YouTube pages need the app's HLSSource / YouTubeSource to pull a frame.
        if spot.source.kind != "snapshot" {
            print("⚠️  Skipped: \(spot.source.kind) sources aren't supported by this script (snapshot only)")
        } else {
            print("❌ Error fetching frame: \(error)")
        }
    }
}

// MARK: - Main
print("""
Swell Detection Tuning Tool
===========================
Analyzing spot water regions and tile grids...
""")

do {
    let spots = try loadSpots()
    let args = CommandLine.arguments

    if args.count > 1 {
        let targetID = args[1].lowercased()
        if let spot = spots.first(where: { $0.id.lowercased() == targetID }) {
            await analyzeSpot(spot)
        } else {
            print("Spot '\(targetID)' not found. Available spots: \(spots.map { $0.id }.joined(separator: ", "))")
        }
    } else {
        // Analyze all non-locked spots
        for spot in spots.filter({ $0.surfValue != "locked" && !$0.source.url.isEmpty }) {
            await analyzeSpot(spot)
        }
    }
} catch {
    print("Error: \(error)")
}
