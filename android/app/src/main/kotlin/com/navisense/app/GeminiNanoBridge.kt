package com.navisense.app

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.SystemClock
import android.provider.Settings
import com.google.firebase.Firebase
import com.google.firebase.ai.DownloadStatus
import com.google.firebase.ai.InferenceMode
import com.google.firebase.ai.InferenceSource
import com.google.firebase.ai.OnDeviceConfig
import com.google.firebase.ai.OnDeviceModelStatus
import com.google.firebase.ai.ai
import com.google.firebase.ai.type.GenerativeBackend
import com.google.firebase.ai.type.PublicPreviewAPI
import com.google.firebase.ai.type.content
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.*
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Guarantees a [MethodChannel.Result] is answered at most once across async coroutines.
 */
internal class SafeResult(private val delegate: MethodChannel.Result) {
    private val replied = AtomicBoolean(false)

    fun success(value: Any?) {
        if (replied.compareAndSet(false, true)) {
            delegate.success(value)
        }
    }

    fun error(errorCode: String, errorMessage: String?, errorDetails: Any? = null) {
        if (replied.compareAndSet(false, true)) {
            delegate.error(errorCode, errorMessage, errorDetails)
        }
    }

    fun notImplemented() {
        if (replied.compareAndSet(false, true)) {
            delegate.notImplemented()
        }
    }
}

/**
 * Hybrid Android bridge for Gemini Nano 4 (`firebase-ai` + `firebase-ai-ondevice`),
 * native JPEG downscaling, device memory queries, and Android settings deep-links.
 */
@OptIn(PublicPreviewAPI::class)
class GeminiNanoBridge(
    private val context: Context,
    private val scope: CoroutineScope,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private var downloadSink: EventChannel.EventSink? = null

    private val model by lazy {
        Firebase.ai(backend = GenerativeBackend.googleAI()).generativeModel(
            modelName = CLOUD_MODEL_FOR_HYBRID,
            systemInstruction = content { text(DEFAULT_SYSTEM_INSTRUCTION) },
            onDeviceConfig = OnDeviceConfig(mode = InferenceMode.PREFER_ON_DEVICE),
        )
    }

    override fun onMethodCall(call: MethodCall, rawResult: MethodChannel.Result) {
        val result = SafeResult(rawResult)
        when (call.method) {
            "getStatus" -> handleGetStatus(result)
            "startDownload" -> handleStartDownload(result)
            "generate" -> handleGenerate(call, result)
            "getDeviceMemoryClass" -> handleGetDeviceMemoryClass(result)
            "compressJpeg" -> handleCompressJpeg(call, result)
            "openAppSettings" -> handleOpenAppSettings(result)
            else -> result.notImplemented()
        }
    }

    private fun handleGetStatus(result: SafeResult) {
        scope.launch {
            val mapped = runCatching {
                val status = model.onDeviceExtension?.checkStatus() ?: OnDeviceModelStatus.UNAVAILABLE
                mapStatus(status)
            }.getOrDefault("UNAVAILABLE")
            result.success(mapped)
        }
    }

    private fun handleStartDownload(result: SafeResult) {
        scope.launch {
            var totalBytes = 0L
            runCatching {
                val extension = model.onDeviceExtension
                    ?: throw IllegalStateException("OnDeviceExtension is unavailable")
                extension.download().collect { progress ->
                    when (progress) {
                        is DownloadStatus.DownloadStarted -> {
                            totalBytes = progress.bytesToDownload
                            emitDownloadEvent("DOWNLOADING", 0L, totalBytes)
                        }
                        is DownloadStatus.DownloadInProgress -> {
                            emitDownloadEvent("DOWNLOADING", progress.totalBytesDownloaded, totalBytes)
                        }
                        is DownloadStatus.DownloadCompleted -> {
                            emitDownloadEvent("COMPLETED", totalBytes, totalBytes)
                        }
                        is DownloadStatus.DownloadFailed -> {
                            withContext(Dispatchers.Main) {
                                downloadSink?.error(
                                    "NANO_FAILED",
                                    progress.exception.message ?: "Gemini Nano download failed",
                                    null,
                                )
                            }
                        }
                    }
                }
            }.onFailure { e ->
                withContext(Dispatchers.Main) {
                    downloadSink?.error(
                        "NANO_FAILED",
                        e.message ?: "Gemini Nano download failed",
                        null,
                    )
                }
            }
            result.success(null)
        }
    }

    private suspend fun emitDownloadEvent(state: String, bytesDownloaded: Long, totalBytes: Long) {
        withContext(Dispatchers.Main) {
            downloadSink?.success(
                mapOf(
                    "state" to state,
                    "bytesDownloaded" to bytesDownloaded,
                    "totalBytes" to totalBytes,
                ),
            )
        }
    }

    private fun handleGenerate(call: MethodCall, result: SafeResult) {
        val jpeg = call.argument<ByteArray>("jpeg")
        val summary = call.argument<String>("summary")
        if (jpeg == null || jpeg.isEmpty() || summary == null) {
            result.error("NANO_FAILED", "Missing jpeg bytes or summary", null)
            return
        }
        val customInstruction = call.argument<String>("systemInstruction")?.trim().orEmpty()
        val promptText = if (customInstruction.isNotEmpty() && customInstruction != DEFAULT_SYSTEM_INSTRUCTION) {
            "$customInstruction\nScene: $summary"
        } else {
            "Scene: $summary"
        }

        scope.launch {
            val started = SystemClock.elapsedRealtime()
            var bitmap: Bitmap? = null
            try {
                bitmap = withContext(Dispatchers.Default) {
                    BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)
                } ?: throw IllegalArgumentException("Failed to decode JPEG snapshot")

                val decodedBitmap = bitmap
                val response = withTimeout(NANO_TIMEOUT_MS) {
                    model.generateContent(
                        content {
                            image(decodedBitmap)
                            text(promptText)
                        },
                    )
                }
                val text = response.text?.trim().orEmpty()
                if (text.isEmpty()) {
                    result.error("NANO_FAILED", "Gemini Nano returned empty response", null)
                    return@launch
                }
                val source = if (response.inferenceSource == InferenceSource.ON_DEVICE) {
                    "ON_DEVICE"
                } else {
                    "IN_CLOUD"
                }
                result.success(
                    mapOf(
                        "text" to text,
                        "inferenceSource" to source,
                        "latencyMs" to (SystemClock.elapsedRealtime() - started).toInt(),
                    ),
                )
            } catch (_: TimeoutCancellationException) {
                result.error("NANO_TIMEOUT", "On-device inference exceeded ${NANO_TIMEOUT_MS}ms", null)
            } catch (e: Exception) {
                result.error("NANO_FAILED", e.message ?: "On-device inference failed", null)
            } finally {
                if (bitmap != null && !bitmap.isRecycled) {
                    bitmap.recycle()
                }
            }
        }
    }

    private fun handleGetDeviceMemoryClass(result: SafeResult) {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        am.getMemoryInfo(memInfo)
        result.success(
            mapOf(
                "memoryClassMb" to am.memoryClass,
                "totalMemBytes" to memInfo.totalMem,
            ),
        )
    }

    private fun handleCompressJpeg(call: MethodCall, result: SafeResult) {
        val path = call.argument<String>("path")
        val maxEdge = call.argument<Int>("maxEdge") ?: DEFAULT_MAX_EDGE
        val quality = call.argument<Int>("quality") ?: DEFAULT_JPEG_QUALITY
        if (path.isNullOrBlank()) {
            result.error("INVALID_ARGS", "Missing JPEG file path", null)
            return
        }
        scope.launch {
            try {
                val compressed = withContext(Dispatchers.Default) {
                    compressJpegFile(path, maxEdge.coerceAtLeast(64), quality.coerceIn(10, 100))
                }
                result.success(compressed)
            } catch (e: Exception) {
                result.error("COMPRESS_FAILED", e.message ?: "JPEG compression failed", null)
            }
        }
    }

    private fun handleOpenAppSettings(result: SafeResult) {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", context.packageName, null),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        result.success(null)
    }

    private fun compressJpegFile(path: String, maxEdge: Int, quality: Int): ByteArray {
        val file = File(path)
        require(file.exists()) { "Snapshot file does not exist: $path" }

        val boundsOptions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, boundsOptions)
        val srcWidth = boundsOptions.outWidth
        val srcHeight = boundsOptions.outHeight
        require(srcWidth > 0 && srcHeight > 0) { "Failed to decode image bounds" }

        val sampleOptions = BitmapFactory.Options().apply {
            inSampleSize = calculateInSampleSize(srcWidth, srcHeight, maxEdge)
        }
        var decoded: Bitmap? = null
        var scaled: Bitmap? = null
        try {
            decoded = BitmapFactory.decodeFile(path, sampleOptions)
                ?: error("Failed to decode bitmap from $path")
            val longest = max(decoded.width, decoded.height)
            val outputBitmap = if (longest > maxEdge) {
                val scale = maxEdge.toFloat() / longest.toFloat()
                val targetW = (decoded.width * scale).roundToInt().coerceAtLeast(1)
                val targetH = (decoded.height * scale).roundToInt().coerceAtLeast(1)
                scaled = Bitmap.createScaledBitmap(decoded, targetW, targetH, true)
                scaled
            } else {
                decoded
            }
            val stream = ByteArrayOutputStream()
            outputBitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)
            return stream.toByteArray()
        } finally {
            if (scaled != null && scaled != decoded && !scaled.isRecycled) {
                scaled.recycle()
            }
            if (decoded != null && !decoded.isRecycled) {
                decoded.recycle()
            }
        }
    }

    private fun calculateInSampleSize(width: Int, height: Int, maxEdge: Int): Int {
        var inSampleSize = 1
        var longest = max(width, height)
        while (longest / 2 >= maxEdge) {
            inSampleSize *= 2
            longest /= 2
        }
        return inSampleSize
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        downloadSink = events
    }

    override fun onCancel(arguments: Any?) {
        downloadSink = null
    }

    private fun mapStatus(status: OnDeviceModelStatus): String = when (status) {
        OnDeviceModelStatus.AVAILABLE -> "AVAILABLE"
        OnDeviceModelStatus.DOWNLOADABLE -> "DOWNLOADABLE"
        OnDeviceModelStatus.DOWNLOADING -> "DOWNLOADING"
        else -> "UNAVAILABLE"
    }

    companion object {
        const val METHOD_CHANNEL = "navisense/gemini_nano"
        const val DOWNLOAD_EVENT_CHANNEL = "navisense/gemini_nano/download"
        const val NANO_TIMEOUT_MS = 4000L
        const val DEFAULT_MAX_EDGE = 768
        const val DEFAULT_JPEG_QUALITY = 70
        const val CLOUD_MODEL_FOR_HYBRID = "gemini-3-flash"
        const val DEFAULT_SYSTEM_INSTRUCTION =
            "You are NaviSense, a calm spatial guide for a blind pedestrian. " +
                "Reply in ONE or TWO short sentences. Mention the closest hazard first with its direction " +
                "(left, ahead, right) and distance (very close, a few steps, far). Read important signs. " +
                "Never describe colors or aesthetics unless safety-relevant. Never speculate."
    }
}
