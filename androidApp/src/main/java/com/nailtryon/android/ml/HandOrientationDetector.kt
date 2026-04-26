package com.nailtryon.android.ml

import android.content.Context
import android.graphics.Bitmap
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.nailtryon.domain.HandAnalysisData
import com.nailtryon.domain.FingerOrientation
import com.nailtryon.domain.NormalizedPoint
import com.nailtryon.domain.TextureMapper

class HandOrientationDetector(context: Context) {
    private var handLandmarker: HandLandmarker? = null
    private val fingerTipIndices = listOf(4, 8, 12, 16, 20)
    private val fingerDipIndices = listOf(3, 7, 11, 15, 19)

    init {
        try {
            val baseOptions = BaseOptions.builder()
                .setModelAssetPath("hand_landmarker.task")
                .build()
            val options = HandLandmarker.HandLandmarkerOptions.builder()
                .setBaseOptions(baseOptions)
                .setMinHandDetectionConfidence(0.5f)
                .setMinHandPresenceConfidence(0.5f)
                .setNumHands(1)
                .setRunningMode(RunningMode.IMAGE)
                .build()
            handLandmarker = HandLandmarker.createFromOptions(context, options)
        } catch (e: Exception) {
            android.util.Log.e("HandOrientation", "Failed to init: ${e.message}")
        }
    }

    fun analyzeHand(bitmap: Bitmap): HandAnalysisData {
        if (handLandmarker == null) return HandAnalysisData(emptyList(), emptyList())
        return try {
            val mpImage = BitmapImageBuilder(bitmap).build()
            val result = handLandmarker?.detect(mpImage)

            if (result == null || result.landmarks().isEmpty()) {
                return HandAnalysisData(emptyList(), emptyList())
            }

            val landmarks = result.landmarks()[0]
            val orientations = ArrayList<FingerOrientation>()
            val normalizedLandmarks = ArrayList<NormalizedPoint>()

            for (landmark in landmarks) {
                normalizedLandmarks.add(NormalizedPoint(landmark.x(), landmark.y()))
            }

            for (i in fingerTipIndices.indices) {
                val tipIdx = fingerTipIndices[i]
                val dipIdx = fingerDipIndices[i]
                val tip = landmarks[tipIdx]
                val dip = landmarks[dipIdx]

                val angle = TextureMapper.calculateFingerAngle(
                    tip.x(), tip.y(), dip.x(), dip.y()
                )
                orientations.add(FingerOrientation(tip.x(), tip.y(), dip.x(), dip.y(), angle))
            }

            HandAnalysisData(orientations, normalizedLandmarks)
        } catch (e: Exception) {
            HandAnalysisData(emptyList(), emptyList())
        }
    }

    fun close() {
        handLandmarker?.close()
    }
}
