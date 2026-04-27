import Foundation
import UIKit
import TensorFlowLite

/// iOS-native nail detector using TensorFlow Lite for the segmentation model
/// and Vision framework for hand pose detection.
class NailDetectorIOS {
    
    private var interpreter: Interpreter?
    private let modelName = "nail_detect_model"
    private let inputSize = 256
    private let modelFileName = "nail_detect_model.tflite"
    
    var patternImage: UIImage?
    var showDebugLandmarks: Bool = false
    
    private var handDetector: HandPoseDetector?
    
    init() {
        setupInterpreter()
        handDetector = HandPoseDetector()
    }
    
    struct DetectionResult {
        let inputImage: UIImage
        let maskImage: UIImage
    }
    
    private func setupInterpreter() {
        guard let modelPath = Bundle.main.path(forResource: modelName, ofType: "tflite") else {
            print("❌ Model file not found: \(modelFileName)")
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
    
    /// Run nail detection on a UIImage.
    func detectNails(_ image: UIImage) -> DetectionResult? {
        guard let interpreter = interpreter else {
            print("❌ Interpreter not initialized")
            return nil
        }
        
        guard let cgImage = image.cgImage else { return nil }
        
        // 1. Resize and preprocess image
        let minDim = min(image.size.width, image.size.height)
        let cropRect = CGRect(
            x: (image.size.width - minDim) / 2,
            y: (image.size.height - minDim) / 2,
            width: minDim,
            height: minDim
        )
        
        guard let croppedCG = cgImage.cropping(to: cropRect) else { return nil }
        
        // Create input tensor directly from pixel data
        guard let inputData = preprocessImage(croppedCG) else {
            print("❌ Failed to preprocess image")
            return nil
        }
        
        // 2. Run inference
        do {
            try interpreter.copy(inputData, toInputAt: 0)
            try interpreter.invoke()
            let outputTensor = try interpreter.output(at: 0)
            let outputData = outputTensor.data
            
            // Output is [1, 256, 256, 1] float32
            let confidenceValues = outputData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> [Float] in
                let floatPtr = ptr.bindMemory(to: Float32.self)
                return Array(UnsafeBufferPointer(start: floatPtr.baseAddress, count: inputSize * inputSize))
            }
            
            // 3. Hand pose detection via Vision
            // Use the original (cropped) input for hand detection
            let inputBitmap = UIImage(cgImage: croppedCG)
            let handAnalysis = handDetector?.analyzeHand(inputBitmap)
            let orientations = handAnalysis?.orientations ?? []
            let landmarks = handAnalysis?.landmarks ?? []
            
            // 4. Connected component analysis
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
            
            // 5. Texture mapping
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
                // Fallback: raw mask
                for i in 0..<confidenceValues.count {
                    if confidenceValues[i] > 0.5 {
                        pixels[i] = argb(a: 180, r: 50, g: 50, b: 255)
                    }
                }
            }
            
            // 6. Create mask UIImage
            let maskImage = createImage(from: pixels, width: inputSize, height: inputSize)
            
            // 7. Create debug input with landmarks if enabled
            var debugInput = inputBitmap
            if showDebugLandmarks && !landmarks.isEmpty {
                debugInput = drawLandmarks(on: inputBitmap, landmarks: landmarks, inputSize: inputSize)
            }
            
            return DetectionResult(inputImage: debugInput, maskImage: maskImage ?? inputBitmap)
            
        } catch {
            print("❌ Inference error: \(error)")
            return nil
        }
    }
    
    /// Convert RGBA pixel buffer to float32 input tensor.
    private func preprocessImage(_ cgImage: CGImage) -> Data? {
        let width = cgImage.width
        let height = cgImage.height
        
        // If not 256x256, resize
        let resizedImage: CGImage
        if width != inputSize || height != inputSize {
            guard let resized = resizeCGImage(cgImage, to: CGSize(width: inputSize, height: inputSize)) else {
                return nil
            }
            resizedImage = resized
        } else {
            resizedImage = cgImage
        }
        
        // Read pixel data
        let bytesPerPixel = 4
        let bytesPerRow = inputSize * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: inputSize * inputSize * bytesPerPixel)
        
        guard let context = CGContext(
            data: &pixelData,
            width: inputSize,
            height: inputSize,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        
        context.draw(resizedImage, in: CGRect(x: 0, y: 0, width: inputSize, height: inputSize))
        
        // Convert to float32 normalized to [-1, 1] (matching Android preprocessing)
        var floatData = [Float32](repeating: 0, count: inputSize * inputSize * 3)
        for i in 0..<(inputSize * inputSize) {
            let pixelOffset = i * 4
            let r = Float(pixelData[pixelOffset]) / 255.0
            let g = Float(pixelData[pixelOffset + 1]) / 255.0
            let b = Float(pixelData[pixelOffset + 2]) / 255.0
            
            // Normalize to [-1, 1] (assuming model was trained with this)
            floatData[i * 3] = (r - 0.5) / 0.5
            floatData[i * 3 + 1] = (g - 0.5) / 0.5
            floatData[i * 3 + 2] = (b - 0.5) / 0.5
        }
        
        return Data(bytes: floatData, count: floatData.count * 4)
    }
    
    /// Resize CGImage to target size.
    private func resizeCGImage(_ image: CGImage, to size: CGSize) -> CGImage? {
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
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
            rawData[i * 4] = UInt8((pixel >> 16) & 0xFF)     // R
            rawData[i * 4 + 1] = UInt8((pixel >> 8) & 0xFF)  // G
            rawData[i * 4 + 2] = UInt8(pixel & 0xFF)         // B
            rawData[i * 4 + 3] = UInt8((pixel >> 24) & 0xFF) // A
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
    
    /// Draw landmarks on debug image.
    private func drawLandmarks(on image: UIImage, landmarks: [NormalizedPoint], inputSize: Int) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: inputSize, height: inputSize), false, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        image.draw(in: CGRect(x: 0, y: 0, width: inputSize, height: inputSize))
        
        guard let ctx = UIGraphicsGetCurrentContext() else { return image }
        ctx.setLineWidth(2.0)
        UIColor.green.setStroke()
        UIColor.red.setFill()
        
        // Hand skeleton connections (same as Android)
        let connections: [(Int, Int)] = [
            (0, 1), (1, 2), (2, 3), (3, 4),
            (0, 5), (5, 6), (6, 7), (7, 8),
            (0, 9), (9, 10), (10, 11), (11, 12),
            (0, 13), (13, 14), (14, 15), (15, 16),
            (0, 17), (17, 18), (18, 19), (19, 20),
            (5, 9), (9, 13), (13, 17)
        ]
        
        for (start, end) in connections {
            guard start < landmarks.count, end < landmarks.count else { continue }
            ctx.move(to: CGPoint(
                x: CGFloat(landmarks[start].x) * CGFloat(inputSize),
                y: CGFloat(landmarks[start].y) * CGFloat(inputSize)
            ))
            ctx.addLine(to: CGPoint(
                x: CGFloat(landmarks[end].x) * CGFloat(inputSize),
                y: CGFloat(landmarks[end].y) * CGFloat(inputSize)
            ))
        }
        ctx.strokePath()
        
        for p in landmarks {
            let rect = CGRect(
                x: CGFloat(p.x) * CGFloat(inputSize) - 3,
                y: CGFloat(p.y) * CGFloat(inputSize) - 3,
                width: 6, height: 6
            )
            ctx.fillEllipse(in: rect)
        }
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
    
    private func argb(a: Int, r: Int, g: Int, b: Int) -> Int {
        return (a & 0xFF) << 24 | (r & 0xFF) << 16 | (g & 0xFF) << 8 | (b & 0xFF)
    }
    
    deinit {
        // TFLite Interpreter is automatically cleaned up by Swift
        print("NailDetectorIOS deinit")
    }
}
