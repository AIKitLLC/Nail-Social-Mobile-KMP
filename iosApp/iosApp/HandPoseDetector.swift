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
    
    /// Analyze a UIImage for hand pose.
    func analyzeHand(_ image: UIImage) -> HandAnalysisData? {
        guard let cgImage = image.cgImage else { return nil }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        
        do {
            try handler.perform([handPoseRequest])
            
            guard let observations = handPoseRequest.results, !observations.isEmpty else {
                return nil
            }
            
            // Take the first hand
            let observation = observations[0]
            
            var orientations: [FingerOrientation] = []
            var landmarks: [NormalizedPoint] = []
            
            // Vision hand pose provides landmarks for each finger.
            // Each finger has: tip (index 3), DIP (index 2), PIP (index 1), MCP (index 0)
            // And there's a wrist (index 4 for thumb, index 0 of the full set via .allPoints)
            
            // Collect all raw landmarks
            if let allPoints = try? observation.recognizedPoints(.all) {
                var points: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
                for (joint, point) in allPoints {
                    guard point.confidence > 0.3 else { continue }
                    let pt = VNImagePointForNormalizedPoint(
                        point.location,
                        Int(image.size.width),
                        Int(image.size.height)
                    )
                    points[joint] = pt
                    let normX = Float(point.location.x)
                    let normY = Float(point.location.y)
                    landmarks.append(NormalizedPoint(x: normX, y: normY))
                }
                
                // For each finger with a detectable tip and DIP, compute orientation
                let fingerJoints: [(tip: VNHumanHandPoseObservation.JointName, dip: VNHumanHandPoseObservation.JointName)] = [
                    (.thumbTip, .thumbIP),       // Thumb: IP joint = DIP equivalent
                    (.indexTip, .indexDIP),
                    (.middleTip, .middleDIP),
                    (.ringTip, .ringDIP),
                    (.littleTip, .littleDIP)
                ]
                
                for (tipJoint, dipJoint) in fingerJoints {
                    guard let tip = points[tipJoint],
                          let dip = points[dipJoint] else { continue }
                    
                    let tipNorm = CGPoint(
                        x: tip.x / image.size.width,
                        y: tip.y / image.size.height
                    )
                    let dipNorm = CGPoint(
                        x: dip.x / image.size.width,
                        y: dip.y / image.size.height
                    )
                    
                    let angle = TextureMapper.calculateFingerAngle(
                        tipX: Float(tipNorm.x),
                        tipY: Float(tipNorm.y),
                        dipX: Float(dipNorm.x),
                        dipY: Float(dipNorm.y)
                    )
                    
                    orientations.append(FingerOrientation(
                        tipX: Float(tipNorm.x),
                        tipY: Float(tipNorm.y),
                        dipX: Float(dipNorm.x),
                        dipY: Float(dipNorm.y),
                        angle: angle
                    ))
                }
            }
            
            return HandAnalysisData(orientations: orientations, landmarks: landmarks)
            
        } catch {
            print("Hand pose detection error: \(error.localizedDescription)")
            return nil
        }
    }
}
