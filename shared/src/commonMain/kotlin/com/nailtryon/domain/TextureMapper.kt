package com.nailtryon.domain

import kotlin.math.*

/**
 * Domain models for hand and nail detection.
 * Shared across all platforms.
 */

data class FingerOrientation(
    val tipX: Float,
    val tipY: Float,
    val dipX: Float,
    val dipY: Float,
    val angle: Double
)

data class NormalizedPoint(val x: Float, val y: Float)

data class HandAnalysisData(
    val orientations: List<FingerOrientation>,
    val landmarks: List<NormalizedPoint>
)

data class NailPattern(
    val name: String,
    val drawableRes: Int = 0
)

/**
 * Pure math functions for texture mapping — shared between platforms.
 */
object TextureMapper {

    /**
     * Map a pattern texture onto a nail region defined by connected components.
     *
     * @param pixels Destination pixel array (ARGB_8888, size = inputSize * inputSize)
     * @param confidenceValues Raw model output (confidences)
     * @param components Connected components properties
     * @param inputSize Model input size (e.g. 256)
     * @param patternWidth Width of pattern bitmap
     * @param patternHeight Height of pattern bitmap
     * @param getPatternPixel Function to get ARGB pixel color from pattern at (x, y)
     * @param orientations Finger orientations for angle alignment
     */
    fun mapTexture(
        pixels: IntArray,
        confidenceValues: FloatArray,
        components: Map<Int, ConnectedComponents.ComponentProperties>,
        inputSize: Int,
        patternWidth: Int,
        patternHeight: Int,
        getPatternPixel: (Int, Int) -> Int,
        orientations: List<FingerOrientation> = emptyList(),
        threshold: Float = 0.5f
    ) {
        // Initialize with transparent
        for (i in pixels.indices) {
            pixels[i] = 0x00000000.toInt()
        }

        if (components.isEmpty()) {
            // Fallback: show raw mask
            for (i in confidenceValues.indices) {
                if (confidenceValues[i] > threshold) {
                    pixels[i] = androidColor(255, 50, 50, 180)
                }
            }
            return
        }

        for ((_, props) in components) {
            // Match nail to closest finger tip for angle
            var matchedAngle = 0.0
            var minDistStart = Double.MAX_VALUE
            var foundMatch = false

            if (orientations.isNotEmpty()) {
                for (finger in orientations) {
                    val fingerX = finger.tipX * inputSize
                    val fingerY = finger.tipY * inputSize
                    val dx = props.centerX - fingerX
                    val dy = props.centerY - fingerY
                    val dist = dx * dx + dy * dy

                    // Threshold: ~60px radius
                    if (dist < 3600 && dist < minDistStart) {
                        minDistStart = dist
                        matchedAngle = finger.angle
                        foundMatch = true
                    }
                }
            }

            val finalAngle = if (foundMatch) matchedAngle else 0.0

            // Draw area
            val maxDim = maxOf(props.boxWidth, props.boxHeight)
            val drawRadius = (maxDim * 1.5).toInt()

            val startX = (props.centerX - drawRadius).toInt().coerceIn(0, inputSize - 1)
            val endX = (props.centerX + drawRadius).toInt().coerceIn(0, inputSize - 1)
            val startY = (props.centerY - drawRadius).toInt().coerceIn(0, inputSize - 1)
            val endY = (props.centerY + drawRadius).toInt().coerceIn(0, inputSize - 1)

            val sinA = sin(finalAngle)
            val cosA = cos(finalAngle)
            val nailWidth = props.boxWidth.toFloat()
            val nailHeight = props.boxHeight * 2.2f

            for (y in startY..endY) {
                for (x in startX..endX) {
                    val dx = x - props.centerX
                    val dy = y - props.centerY

                    // Inverse rotation to local nail space
                    val u = (dx * cosA + dy * sinA).toFloat()
                    val v = (-dx * sinA + dy * cosA).toFloat()

                    val texBottomV = props.boxHeight / 2.0f
                    val texTopV = texBottomV - nailHeight
                    val relativeY = (v - texTopV) / (texBottomV - texTopV)
                    val relativeX = (u - (-nailWidth / 2)) / nailWidth

                    if (relativeX in 0f..1f && relativeY in 0f..1f) {
                        val patternX = (relativeX * patternWidth).toInt().coerceIn(0, patternWidth - 1)
                        val patternY = (relativeY * patternHeight).toInt().coerceIn(0, patternHeight - 1)
                        val pixelColor = getPatternPixel(patternX, patternY)

                        // White-keying: skip near-white pixels
                        val r = (pixelColor shr 16) and 0xFF
                        val g = (pixelColor shr 8) and 0xFF
                        val b = pixelColor and 0xFF

                        if (r < 240 || g < 240 || b < 240) {
                            pixels[y * inputSize + x] = pixelColor
                        }
                    }
                }
            }
        }
    }

    /**
     * Create ARGB_8888 color int (same as Android's Color.argb).
     */
    fun androidColor(a: Int, r: Int, g: Int, b: Int): Int {
        return (a and 0xFF shl 24) or (r and 0xFF shl 16) or (g and 0xFF shl 8) or (b and 0xFF)
    }

    /**
     * Calculate angle between finger tip and DIP joint for nail orientation.
     */
    fun calculateFingerAngle(tipX: Float, tipY: Float, dipX: Float, dipY: Float): Double {
        val deltaX = tipX - dipX
        val deltaY = tipY - dipY
        return atan2(deltaY.toDouble(), deltaX.toDouble()) + (PI / 2)
    }
}
