import Foundation
import UIKit

/// Ported from shared Kotlin `ConnectedComponents.kt`
/// Connected component labeling and property calculation for nail segmentation.
class ConnectedComponents {
    
    struct ComponentProperties {
        let centerX: Float
        let centerY: Float
        let boxWidth: Float
        let boxHeight: Float
        let pixelCount: Int
    }
    
    /// Find connected components in the confidence map using thresholding.
    /// - Parameters:
    ///   - confidenceValues: Flat array of confidence values (inputSize * inputSize)
    ///   - inputSize: Dimension of the square input
    ///   - threshold: Confidence threshold (default 0.8)
    /// - Returns: (labels array, bounding boxes dictionary [componentId -> minX, minY, maxX, maxY])
    static func findComponents(
        _ confidenceValues: [Float],
        inputSize: Int,
        threshold: Float = 0.8
    ) -> (labels: [Int], boundingBoxes: [Int: (minX: Int, minY: Int, maxX: Int, maxY: Int)]) {
        
        var labels = [Int](repeating: 0, count: inputSize * inputSize)
        var boundingBoxes: [Int: (minX: Int, minY: Int, maxX: Int, maxY: Int)] = [:]
        var currentLabel = 0
        var equivalences: [Int: Int] = [:]
        
        func find(_ x: Int) -> Int {
            var root = x
            while equivalences[root] != nil && equivalences[root] != root {
                root = equivalences[root]!
            }
            // Path compression
            var cur = x
            while equivalences[cur] != nil && equivalences[cur] != cur {
                let next = equivalences[cur]!
                equivalences[cur] = root
                cur = next
            }
            return root
        }
        
        // First pass: assign labels with connected component analysis
        for y in 0..<inputSize {
            for x in 0..<inputSize {
                let idx = y * inputSize + x
                guard confidenceValues[idx] > threshold else { continue }
                
                let upIdx = (y > 0) ? ((y - 1) * inputSize + x) : -1
                let leftIdx = (x > 0) ? (y * inputSize + (x - 1)) : -1
                let upLabel = (upIdx >= 0 && labels[upIdx] > 0) ? labels[upIdx] : 0
                let leftLabel = (leftIdx >= 0 && labels[leftIdx] > 0) ? labels[leftIdx] : 0
                
                if upLabel == 0 && leftLabel == 0 {
                    currentLabel += 1
                    labels[idx] = currentLabel
                    boundingBoxes[currentLabel] = (x, y, x, y)
                } else if upLabel != 0 && leftLabel == 0 {
                    labels[idx] = upLabel
                    if var box = boundingBoxes[upLabel] {
                        box.maxX = max(box.maxX, x)
                        box.maxY = max(box.maxY, y)
                        boundingBoxes[upLabel] = box
                    }
                } else if upLabel == 0 && leftLabel != 0 {
                    labels[idx] = leftLabel
                    if var box = boundingBoxes[leftLabel] {
                        box.maxX = max(box.maxX, x)
                        box.maxY = max(box.maxY, y)
                        boundingBoxes[leftLabel] = box
                    }
                } else {
                    // Both neighbors have labels - merge
                    let minLabel = min(upLabel, leftLabel)
                    let maxLabel = max(upLabel, leftLabel)
                    labels[idx] = minLabel
                    equivalences[maxLabel] = minLabel
                    
                    if var minBox = boundingBoxes[minLabel],
                       var maxBox = boundingBoxes[maxLabel] {
                        minBox.minX = min(minBox.minX, x, maxBox.minX)
                        minBox.minY = min(minBox.minY, y, maxBox.minY)
                        minBox.maxX = max(minBox.maxX, x, maxBox.maxX)
                        minBox.maxY = max(minBox.maxY, y, maxBox.maxY)
                        boundingBoxes[minLabel] = minBox
                    }
                }
            }
        }
        
        // Second pass: resolve equivalences
        for i in 0..<labels.count {
            if labels[i] > 0 {
                labels[i] = find(labels[i])
            }
        }
        
        // Merge bounding boxes after equivalence resolution
        var mergedBoxes: [Int: (minX: Int, minY: Int, maxX: Int, maxY: Int)] = [:]
        for (label, box) in boundingBoxes {
            let rootLabel = find(label)
            if let existing = mergedBoxes[rootLabel] {
                mergedBoxes[rootLabel] = (
                    min(existing.minX, box.minX),
                    min(existing.minY, box.minY),
                    max(existing.maxX, box.maxX),
                    max(existing.maxY, box.maxY)
                )
            } else {
                mergedBoxes[rootLabel] = box
            }
        }
        
        return (labels, mergedBoxes)
    }
    
    /// Calculate properties for each connected component.
    static func calculateProperties(
        labels: [Int],
        boundingBoxes: [Int: (minX: Int, minY: Int, maxX: Int, maxY: Int)],
        inputSize: Int
    ) -> [Int: ComponentProperties] {
        
        var properties: [Int: ComponentProperties] = [:]
        
        // Calculate pixel counts
        var pixelCounts: [Int: Int] = [:]
        for label in labels {
            if label > 0 {
                pixelCounts[label] = (pixelCounts[label] ?? 0) + 1
            }
        }
        
        for (label, box) in boundingBoxes {
            // Filter out noise: require minimum pixel count
            let count = pixelCounts[label] ?? 0
            guard count > 20 else { continue }
            
            let centerX = Float(box.minX + box.maxX) / 2.0
            let centerY = Float(box.minY + box.maxY) / 2.0
            let boxWidth = Float(box.maxX - box.minX)
            let boxHeight = Float(box.maxY - box.minY)
            
            properties[label] = ComponentProperties(
                centerX: centerX,
                centerY: centerY,
                boxWidth: boxWidth,
                boxHeight: boxHeight,
                pixelCount: count
            )
        }
        
        return properties
    }
}
