package com.nailtryon.android.ml

import android.content.Context
import android.graphics.Bitmap
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.gpu.CompatibilityList
import org.tensorflow.lite.gpu.GpuDelegate
import org.tensorflow.lite.support.common.ops.CastOp
import org.tensorflow.lite.support.image.ImageProcessor
import org.tensorflow.lite.support.image.TensorImage
import org.tensorflow.lite.support.image.ops.ResizeOp
import org.tensorflow.lite.support.image.ops.ResizeWithCropOrPadOp
import com.nailtryon.domain.ConnectedComponents
import com.nailtryon.domain.TextureMapper
import com.nailtryon.domain.HandAnalysisData
import com.nailtryon.domain.FingerOrientation
import java.nio.ByteBuffer
import java.nio.ByteOrder

class NailDetector(context: Context) {

    private var interpreter: Interpreter? = null
    private val modelName = "nail_detect_model.tflite"
    private val inputSize = 256
    var patternBitmap: Bitmap? = null
    var showDebugLandmarks: Boolean = false
    private var handDetector: HandOrientationDetector? = null

    init {
        setupInterpreter(context)
        handDetector = HandOrientationDetector(context)
    }

    private fun setupInterpreter(context: Context) {
        try {
            if (CompatibilityList().isDelegateSupportedOnThisDevice) {
                val options = Interpreter.Options()
                options.addDelegate(GpuDelegate())
                interpreter = loadModel(context, options)
                return
            }
        } catch (e: Exception) {
            interpreter = null
        }

        if (interpreter == null) {
            try {
                val options = Interpreter.Options()
                options.setNumThreads(4)
                interpreter = loadModel(context, options)
            } catch (e: Exception) {
                android.util.Log.e("NailDetector", "Failed to init interpreter: ${e.message}")
            }
        }
    }

    private fun loadModel(context: Context, options: Interpreter.Options): Interpreter {
        val fd = context.assets.openFd(modelName)
        val fis = java.io.FileInputStream(fd.fileDescriptor)
        val channel = fis.channel
        val byteBuffer = channel.map(
            java.nio.channels.FileChannel.MapMode.READ_ONLY,
            fd.startOffset,
            fd.declaredLength
        )
        return Interpreter(byteBuffer, options)
    }

    data class DetectionResult(val inputBitmap: Bitmap, val maskBitmap: Bitmap)

    fun detectNails(bitmap: Bitmap): DetectionResult? {
        if (interpreter == null) return null

        val minDim = minOf(bitmap.width, bitmap.height)
        val displayProcessor = ImageProcessor.Builder()
            .add(ResizeWithCropOrPadOp(minDim, minDim))
            .add(ResizeOp(inputSize, inputSize, ResizeOp.ResizeMethod.BILINEAR))
            .build()

        val displayImage = displayProcessor.process(TensorImage.fromBitmap(bitmap))
        val inputBitmap = displayImage.bitmap

        val inferenceProcessor = ImageProcessor.Builder()
            .add(CastOp(org.tensorflow.lite.DataType.FLOAT32))
            .build()
        val inferenceInput = inferenceProcessor.process(displayImage)

        val outputBuffer = ByteBuffer.allocateDirect(1 * inputSize * inputSize * 1 * 4)
        outputBuffer.order(ByteOrder.nativeOrder())

        val handAnalysis = handDetector?.analyzeHand(inputBitmap)
        val orientations = handAnalysis?.orientations ?: emptyList()
        val landmarks = handAnalysis?.landmarks ?: emptyList()

        interpreter?.run(inferenceInput.buffer, outputBuffer)

        val maskBitmap = convertOutputToMask(inputBitmap, outputBuffer, orientations)

        var debugInput = inputBitmap
        if (showDebugLandmarks && landmarks.isNotEmpty()) {
            debugInput = inputBitmap.copy(Bitmap.Config.ARGB_8888, true)
            val canvas = android.graphics.Canvas(debugInput)
            val paint = android.graphics.Paint().apply {
                color = android.graphics.Color.GREEN
                strokeWidth = 3f
                style = android.graphics.Paint.Style.STROKE
            }
            val pointPaint = android.graphics.Paint().apply {
                color = android.graphics.Color.RED
                style = android.graphics.Paint.Style.FILL
            }

            val connections = listOf(
                Pair(0, 1), Pair(1, 2), Pair(2, 3), Pair(3, 4),
                Pair(0, 5), Pair(5, 6), Pair(6, 7), Pair(7, 8),
                Pair(0, 9), Pair(9, 10), Pair(10, 11), Pair(11, 12),
                Pair(0, 13), Pair(13, 14), Pair(14, 15), Pair(15, 16),
                Pair(0, 17), Pair(17, 18), Pair(18, 19), Pair(19, 20),
                Pair(5, 9), Pair(9, 13), Pair(13, 17)
            )

            for ((start, end) in connections) {
                if (start < landmarks.size && end < landmarks.size) {
                    canvas.drawLine(
                        landmarks[start].x * inputSize, landmarks[start].y * inputSize,
                        landmarks[end].x * inputSize, landmarks[end].y * inputSize,
                        paint
                    )
                }
            }
            for (p in landmarks) {
                canvas.drawCircle(p.x * inputSize, p.y * inputSize, 3f, pointPaint)
            }
        }

        return DetectionResult(debugInput, maskBitmap)
    }

    private fun convertOutputToMask(
        inputBitmap: Bitmap,
        outputBuffer: ByteBuffer,
        orientations: List<FingerOrientation>
    ): Bitmap {
        outputBuffer.rewind()

        val confidenceValues = FloatArray(inputSize * inputSize)
        for (i in confidenceValues.indices) {
            confidenceValues[i] = outputBuffer.float
        }

        val (labels, boundingBoxes) = ConnectedComponents.findComponents(
            confidenceValues, inputSize, 0.8f
        )
        val components = ConnectedComponents.calculateProperties(labels, boundingBoxes, inputSize)

        val pixels = IntArray(inputSize * inputSize)
        val pattern = patternBitmap

        if (pattern != null && components.isNotEmpty()) {
            TextureMapper.mapTexture(
                pixels = pixels,
                confidenceValues = confidenceValues,
                components = components,
                inputSize = inputSize,
                patternWidth = pattern.width,
                patternHeight = pattern.height,
                getPatternPixel = { x, y -> pattern.getPixel(x, y) },
                orientations = orientations
            )
        }

        return Bitmap.createBitmap(pixels, inputSize, inputSize, Bitmap.Config.ARGB_8888)
    }

    fun close() {
        handDetector?.close()
        interpreter?.close()
    }
}
