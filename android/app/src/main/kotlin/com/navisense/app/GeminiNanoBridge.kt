package com.navisense.app

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import com.google.firebase.Firebase
import com.google.firebase.ai.DownloadStatus
import com.google.firebase.ai.InferenceMode
import com.google.firebase.ai.GenerativeModel
import com.google.firebase.ai.InferenceSource
import com.google.firebase.ai.OnDeviceConfig
import com.google.firebase.ai.OnDeviceModelOption
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

    // WHY: Gemini Nano 4 ships through the AICore *preview* channel, while
    // production devices expose the STABLE Nano build. We probe both and route
    // to whichever is actually usable instead of hard-wiring one.
    private val previewModel by lazy { buildModel(OnDeviceModelOption.PREVIEW) }
    private val stableModel by lazy { buildModel(OnDeviceModelOption.STABLE) }

    @Volatile private var activeModel: GenerativeModel? = null
    @Volatile private var activeOption: String = "STABLE"
    @Volatile private var activeModelName: String? = null
    @Volatile private var warmedUp = false

    private fun buildModel(option: OnDeviceModelOption): GenerativeModel =
        Firebase.ai(backend = GenerativeBackend.googleAI()).generativeModel(
            modelName = CLOUD_MODEL_FOR_HYBRID,
            systemInstruction = content { text(DEFAULT_SYSTEM_INSTRUCTION) },
            onDeviceConfig = OnDeviceConfig(
                mode = InferenceMode.PREFER_ON_DEVICE,
                maxOutputTokens = 96,
                temperature = 0.2f,
                modelOption = option,
            ),
        )

    private suspend fun statusOf(model: GenerativeModel, label: String): OnDeviceModelStatus =
        runCatching {
            model.onDeviceExtension?.checkStatus() ?: OnDeviceModelStatus.UNAVAILABLE
        }.onFailure { e ->
            Log.w(TAG, "checkStatus($label) failed: ${e.javaClass.simpleName}: ${e.message}")
        }.getOrDefault(OnDeviceModelStatus.UNAVAILABLE)

    /**
     * Picks the best on-device model: an AVAILABLE preview (Nano 4) model wins,
     * then an AVAILABLE stable model, then a downloadable preview, then stable.
     */
    private suspend fun resolveModel(): Pair<GenerativeModel, OnDeviceModelStatus> {
        val preview = statusOf(previewModel, "PREVIEW")
        val stable = statusOf(stableModel, "STABLE")
        Log.i(TAG, "on-device status preview=${mapStatus(preview)} stable=${mapStatus(stable)}")
        val (chosen, option, status) = when {
            preview == OnDeviceModelStatus.AVAILABLE -> Triple(previewModel, "PREVIEW", preview)
            stable == OnDeviceModelStatus.AVAILABLE -> Triple(stableModel, "STABLE", stable)
            preview == OnDeviceModelStatus.DOWNLOADING ||
                preview == OnDeviceModelStatus.DOWNLOADABLE -> Triple(previewModel, "PREVIEW", preview)
            else -> Triple(stableModel, "STABLE", stable)
        }
        if (activeModel !== chosen) warmedUp = false
        activeModel = chosen
        activeOption = option
        if (status == OnDeviceModelStatus.AVAILABLE) {
            activeModelName = runCatching { chosen.onDeviceExtension?.getModelName() }.getOrNull()
            warmUpOnce(chosen)
        }
        return chosen to status
    }

    private fun warmUpOnce(model: GenerativeModel) {
        if (warmedUp) return
        warmedUp = true
        // WHY: The first AICore inference pays a multi-second model load; doing
        // it at status time keeps the user's first tap inside the timeout.
        scope.launch {
            runCatching { model.onDeviceExtension?.warmUp() }
                .onSuccess { Log.i(TAG, "Gemini Nano warm-up done ($activeOption, $activeModelName)") }
                .onFailure { e ->
                    warmedUp = false
                    Log.w(TAG, "Gemini Nano warm-up failed: ${e.message}")
                }
        }
    }

    private suspend fun currentModel(): GenerativeModel = activeModel ?: resolveModel().first

    override fun onMethodCall(call: MethodCall, rawResult: MethodChannel.Result) {
        val result = SafeResult(rawResult)
        when (call.method) {
            "getStatus" -> handleGetStatus(result)
            "startDownload" -> handleStartDownload(result)
            "generate" -> handleGenerate(call, result)
            "getModelInfo" -> result.success(
                mapOf("option" to activeOption, "modelName" to activeModelName),
            )
            "hasCameraPermission" -> result.success(
                context.checkSelfPermission(android.Manifest.permission.CAMERA) ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED,
            )
            "getDeviceMemoryClass" -> handleGetDeviceMemoryClass(result)
            "compressJpeg" -> handleCompressJpeg(call, result)
            "openAppSettings" -> handleOpenAppSettings(result)
            else -> result.notImplemented()
        }
    }

    private fun handleGetStatus(result: SafeResult) {
        scope.launch {
            val mapped = runCatching { mapStatus(resolveModel().second) }
                .onFailure { e -> Log.w(TAG, "getStatus failed: ${e.message}") }
                .getOrDefault("UNAVAILABLE")
            result.success(mapped)
        }
    }

    private fun handleStartDownload(result: SafeResult) {
        scope.launch {
            var totalBytes = 0L
            runCatching {
                val extension = currentModel().onDeviceExtension
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
                            warmedUp = false
                            emitDownloadEvent("COMPLETED", totalBytes, totalBytes)
                        }
                        is DownloadStatus.DownloadFailed -> {
                            Log.w(TAG, "Gemini Nano download failed", progress.exception)
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
                val activeModel = currentModel()
                val response = withTimeout(NANO_TIMEOUT_MS) {
                    activeModel.generateContent(
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
                Log.i(
                    TAG,
                    "generate ok source=$source option=$activeOption model=$activeModelName " +
                        "latencyMs=${SystemClock.elapsedRealtime() - started}",
                )
                result.success(
                    mapOf(
                        "text" to text,
                        "inferenceSource" to source,
                        "latencyMs" to (SystemClock.elapsedRealtime() - started).toInt(),
                    ),
                )
            } catch (_: TimeoutCancellationException) {
                Log.w(TAG, "generate timed out after ${NANO_TIMEOUT_MS}ms (option=$activeOption)")
                result.error("NANO_TIMEOUT", "On-device inference exceeded ${NANO_TIMEOUT_MS}ms", null)
            } catch (e: Exception) {
                Log.w(TAG, "generate failed (option=$activeOption): ${e.javaClass.simpleName}: ${e.message}", e)
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
        private const val TAG = "NaviSenseNano"
        // WHY: Covers AICore image encoding + generation, and (under
        // PREFER_ON_DEVICE) the SDK's own automatic cloud fallback, both of
        // which must fit in one budget. 4 s left no headroom for either.
        const val NANO_TIMEOUT_MS = 8000L
        const val DEFAULT_MAX_EDGE = 768
        const val DEFAULT_JPEG_QUALITY = 70
        // WHY: The previous "gemini-3-flash" is not a documented model ID
        // (Gemini 3 Flash shipped as "gemini-3-flash-preview"; the official
        // Android hybrid sample uses "gemini-3.5-flash"). An invalid ID makes
        // every PREFER_ON_DEVICE cloud fallback fail.
        const val CLOUD_MODEL_FOR_HYBRID = "gemini-3.5-flash"
        const val DEFAULT_SYSTEM_INSTRUCTION =
            "You are NaviSense, a calm spatial guide for a blind pedestrian. " +
                "Reply in ONE or TWO short sentences. Mention the closest hazard first with its direction " +
                "(left, ahead, right) and distance (very close, a few steps, far). Read important signs. " +
                "Never describe colors or aesthetics unless safety-relevant. Never speculate."
    }
}
