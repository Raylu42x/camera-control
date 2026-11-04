import CoreImage
import Vision

/// Person segmentation for background effects. The request object is reused across
/// frames so Vision can smooth the mask over time.
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
    var leftEye: CGPoint?
    var rightEye: CGPoint?

    /// Eye positions, falling back to where eyes usually sit in the face box.
    var eyes: [CGPoint] {
        if let leftEye, let rightEye { return [leftEye, rightEye] }
        return [CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.62),
                CGPoint(x: rect.minX + rect.width * 0.7, y: rect.minY + rect.height * 0.62)]
    }

    func applying(_ t: CGAffineTransform) -> TrackedFace {
        TrackedFace(rect: rect.applying(t), roll: roll, leftEye: leftEye?.applying(t), rightEye: rightEye?.applying(t))
    }
}

/// Face boxes and pupils for stickers, lasers, witness protection, distortions and
/// auto-framing, lightly smoothed.
final class FaceTracker {
    private let request = VNDetectFaceLandmarksRequest()
    private let handler = VNSequenceRequestHandler()
    /// Smoothed faces in the coordinates of the image passed to `update`.
    private(set) var raw: [TrackedFace] = []
    /// Faces in canvas coordinates (`raw` mapped through the last `apply`).
    private(set) var faces: [TrackedFace] = []
    /// Flip if stickers tilt the wrong way when you tilt your head.
    static let rollSign: CGFloat = -1

    func update(with image: CIImage) {
        do { try handler.perform([request], on: image) } catch { return }
        let e = image.extent
        let found = (request.results ?? []).map { obs -> TrackedFace in
            let b = obs.boundingBox
            func pupil(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
                region?.pointsInImage(imageSize: e.size).first.map { CGPoint(x: $0.x + e.minX, y: $0.y + e.minY) }
            }
            return TrackedFace(rect: CGRect(x: e.minX + b.minX * e.width, y: e.minY + b.minY * e.height,
                                            width: b.width * e.width, height: b.height * e.height),
                               roll: CGFloat(obs.roll?.doubleValue ?? 0) * Self.rollSign,
                               leftEye: pupil(obs.landmarks?.leftPupil), rightEye: pupil(obs.landmarks?.rightPupil))
        }
        if found.count == raw.count {
            // Ease toward the new positions to cut jitter.
            raw = zip(raw, found).map { old, new in
                TrackedFace(rect: lerp(old.rect, new.rect, 0.5), roll: old.roll + (new.roll - old.roll) * 0.5,
                            leftEye: lerp(old.leftEye, new.leftEye, 0.5), rightEye: lerp(old.rightEye, new.rightEye, 0.5))
            }
        } else {
            raw = found
        }
        faces = raw
    }

    func apply(_ t: CGAffineTransform) { faces = raw.map { $0.applying(t) } }

    func clear() { raw = []; faces = [] }
}

private func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
    CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
           width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
}

private func lerp(_ a: CGPoint?, _ b: CGPoint?, _ t: CGFloat) -> CGPoint? {
    guard let a, let b else { return b }
    return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}
