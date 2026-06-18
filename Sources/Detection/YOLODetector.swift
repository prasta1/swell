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
        let cropped = try cropToRegion(frame, region: region)
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFit
        let handler = VNImageRequestHandler(cgImage: cropped, options: [:])
        try handler.perform([request])
        let obs = (request.results as? [VNRecognizedObjectObservation]) ?? []
        let people = obs.filter { ob in
            (ob.labels.first(where: { $0.identifier == "person" })?.confidence ?? 0) > 0.25
        }
        let conf = people.isEmpty ? 0
            : people.map { Double($0.confidence) }.reduce(0, +) / Double(people.count)
        return Detection(count: people.count, confidence: conf)
    }

    /// Crop to the water-region bounding box (in pixels) before detection so
    /// beach/cliff people are excluded.
    private func cropToRegion(_ image: CGImage, region: WaterRegion) throws -> CGImage {
        let w = Double(image.width), h = Double(image.height)
        let xs = region.points.map { $0.x * w }, ys = region.points.map { $0.y * h }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max(), maxX > minX, maxY > minY else {
            return image
        }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return image.cropping(to: rect) ?? image
    }
}
