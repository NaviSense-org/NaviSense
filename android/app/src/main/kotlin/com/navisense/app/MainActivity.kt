package com.navisense.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {
    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var nanoBridge: GeminiNanoBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bridge = GeminiNanoBridge(context = this, scope = mainScope)
        nanoBridge = bridge

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            GeminiNanoBridge.METHOD_CHANNEL,
        ).setMethodCallHandler(bridge)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            GeminiNanoBridge.DOWNLOAD_EVENT_CHANNEL,
        ).setStreamHandler(bridge)
    }

    override fun onDestroy() {
        mainScope.cancel()
        nanoBridge = null
        super.onDestroy()
    }
}
