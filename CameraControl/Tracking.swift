import CoreImage
import Vision

/// Person segmentation for background blur/replacement. The request object is reused
/// across frames so Vision can smooth the mask over time.
final class Segmenter {
    private let request: VNGeneratePersonSegmentationRequest = {
        let r = VNGeneratePersonSegmentationRequest()
        r.qualityLevel = .balanced
        r.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return r
    }()
    private let handler = VNSequenceRequestHandler()

    /// Returns a mask (white = person) covering `image.extent`.
    func mask(for image: CIImage) -> CIImage? {
        do { try handler.perform([request], on: image) } catch { return nil }
        guard let pb = request.results?.first?.pixelBuffer else { return nil }
        let m = CIImage(cvPixelBuffer: pb)
        let e = image.extent
        return m.transformed(by: CGAffineTransform(scaleX: e.width / m.extent.width, y: e.height / m.extent.height)
            .concatenating(CGAffineTransform(translationX: e.minX, y: e.minY)))
    }
}

struct TrackedFace {
    var rect: CGRect
    var roll: CGFloat
}

/// Face rectangles for stickers and face-centered distortions, lightly smoothed.
final class FaceTracker {
    private let request = VNDetectFaceRectanglesRequest()
    private let handler = VNSequenceRequestHandler()
    private(set) var faces: [TrackedFace] = []
    /// Flip if stickers tilt the wrong way when you tilt your head.
    static let rollSign: CGFloat = -1

    func update(with image: CIImage) {
        do { try handler.perform([request], on: image) } catch { return }
        let e = image.extent
        let found = (request.results ?? []).map { obs -> TrackedFace in
            let b = obs.boundingBox
            return TrackedFace(rect: CGRect(x: e.minX + b.minX * e.width, y: e.minY + b.minY * e.height,
                                            width: b.width * e.width, height: b.height * e.height),
                               roll: CGFloat(obs.roll?.doubleValue ?? 0) * Self.rollSign)
        }
        if found.count == faces.count {
            // Ease toward the new positions to cut jitter.
            faces = zip(faces, found).map { old, new in
                TrackedFace(rect: lerp(old.rect, new.rect, 0.5), roll: old.roll + (new.roll - old.roll) * 0.5)
            }
        } else {
            faces = found
        }
    }

    func clear() { faces = [] }
}

private func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
    CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
           width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
}
