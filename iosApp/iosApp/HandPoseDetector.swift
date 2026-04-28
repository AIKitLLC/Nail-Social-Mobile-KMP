import Foundation
import Vision
import UIKit

/// Uses Vision framework's VNDetectHumanHandPoseRequest to detect hand landmarks
/// (replaces MediaPipe HandLandmarker used on Android).
class HandPoseDetector {
    
    private let handPoseRequest = VNDetectHumanHandPoseRequest()
    
    init() {
        handPoseRequest.maximumHandCount = 1
        handPoseRequest.revision = VNDetectHumanHandPoseRequestRevision1
    }
    
    /// Run hand pose detection on a CGImage and return joints + bounding box
    /// in the image's pixel coordinate space (top-left origin, as returned by
    /// `VNImagePointForNormalizedPoint`).
    /// Used to compute a tight crop region around the hand before segmentation.
    func detectHandPixelLandmarks(_ cgImage: CGImage, imageWidth: Int, imageHeight: Int) -> HandLandmarksRaw? {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
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
