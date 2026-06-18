import CoreGraphics
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

    func count(in frame: CGImage, region: WaterRegion) throws -> Detection {
        let regionRect = Self.regionRectPx(frame, region: region)
        let cropped = frame.cropping(to: regionRect)
        // If the crop fails, analyze the whole frame and map boxes against it so
        // the overlay stays aligned with what was actually scanned.
        let analysisImage = cropped ?? frame
        let analysisRect = cropped == nil
            ? CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
            : regionRect

        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFit
        let handler = VNImageRequestHandler(cgImage: analysisImage, options: [:])
        try handler.perform([request])
        let obs = (request.results as? [VNRecognizedObjectObservation]) ?? []
        let people = obs.filter { ob in
            (ob.labels.first(where: { $0.identifier == "person" })?.confidence ?? 0) > 0.25
        }
        let conf = people.isEmpty ? 0
            : people.map { Double($0.confidence) }.reduce(0, +) / Double(people.count)
        let boxes = people.map {
            Self.fullFrameBox(visionBox: $0.boundingBox, cropRectPx: analysisRect,
                              imageWidth: frame.width, imageHeight: frame.height)
        }
        return Detection(count: people.count, confidence: conf, boxes: boxes)
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
}
