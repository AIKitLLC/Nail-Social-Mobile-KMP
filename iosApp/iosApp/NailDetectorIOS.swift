import Foundation
import UIKit
import Vision
import TensorFlowLite

/// iOS-native nail detector using TensorFlow Lite for the segmentation model
/// and Vision framework for hand pose detection.
class NailDetectorIOS {
    
    private var interpreter: Interpreter?
    private let modelName = "nail_detect_model"
    private let inputSize = 256
    
    var patternImage: UIImage?
    var showDebugLandmarks: Bool = false
    
    private var handDetector: HandPoseDetector?
    
    init() {
        setupInterpreter()
        handDetector = HandPoseDetector()
    }
    
    struct DetectionResult {
        let maskImage: UIImage
        /// 0...1 max confidence from this frame's mask.
        var maxConfidence: Float = 0
        /// Number of connected components (≈ number of nails) detected.
        var componentsFound: Int = 0
        /// Debug artifacts populated only when `captureDebug == true` on the call.
        var debug: DebugArtifacts? = nil
    }

    struct DebugArtifacts {
        let orientedFullFrame: UIImage      // bitmap fed into the detector (after orientation)
        let croppedSquare: UIImage          // tight square fed to TFLite (256×256-ish or larger)
        let rawMask256: UIImage             // 256×256 colored mask before composing
        let handBBoxInFullFrame: CGRect?    // hand pose bbox, nil if not detected
        let cropRectInFullFrame: CGRect     // square crop rect used for inference
        let maxConfidence: Float
        let highConfidencePixelCount: Int
        let componentsFound: Int
        let orientationsFound: Int
    }
    
    private func setupInterpreter() {
        guard let modelPath = Bundle.main.path(forResource: modelName, ofType: "tflite") else {
            print("❌ Model file not found: nail_detect_model.tflite")
            return
        }
        
        do {
            var options = Interpreter.Options()
            options.threadCount = 4
            
            interpreter = try Interpreter(modelPath: modelPath, options: options)
            try interpreter?.allocateTensors()
            
            print("✅ TFLite interpreter initialized successfully")
            print("   Input: \(inputSize)x\(inputSize)x3 -> Output: \(inputSize)x\(inputSize)x1")
        } catch {
            print("❌ Failed to initialize TFLite interpreter: \(error)")
        }
    }
    
    /// Render UIImage to a properly oriented bitmap, then run nail detection.
    /// Pipeline: Vision hand-pose on full frame → tight square crop around hand
    /// → TFLite segmentation at 256×256 → composite mask back to source-frame
    /// aspect ratio so it overlays the camera preview pixel-for-pixel.
    /// When `captureDebug` is true the result includes intermediate images so
    /// callers can render a debug breakdown.
    func detectNails(_ image: UIImage, captureDebug: Bool = false) -> DetectionResult? {
        guard let interpreter = interpreter else {
            print("❌ Interpreter not initialized")
            return nil
        }

        // Render UIImage to bitmap to handle orientation properly
        guard let orientedBitmap = image.renderToBitmap() else {
            print("❌ Failed to render oriented bitmap")
            return nil
        }

        let bitmapWidth = orientedBitmap.width
        let bitmapHeight = orientedBitmap.height
        let canvasSize = CGSize(width: bitmapWidth, height: bitmapHeight)

        // 1. Hand pose detection on the FULL frame (not the crop) — finds the hand
        //    no matter where it is in the camera view.
        let handLandmarks = handDetector?.detectHandPixelLandmarks(
            orientedBitmap,
            imageWidth: bitmapWidth,
            imageHeight: bitmapHeight
        )

        // 2. Compute a tight square crop around the hand (or fall back to center).
        let cropRect = computeCropRect(
            handBBox: handLandmarks?.boundingBox,
            imageWidth: bitmapWidth,
            imageHeight: bitmapHeight
        )

        // 3. Crop and feed to TFLite at 256×256.
        guard let cropped = orientedBitmap.cropping(to: cropRect) else {
            print("❌ Failed to crop image (rect=\(cropRect))")
            return nil
        }

        guard let inputData = preprocessImage(cropped) else {
            print("❌ Failed to preprocess image")
            return nil
        }

        // 4. Run inference.
        do {
            try interpreter.copy(inputData, toInputAt: 0)
            try interpreter.invoke()
            let outputTensor = try interpreter.output(at: 0)
            let outputData = outputTensor.data

            let confidenceValues = outputData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> [Float] in
                let floatPtr = ptr.bindMemory(to: Float32.self)
                return Array(UnsafeBufferPointer(start: floatPtr.baseAddress, count: inputSize * inputSize))
            }

            let maxConf = confidenceValues.max() ?? 0
            let meanConf = confidenceValues.reduce(0, +) / Float(confidenceValues.count)
            let highConfCount = confidenceValues.filter { $0 > 0.5 }.count
            print("📊 Inference: max=\(maxConf), mean=\(meanConf), >0.5=\(highConfCount), crop=\(Int(cropRect.width))×\(Int(cropRect.height)) hand=\(handLandmarks != nil)")

            // 5. Re-project finger orientations from full-frame coords into the crop.
            let orientations = computeOrientationsForCrop(
                joints: handLandmarks?.joints,
                cropRect: cropRect
            )

            // 6. Connected components + texture mapping (existing logic, unchanged).
            let (labels, boundingBoxes) = ConnectedComponents.findComponents(
                confidenceValues,
                inputSize: inputSize,
                threshold: 0.8
            )
            let components = ConnectedComponents.calculateProperties(
                labels: labels,
                boundingBoxes: boundingBoxes,
                inputSize: inputSize
            )

            var pixels = [Int](repeating: 0, count: inputSize * inputSize)

            if patternImage != nil && !components.isEmpty {
                TextureMapper.mapTexture(
                    pixels: &pixels,
                    confidenceValues: confidenceValues,
                    components: components,
                    inputSize: inputSize,
                    patternImage: patternImage,
                    orientations: orientations
                )
            } else {
                // Fallback: show semitransparent overlay where mask confidence > 0.1
                for i in 0..<confidenceValues.count {
                    if confidenceValues[i] > 0.1 {
                        let v = UInt8(min(confidenceValues[i] * 255, 255))
                        pixels[i] = argb(a: 180, r: Int(v), g: 50, b: 180)
                    }
                }
            }

            // 7. Mask at 256×256 over the crop region.
            guard let cropMask = createImage(from: pixels, width: inputSize, height: inputSize) else {
                return nil
            }

            // 8. Composite the crop-mask onto a canvas matching the source frame's
            //    aspect ratio. This lets SwiftUI overlay the mask aligned 1:1 with
            //    the camera preview (both use .resizeAspectFill).
            let composedMask = compositeMask(cropMask, canvasSize: canvasSize, at: cropRect)

            var debug: DebugArtifacts? = nil
            if captureDebug {
                debug = DebugArtifacts(
                    orientedFullFrame: UIImage(cgImage: orientedBitmap),
                    croppedSquare: UIImage(cgImage: cropped),
                    rawMask256: cropMask,
                    handBBoxInFullFrame: handLandmarks?.boundingBox,
                    cropRectInFullFrame: cropRect,
                    maxConfidence: maxConf,
                    highConfidencePixelCount: highConfCount,
                    componentsFound: components.count,
                    orientationsFound: orientations.count
                )
            }
            return DetectionResult(
                maskImage: composedMask,
                maxConfidence: maxConf,
                componentsFound: components.count,
                debug: debug
            )

        } catch {
            print("❌ Inference error: \(error)")
            return nil
        }
    }

    /// Compute a square crop region around the hand (or center fallback).
    /// Returns a rect in the source bitmap's pixel coordinate space.
    private func computeCropRect(handBBox: CGRect?, imageWidth: Int, imageHeight: Int) -> CGRect {
        let bitmapW = CGFloat(imageWidth)
        let bitmapH = CGFloat(imageHeight)
        let minDim = min(bitmapW, bitmapH)

        guard let bbox = handBBox, bbox.width > 4, bbox.height > 4 else {
            // Fallback: center crop
            let x = (bitmapW - minDim) / 2
            let y = (bitmapH - minDim) / 2
            return CGRect(x: x, y: y, width: minDim, height: minDim)
        }

        // Expand bbox 30% on each side so fingertips aren't clipped, then
        // square-up to the larger side. The whole point is to give the model
        // a tight close-up of the hand.
        let padding: CGFloat = 0.3
        let expandedW = bbox.width * (1 + padding * 2)
        let expandedH = bbox.height * (1 + padding * 2)
        var side = max(expandedW, expandedH)
        side = min(side, minDim)

        let centerX = bbox.midX
        let centerY = bbox.midY
        var x = centerX - side / 2
        var y = centerY - side / 2

        // Clamp to image bounds.
        x = max(0, min(x, bitmapW - side))
        y = max(0, min(y, bitmapH - side))

        return CGRect(x: x, y: y, width: side, height: side)
    }

    /// Map joint pixel coords from full-frame coordinate space into normalized
    /// (0..1) coordinates relative to the cropped square. TextureMapper uses
    /// these to rotate nail textures along finger angles.
    private func computeOrientationsForCrop(
        joints: [VNHumanHandPoseObservation.JointName: CGPoint]?,
        cropRect: CGRect
    ) -> [FingerOrientation] {
        guard let joints = joints, cropRect.width > 0, cropRect.height > 0 else { return [] }

        let fingerJoints: [(tip: VNHumanHandPoseObservation.JointName, dip: VNHumanHandPoseObservation.JointName)] = [
            (.thumbTip, .thumbIP),
            (.indexTip, .indexDIP),
            (.middleTip, .middleDIP),
            (.ringTip, .ringDIP),
            (.littleTip, .littleDIP)
        ]

        var result: [FingerOrientation] = []
        for (tipJoint, dipJoint) in fingerJoints {
            guard let tip = joints[tipJoint], let dip = joints[dipJoint] else { continue }

            let tipX = Float((tip.x - cropRect.origin.x) / cropRect.width)
            let tipY = Float((tip.y - cropRect.origin.y) / cropRect.height)
            let dipX = Float((dip.x - cropRect.origin.x) / cropRect.width)
            let dipY = Float((dip.y - cropRect.origin.y) / cropRect.height)

            let angle = TextureMapper.calculateFingerAngle(
                tipX: tipX, tipY: tipY,
                dipX: dipX, dipY: dipY
            )
            result.append(FingerOrientation(
                tipX: tipX, tipY: tipY,
                dipX: dipX, dipY: dipY,
                angle: angle
            ))
        }
        return result
    }

    /// Draw the 256×256 crop mask onto a transparent canvas matching the source
    /// frame's aspect ratio at the crop's location. The returned UIImage can be
    /// overlaid on the camera preview with the same aspect-fill content mode.
    private func compositeMask(_ cropMask: UIImage, canvasSize: CGSize, at rect: CGRect) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { _ in
            cropMask.draw(in: rect)
        }
    }
    
    /// Preprocess CGImage to TFLite input tensor (float32 [-1, 1]).
    private func preprocessImage(_ cgImage: CGImage) -> Data? {
        // Resize to 256x256
        guard let resized = resizeCGImage(cgImage, to: CGSize(width: inputSize, height: inputSize)) else {
            return nil
        }
        
        // Read pixel data
        let bytesPerPixel = 4
        let bytesPerRow = inputSize * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: inputSize * inputSize * bytesPerPixel)
        
        let context = CGContext(
            data: &pixelData,
            width: inputSize,
            height: inputSize,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )
        context?.draw(resized, in: CGRect(x: 0, y: 0, width: inputSize, height: inputSize))
        
        // Convert to float32: keep raw [0,255] range
        // Android uses CastOp(FLOAT32) which does NOT normalize — it just casts UINT8 [0,255] → FLOAT32 [0.0, 255.0]
        var floatData = [Float32](repeating: 0, count: inputSize * inputSize * 3)
        for i in 0..<(inputSize * inputSize) {
            let offset = i * 4
            floatData[i * 3]     = Float(pixelData[offset])               // R
            floatData[i * 3 + 1] = Float(pixelData[offset + 1])           // G
            floatData[i * 3 + 2] = Float(pixelData[offset + 2])           // B
            // Skip A (noneSkipLast)
        }
        
        return Data(bytes: floatData, count: floatData.count * 4)
    }
    
    private func resizeCGImage(_ image: CGImage, to size: CGSize) -> CGImage? {
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )
        context?.interpolationQuality = .high
        context?.draw(image, in: CGRect(origin: .zero, size: size))
        return context?.makeImage()
    }
    
    /// Create UIImage from ARGB pixel array.
    private func createImage(from pixels: [Int], width: Int, height: Int) -> UIImage? {
        var rawData = [UInt8](repeating: 0, count: width * height * 4)
        
        for i in 0..<(width * height) {
            let pixel = pixels[i]
            // pixels store: alpha (bits 24-31), red (16-23), green (8-15), blue (0-7)
            rawData[i * 4]     = UInt8((pixel >> 16) & 0xFF)  // R
            rawData[i * 4 + 1] = UInt8((pixel >> 8) & 0xFF)   // G
            rawData[i * 4 + 2] = UInt8(pixel & 0xFF)          // B
            rawData[i * 4 + 3] = UInt8((pixel >> 24) & 0xFF)  // A
        }
        
        let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )
        guard let cgImage = context?.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    private func argb(a: Int, r: Int, g: Int, b: Int) -> Int {
        return (a & 0xFF) << 24 | (r & 0xFF) << 16 | (g & 0xFF) << 8 | (b & 0xFF)
    }
    
    deinit {
        print("NailDetectorIOS deinit")
    }
}

// MARK: - UIImage orientation helper

extension UIImage {
    /// Render UIImage to a CGImage bitmap that matches how UIKit/SwiftUI display
    /// it (EXIF orientation baked in, top-left memory origin).
    /// Uses `UIGraphicsImageRenderer` because the older path (manual CGContext +
    /// `UIGraphicsPushContext`) leaves the underlying context in lower-left origin,
    /// causing `UIImage.draw(in:)` to write pixels rotated 180° relative to the
    /// displayed image.
    func renderToBitmap() -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: self.size, format: format)
        let rendered = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: self.size))
        }
        return rendered.cgImage
    }
}
