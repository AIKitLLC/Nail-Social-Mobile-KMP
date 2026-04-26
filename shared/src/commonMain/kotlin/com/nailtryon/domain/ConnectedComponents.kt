package com.nailtryon.domain

/**
 * Pure Kotlin implementation of Connected Components Labeling (CCL)
 * using two-pass algorithm with Union-Find for nail segmentation mask processing.
 *
 * This is shared between Android (TFLite) and iOS (CoreML) platforms.
 */
object ConnectedComponents {

    data class ComponentBox(
        var left: Int = Int.MAX_VALUE,
        var top: Int = Int.MAX_VALUE,
        var right: Int = Int.MIN_VALUE,
        var bottom: Int = Int.MIN_VALUE
    ) {
        fun width() = right - left + 1
        fun height() = bottom - top + 1
        fun addPoint(x: Int, y: Int) {
            if (x < left) left = x
            if (x > right) right = x
            if (y < top) top = y
            if (y > bottom) bottom = y
        }
    }

    data class ComponentProperties(
        val centerX: Double,
        val centerY: Double,
        val boxWidth: Int,
        val boxHeight: Int
    )

    /**
     * Find connected components in a binary segmentation mask.
     * @param confidenceValues Float array from model output (size = inputSize * inputSize)
     * @param inputSize Width/height of the square input
     * @param threshold Confidence threshold (default 0.8)
     * @return Pair of (labels array, bounding boxes map)
     */
    fun findComponents(
        confidenceValues: FloatArray,
        inputSize: Int,
        threshold: Float = 0.8f
    ): Pair<IntArray, Map<Int, ComponentBox>> {
        val labels = IntArray(inputSize * inputSize)
        var nextLabel = 1
        val parent = IntArray(inputSize * inputSize / 2 + 1) { it }

        fun find(i: Int): Int {
            var root = i
            while (root != parent[root]) root = parent[root]
            var curr = i
            while (curr != root) {
                val next = parent[curr]
                parent[curr] = root
                curr = next
            }
            return root
        }

        fun union(i: Int, j: Int) {
            val rootI = find(i)
            val rootJ = find(j)
            if (rootI != rootJ) parent[rootJ] = rootI
        }

        // First pass: assign labels
        for (y in 0 until inputSize) {
            for (x in 0 until inputSize) {
                val index = y * inputSize + x
                if (confidenceValues[index] > threshold) {
                    var leftLabel = 0
                    var topLabel = 0
                    if (x > 0) leftLabel = labels[index - 1]
                    if (y > 0) topLabel = labels[index - inputSize]

                    labels[index] = when {
                        leftLabel != 0 && topLabel != 0 -> {
                            if (leftLabel != topLabel) union(leftLabel, topLabel)
                            minOf(leftLabel, topLabel)
                        }
                        leftLabel != 0 -> leftLabel
                        topLabel != 0 -> topLabel
                        else -> {
                            val newLabel = nextLabel++
                            newLabel
                        }
                    }
                }
            }
        }

        // Second pass: resolve equivalence classes and compute bounding boxes
        val finalBoundingBoxes = HashMap<Int, ComponentBox>()
        val rootToFinalLabel = HashMap<Int, Int>()
        var finalLabelCounter = 1

        for (i in labels.indices) {
            if (labels[i] > 0) {
                val root = find(labels[i])
                val finalId = rootToFinalLabel.getOrPut(root) { finalLabelCounter++ }
                labels[i] = finalId
                val x = i % inputSize
                val y = i / inputSize
                val box = finalBoundingBoxes.getOrPut(finalId) { ComponentBox() }
                box.addPoint(x, y)
            }
        }

        return Pair(labels, finalBoundingBoxes)
    }

    /**
     * Calculate centroid and bounding box properties for each labeled component.
     */
    fun calculateProperties(
        labels: IntArray,
        boxes: Map<Int, ComponentBox>,
        inputSize: Int
    ): Map<Int, ComponentProperties> {
        val props = HashMap<Int, ComponentProperties>()
        val moments = HashMap<Int, DoubleArray>()

        for (i in labels.indices) {
            val label = labels[i]
            if (label > 0) {
                val y = i / inputSize
                val x = i % inputSize
                val m = moments.getOrPut(label) { DoubleArray(3) }
                m[0]++
                m[1] += x.toDouble()
                m[2] += y.toDouble()
            }
        }

        for ((label, m) in moments) {
            val n = m[0]
            val meanX = m[1] / n
            val meanY = m[2] / n
            val box = boxes[label]
            props[label] = ComponentProperties(
                centerX = meanX,
                centerY = meanY,
                boxWidth = box?.width() ?: 10,
                boxHeight = box?.height() ?: 10
            )
        }

        return props
    }
}
