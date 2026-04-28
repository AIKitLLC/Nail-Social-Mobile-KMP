import Foundation
import UIKit

/// Maps a pattern texture onto nail regions defined by connected components.
///
/// Speed-optimised: the pattern bitmap (cached as a flat RGBA byte array)
/// used to be re-extracted from the source UIImage on every detection
/// frame, which involved a CGContext allocation + draw. Now we cache the
/// extracted bytes and bounce only when the pattern image identity changes.
enum TextureMapper {

    /// Cache last-rendered pattern so we don't re-walk the CGImage every
    /// frame. Keyed on `ObjectIdentifier(cgImage)` — UIImage instances
    /// returned by NailPatternFactory are stable for the app's lifetime.
    private static var patternCache: PatternCache?
    private static let cacheLock = NSLock()
    private static let patternColorSpace = CGColorSpaceCreateDeviceRGB()

    private struct PatternCache {
        let cgImageRef: ObjectIdentifier
        let width: Int
        let height: Int
        let pixels: [UInt8]
    }

    /// Map a pattern texture onto a nail region with per-finger orientation.
    static func mapTexture(
        pixels: inout [Int],
        confidenceValues: [Float],
        components: [Int: ConnectedComponents.ComponentProperties],
        inputSize: Int,
        patternImage: UIImage?,
        orientations: [FingerOrientation] = [],
        threshold: Float = 0.5
    ) {
        // Initialize with transparent
        for i in 0..<pixels.count {
            pixels[i] = 0x00000000
        }

        guard let patternImage = patternImage else {
            // Fallback: show raw mask
            for i in 0..<confidenceValues.count {
                if confidenceValues[i] > threshold {
                    pixels[i] = argb(a: 255, r: 50, g: 50, b: 180)
                }
            }
            return
        }

        guard components.isEmpty == false else {
            // No components, fallback to raw mask
            for i in 0..<confidenceValues.count {
                if confidenceValues[i] > threshold {
                    pixels[i] = argb(a: 255, r: 50, g: 50, b: 180)
                }
            }
            return
        }

        guard let cache = patternCacheFor(patternImage) else { return }
        let patternWidth = cache.width
        let patternHeight = cache.height
        // Local strong reference; `cache.pixels` is a value-type Array so
        // the closure below sees a stable copy.
        let patternPixels = cache.pixels

        @inline(__always)
        func getPatternPixel(_ x: Int, _ y: Int) -> Int {
            let idx = (y * patternWidth + x) * 4
            guard idx + 3 < patternPixels.count else { return 0 }
            let r = Int(patternPixels[idx])
            let g = Int(patternPixels[idx + 1])
            let b = Int(patternPixels[idx + 2])
            let a = Int(patternPixels[idx + 3])
            return (a << 24) | (r << 16) | (g << 8) | b
        }

        for (_, props) in components {
            // Match nail to closest finger tip for angle
            var matchedAngle: Double = 0
            var minDistStart = Double.greatestFiniteMagnitude
            var foundMatch = false

            if !orientations.isEmpty {
                for finger in orientations {
                    let fingerX = finger.tipX * Float(inputSize)
                    let fingerY = finger.tipY * Float(inputSize)
                    let dx = props.centerX - fingerX
                    let dy = props.centerY - fingerY
                    let dist = Double(dx * dx + dy * dy)

                    // Threshold: ~60px radius
                    if dist < 3600 && dist < minDistStart {
                        minDistStart = dist
                        matchedAngle = finger.angle
                        foundMatch = true
                    }
                }
            }

            let finalAngle = foundMatch ? matchedAngle : 0.0

            // Draw area
            let maxDim = max(props.boxWidth, props.boxHeight)
            let drawRadius = Int(maxDim * 1.5)

            let startX = max(0, Int(props.centerX) - drawRadius)
            let endX = min(inputSize - 1, Int(props.centerX) + drawRadius)
            let startY = max(0, Int(props.centerY) - drawRadius)
            let endY = min(inputSize - 1, Int(props.centerY) + drawRadius)

            let sinA = Float(sin(finalAngle))
            let cosA = Float(cos(finalAngle))
            let nailWidth = props.boxWidth
            let nailHeight = props.boxHeight * 2.2

            for y in startY...endY {
                for x in startX...endX {
                    let dx = Float(x) - props.centerX
                    let dy = Float(y) - props.centerY

                    // Inverse rotation to local nail space
                    let u = dx * cosA + dy * sinA
                    let v = -dx * sinA + dy * cosA

                    let texBottomV = props.boxHeight / 2.0
                    let texTopV = texBottomV - nailHeight
                    let relativeY = (v - texTopV) / (texBottomV - texTopV)
                    let relativeX = (u - (-nailWidth / 2)) / nailWidth

                    if relativeX >= 0 && relativeX <= 1 && relativeY >= 0 && relativeY <= 1 {
                        let patternX = Int(relativeX * Float(patternWidth)).clamped(to: 0, patternWidth - 1)
                        let patternY = Int(relativeY * Float(patternHeight)).clamped(to: 0, patternHeight - 1)
                        let pixelColor = getPatternPixel(patternX, patternY)

                        // White-keying: skip near-white pixels
                        let r = (pixelColor >> 16) & 0xFF
                        let g2 = (pixelColor >> 8) & 0xFF
                        let b2 = pixelColor & 0xFF

                        if r < 240 || g2 < 240 || b2 < 240 {
                            pixels[y * inputSize + x] = pixelColor
                        }
                    }
                }
            }
        }
    }

    /// Calculate angle between finger tip and DIP joint for nail orientation.
    static func calculateFingerAngle(tipX: Float, tipY: Float, dipX: Float, dipY: Float) -> Double {
        let deltaX = tipX - dipX
        let deltaY = tipY - dipY
        return atan2(Double(deltaY), Double(deltaX)) + (Double.pi / 2)
    }

    /// Lookup-or-extract the cached RGBA byte buffer for `image`. Cache is
    /// keyed on the underlying CGImage pointer identity, so swapping the
    /// pattern triggers exactly one re-extract.
    private static func patternCacheFor(_ image: UIImage) -> PatternCache? {
        guard let cgImage = image.cgImage else { return nil }
        let key = ObjectIdentifier(cgImage)

        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let existing = patternCache, existing.cgImageRef == key {
            return existing
        }

        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: patternColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let cache = PatternCache(cgImageRef: key, width: width, height: height, pixels: pixels)
        patternCache = cache
        return cache
    }

    /// Create ARGB_8888 color int.
    private static func argb(a: Int, r: Int, g: Int, b: Int) -> Int {
        return (a & 0xFF) << 24 | (r & 0xFF) << 16 | (g & 0xFF) << 8 | (b & 0xFF)
    }
}

/// Finger orientation with angle for texture rotation.
struct FingerOrientation {
    let tipX: Float
    let tipY: Float
    let dipX: Float
    let dipY: Float
    let angle: Double
}

extension Int {
    func clamped(to lower: Int, _ upper: Int) -> Int {
        return Swift.min(Swift.max(self, lower), upper)
    }
}
