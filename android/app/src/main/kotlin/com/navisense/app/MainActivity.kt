package com.navisense.app

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
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

class MainActivity : FlutterActivity() {
    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, rawResult ->
            handleMethodCall(call, SafeResult(rawResult))
        }
    }

    private fun handleMethodCall(call: MethodCall, result: SafeResult) {
        when (call.method) {
            "getDeviceMemoryClass" -> {
                val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                val memInfo = ActivityManager.MemoryInfo()
                am.getMemoryInfo(memInfo)
                result.success(
                    mapOf(
                        "memoryClassMb" to am.memoryClass,
                        "totalMemBytes" to memInfo.totalMem,
                    ),
                )
            }

            "compressJpeg" -> {
                val path = call.argument<String>("path")
                val maxEdge = call.argument<Int>("maxEdge") ?: DEFAULT_MAX_EDGE
                val quality = call.argument<Int>("quality") ?: DEFAULT_JPEG_QUALITY
                if (path.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "Missing JPEG file path", null)
                    return
                }
                mainScope.launch {
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

            "openAppSettings" -> {
                val intent = Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", packageName, null),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                result.success(null)
            }

            else -> result.notImplemented()
        }
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

    override fun onDestroy() {
        mainScope.cancel()
        super.onDestroy()
    }

    companion object {
        const val CHANNEL_NAME = "navisense/gemini_nano"
        const val DEFAULT_MAX_EDGE = 768
        const val DEFAULT_JPEG_QUALITY = 70
    }
}
