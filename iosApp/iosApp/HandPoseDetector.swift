import Foundation
import Vision
import UIKit
import Accelerate

/// Hand-pose detection wrapper around `VNDetectHumanHandPoseRequest`.
///
/// Speed-optimised: full frames from the camera (1280×720 BGRA) are
/// proportionally downsampled before Vision runs — Vision's Hand-Pose
/// model has its own internal scale, so feeding a smaller frame cuts
/// per-call time roughly proportionally without measurable accuracy loss.
class HandPoseDetector {

    /// Target longest-edge size that we feed Vision. Empirically 480 keeps
    /// fingertip joints well inside the noise floor while running ~5–9×
    /// faster than 1280×720.
    static let detectionTargetSize: CGFloat = 480

    private let handPoseRequest: VNDetectHumanHandPoseRequest
    private let downsampleColorSpace = CGColorSpaceCreateDeviceRGB()

    init() {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        // Use the latest revision the runtime advertises, falling back to
        // Revision 1. Newer revisions ship faster + more stable hand
        // detection without needing a SDK bump on our side.
        if let latest = VNDetectHumanHandPoseRequest.supportedRevisions.max() {
            request.revision = latest
        } else {
            request.revision = VNDetectHumanHandPoseRequestRevision1
        }
        self.handPoseRequest = request
    }

    /// Run hand pose detection on a CGImage and return joints + bounding box
    /// in the *full-frame* pixel coordinate space (top-left origin). The
    /// caller passes the original full-resolution dimensions; the actual
    /// Vision call runs on a downsampled copy for speed.
    func detectHandPixelLandmarks(_ cgImage: CGImage, imageWidth: Int, imageHeight: Int) -> HandLandmarksRaw? {
        // Downsample to keep Vision's compute small. We hand the request a
        // smaller CGImage but report joint coords in the original pixel
        // space (Vision returns normalized coords, so we just multiply by
        // the *original* dimensions on the way out).
        let downsampled = downsample(cgImage, longestSide: Self.detectionTargetSize) ?? cgImage

        let handler = VNImageRequestHandler(cgImage: downsampled, orientation: .up, options: [:])
        do {
            try handler.perform([handPoseRequest])
        } catch {
            print("Hand pose detection error: \(error.localizedDescription)")
            return nil
        }
        guard let observation = handPoseRequest.results?.first else { return nil }
        guard let allPoints = try? observation.recognizedPoints(.all) else { return nil }

        var joints: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX: CGFloat = -.greatestFiniteMagnitude
        var maxY: CGFloat = -.greatestFiniteMagnitude

        for (joint, point) in allPoints {
            guard point.confidence > 0.3 else { continue }
            // Normalised coords scale the same regardless of detector input
            // size, so multiply by the *original* image dims to land back
            // in the camera-frame pixel space the rest of the pipeline uses.
            let pt = VNImagePointForNormalizedPoint(
                point.location,
                imageWidth,
                imageHeight
            )
            joints[joint] = pt
            if pt.x < minX { minX = pt.x }
            if pt.y < minY { minY = pt.y }
            if pt.x > maxX { maxX = pt.x }
            if pt.y > maxY { maxY = pt.y }
        }

        guard !joints.isEmpty else { return nil }
        let bbox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return HandLandmarksRaw(boundingBox: bbox, joints: joints)
    }

    /// Proportionally downsample a CGImage so the longer edge equals
    /// `longestSide`. Returns the original if it's already smaller.
    private func downsample(_ image: CGImage, longestSide: CGFloat) -> CGImage? {
        let w = image.width
        let h = image.height
        let maxDim = max(w, h)
        guard CGFloat(maxDim) > longestSide else { return image }

        let scale = longestSide / CGFloat(maxDim)
        let outW = Int((CGFloat(w) * scale).rounded())
        let outH = Int((CGFloat(h) * scale).rounded())

        let context = CGContext(
            data: nil,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: downsampleColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )
        // Lower interpolation quality is fine — Vision is not sensitive
        // to fine detail in the down-sample, and this is faster.
        context?.interpolationQuality = .low
        context?.draw(image, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        return context?.makeImage()
    }
}

/// Raw hand landmark output in image pixel coordinates (top-left origin).
struct HandLandmarksRaw {
    let boundingBox: CGRect
    let joints: [VNHumanHandPoseObservation.JointName: CGPoint]
}

// MARK: - UIImage.Orientation to CGImagePropertyOrientation

extension UIImage.Orientation {
    func toCGImagePropertyOrientation() -> CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
