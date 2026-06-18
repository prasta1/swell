import CoreGraphics
import Foundation
import Vision

/// Counts people inside a cam's water region using the bundled YOLO11n Core ML
/// model (COCO `person` class). The model is an NMS-pipeline export, so Vision
/// returns `VNRecognizedObjectObservation` boxes directly.
struct YOLODetector: SurferDetector {
    private let model: VNCoreMLModel

    init() throws {
        let mlModel = try SurferYOLO(configuration: .init()).model
        model = try VNCoreMLModel(for: mlModel)
    }

    // MARK: - Tuning

    /// Target max tile size in pixels. Tiles are detected at the model's 640px
    /// input, so keeping tiles near this size means distant surfers aren't
    /// shrunk below what the model can find.
    static let maxTilePx: CGFloat = 640
    /// Fractional overlap between tiles, so a surfer on a seam still appears
    /// whole in at least one tile.
    static let tileOverlap: CGFloat = 0.2
    /// IoU above which two boxes (e.g. the same surfer caught in two overlapping
    /// tiles) are treated as duplicates when merging.
    static let mergeIoU = 0.45
    /// Minimum `person` confidence to keep a detection.
    static let minConfidence: Float = 0.25

    /// A detection box (full-frame normalized, top-left origin) with its score.
    struct ScoredBox: Equatable {
        var rect: CGRect
        var score: Float
    }

    func count(in frame: CGImage, region: WaterRegion) throws -> Detection {
        let regionRect = Self.regionRectPx(frame, region: region)
        let imageBounds = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        let tiles = Self.tiles(in: regionRect, maxTile: Self.maxTilePx,
                               overlap: Self.tileOverlap, imageBounds: imageBounds)

        // Detect within each tile (so distant surfers fill more of the 640px
        // input), then merge across tiles with NMS so a surfer caught in two
        // overlapping tiles is only counted once.
        var scored: [ScoredBox] = []
        for tile in tiles {
            scored += try detect(in: frame, tile: tile)
        }
        let merged = Self.nonMaxSuppress(scored, iouThreshold: Self.mergeIoU)

        let conf = merged.isEmpty ? 0
            : merged.map { Double($0.score) }.reduce(0, +) / Double(merged.count)
        return Detection(count: merged.count, confidence: conf, boxes: merged.map { $0.rect })
    }

    /// Runs the model on one tile and returns its `person` boxes in full-frame
    /// normalized coordinates.
    private func detect(in frame: CGImage, tile: CGRect) throws -> [ScoredBox] {
        guard let cropped = frame.cropping(to: tile) else { return [] }
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFit
        try VNImageRequestHandler(cgImage: cropped, options: [:]).perform([request])
        let obs = (request.results as? [VNRecognizedObjectObservation]) ?? []
        return obs.compactMap { ob in
            guard let score = ob.labels.first(where: { $0.identifier == "person" })?.confidence,
                  score > Self.minConfidence else { return nil }
            let rect = Self.fullFrameBox(visionBox: ob.boundingBox, cropRectPx: tile,
                                         imageWidth: frame.width, imageHeight: frame.height)
            return ScoredBox(rect: rect, score: score)
        }
    }

    /// Pixel rect of the water-region bounding box; the whole image if the
    /// region is degenerate. Detection runs inside this rect so beach/cliff
    /// people are excluded.
    static func regionRectPx(_ image: CGImage, region: WaterRegion) -> CGRect {
        let w = Double(image.width), h = Double(image.height)
        let xs = region.points.map { $0.x * w }, ys = region.points.map { $0.y * h }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max(), maxX > minX, maxY > minY else {
            return CGRect(x: 0, y: 0, width: w, height: h)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Maps a Vision bounding box (normalized, bottom-left origin, relative to
    /// the cropped water-region) into full-frame normalized coordinates with a
    /// top-left origin — ready to draw over the displayed frame in SwiftUI.
    static func fullFrameBox(visionBox: CGRect, cropRectPx: CGRect, imageWidth: Int, imageHeight: Int) -> CGRect {
        let w = CGFloat(imageWidth), h = CGFloat(imageHeight)
        let xPx = cropRectPx.minX + visionBox.minX * cropRectPx.width
        // Vision's origin is bottom-left; flip the y within the crop to top-left.
        let yPx = cropRectPx.minY + (1 - visionBox.minY - visionBox.height) * cropRectPx.height
        let widthPx = visionBox.width * cropRectPx.width
        let heightPx = visionBox.height * cropRectPx.height
        return CGRect(x: xPx / w, y: yPx / h, width: widthPx / w, height: heightPx / h)
    }

    /// Splits `region` into an overlapping grid of tiles, each ≤ ~`maxTile` on a
    /// side, clamped to the image. Wide-short water regions yield more columns
    /// than rows.
    static func tiles(in region: CGRect, maxTile: CGFloat, overlap: CGFloat, imageBounds: CGRect) -> [CGRect] {
        guard region.width > 0, region.height > 0 else { return [] }
        let cols = max(1, Int(ceil(region.width / maxTile)))
        let rows = max(1, Int(ceil(region.height / maxTile)))
        let stepX = region.width / CGFloat(cols)
        let stepY = region.height / CGFloat(rows)
        let padX = stepX * overlap
        let padY = stepY * overlap
        var rects: [CGRect] = []
        for row in 0..<rows {
            for col in 0..<cols {
                let raw = CGRect(x: region.minX + CGFloat(col) * stepX - padX,
                                 y: region.minY + CGFloat(row) * stepY - padY,
                                 width: stepX + 2 * padX,
                                 height: stepY + 2 * padY)
                let clamped = raw.intersection(imageBounds)
                if !clamped.isNull, clamped.width > 1, clamped.height > 1 {
                    rects.append(clamped)
                }
            }
        }
        return rects
    }

    /// Intersection-over-union of two rects (0 when disjoint).
    static func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let inter = a.intersection(b)
        guard !inter.isNull else { return 0 }
        let interArea = Double(inter.width * inter.height)
        let union = Double(a.width * a.height + b.width * b.height) - interArea
        return union > 0 ? interArea / union : 0
    }

    /// Greedy non-maximum suppression: keep the highest-scoring box, drop any
    /// box overlapping it beyond `iouThreshold`, repeat.
    static func nonMaxSuppress(_ boxes: [ScoredBox], iouThreshold: Double) -> [ScoredBox] {
        var candidates = boxes.sorted { $0.score > $1.score }
        var kept: [ScoredBox] = []
        while !candidates.isEmpty {
            let best = candidates.removeFirst()
            kept.append(best)
            candidates.removeAll { iou(best.rect, $0.rect) > iouThreshold }
        }
        return kept
    }
}
