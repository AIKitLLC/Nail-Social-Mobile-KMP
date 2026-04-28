package com.nailtryon.android.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import android.widget.Toast
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.nailtryon.data.NailApiService
import com.nailtryon.domain.NailPattern
import com.nailtryon.android.ml.NailDetector
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.Executors

// Local nail pattern drawable resources
private val patternDrawables = mapOf(
    "Classic Red" to 0,
    "French" to 0,
    "Pink Glitter" to 0,
    "Blue Gradient" to 0,
    "Gold Metallic" to 0,
    "Purple Sparkle" to 0
)

private val nailPatterns = listOf(
    NailPattern("Classic Red"),
    NailPattern("French"),
    NailPattern("Pink Glitter"),
    NailPattern("Blue Gradient"),
    NailPattern("Gold Metallic"),
    NailPattern("Purple Sparkle")
)

@Composable
fun NailTryOnScreen(designId: String?) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var detectionResult by remember { mutableStateOf<NailDetector.DetectionResult?>(null) }
    val detector = remember { NailDetector(context) }
    val cameraExecutor = remember { Executors.newSingleThreadExecutor() }
    var selectedPatternIndex by remember { mutableStateOf(if (designId != null) -1 else 0) }
    val scope = rememberCoroutineScope()

    // Load pattern from API or use local
    LaunchedEffect(designId, selectedPatternIndex) {
        if (selectedPatternIndex >= 0 && selectedPatternIndex < nailPatterns.size) {
            // Use local pattern on the fly — we'll fall back to showing the mask
            detector.patternBitmap = null // Will use raw mask fallback
        } else if (designId != null) {
            // Load from API
            try {
                val api = NailApiService()
                val design = withContext(Dispatchers.IO) {
                    api.getDesignById(designId)
                }
                val base64Str = design.extractedNailImageUrl ?: ""
                if (base64Str.isNotBlank()) {
                    val pureBase64 = if (base64Str.contains(",")) {
                        base64Str.substringAfter(",")
                    } else base64Str
                    val decodedBytes = Base64.decode(pureBase64, Base64.DEFAULT)
                    val bitmap = BitmapFactory.decodeByteArray(decodedBytes, 0, decodedBytes.size)
                    if (bitmap != null) {
                        detector.patternBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, false)
                    } else {
                        Toast.makeText(context, "Failed to decode nail texture", Toast.LENGTH_SHORT).show()
                    }
                }
            } catch (e: Exception) {
                Toast.makeText(context, "Failed to load design: ${e.message}", Toast.LENGTH_SHORT).show()
                selectedPatternIndex = 0
            }
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            cameraExecutor.shutdown()
            detector.close()
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        // 1. Camera Preview
        AndroidView(
            factory = { ctx ->
                val previewView = PreviewView(ctx)
                val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)

                cameraProviderFuture.addListener({
                    val cameraProvider = cameraProviderFuture.get()

                    val preview = Preview.Builder().build()
                    preview.setSurfaceProvider(previewView.surfaceProvider)

                    val imageAnalysis = ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                        .build()

                    val analyzer = NailAnalyzer(detector) { result ->
                        detectionResult = result
                    }
                    imageAnalysis.setAnalyzer(cameraExecutor, analyzer)

                    try {
                        cameraProvider.unbindAll()
                        cameraProvider.bindToLifecycle(
                            lifecycleOwner,
                            CameraSelector.DEFAULT_BACK_CAMERA,
                            preview,
                            imageAnalysis
                        )
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }, ContextCompat.getMainExecutor(ctx))

                previewView
            },
            modifier = Modifier.fillMaxSize()
        )

        // 2. AI Input Image overlay
        detectionResult?.inputBitmap?.let { bitmap ->
            Image(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = "AI Input",
                contentScale = ContentScale.Fit,
                modifier = Modifier.fillMaxSize()
            )
        }

        // 3. Mask overlay
        detectionResult?.maskBitmap?.let { bitmap ->
            Image(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = "Nail Mask",
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .fillMaxSize()
                    .alpha(0.7f)
            )
        }

        // 4. Pattern selection at bottom
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            Color.Transparent,
                            Color.Black.copy(alpha = 0.7f)
                        )
                    )
                )
                .padding(16.dp)
        ) {
            Text(
                text = if (selectedPatternIndex == -1) "Custom Design" else "Select Nail Pattern",
                color = Color.White,
                fontSize = 14.sp,
                modifier = Modifier.padding(bottom = 8.dp)
            )

            if (selectedPatternIndex != -1) {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(nailPatterns.size) { index ->
                        PatternThumbnail(
                            name = nailPatterns[index].name,
                            isSelected = index == selectedPatternIndex,
                            onClick = { selectedPatternIndex = index }
                        )
                    }
                }
            }
        }

        // Debug toggle hint
        Text(
            text = "Tap to toggle debug landmarks",
            color = Color.White.copy(alpha = 0.5f),
            fontSize = 10.sp,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(8.dp)
                .clickable { detector.showDebugLandmarks = !detector.showDebugLandmarks }
        )
    }
}

@Composable
fun PatternThumbnail(
    name: String,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .width(70.dp)
            .clickable(onClick = onClick)
    ) {
        Box(
            modifier = Modifier
                .size(60.dp)
                .background(
                    color = if (isSelected) Color.White.copy(alpha = 0.3f)
                    else Color.White.copy(alpha = 0.1f),
                    shape = RoundedCornerShape(8.dp)
                )
                .border(
                    width = if (isSelected) 2.dp else 0.dp,
                    color = Color.White,
                    shape = RoundedCornerShape(8.dp)
                )
                .padding(4.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = name.first().toString(),
                color = Color.White,
                fontSize = 20.sp
            )
        }
        Text(
            text = name,
            color = Color.White,
            fontSize = 10.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 4.dp)
        )
    }
}

// Copied from original to avoid complex import chains
class NailAnalyzer(
    private val detector: NailDetector,
    private val onResult: (NailDetector.DetectionResult) -> Unit
) : ImageAnalysis.Analyzer {
    override fun analyze(image: androidx.camera.core.ImageProxy) {
        val bitmap = image.toBitmap()
        if (bitmap != null) {
            val matrix = android.graphics.Matrix()
            matrix.postRotate(image.imageInfo.rotationDegrees.toFloat())
            val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            val result = detector.detectNails(rotated)
            if (result != null) {
                onResult(result)
            }
        }
        image.close()
    }
}
