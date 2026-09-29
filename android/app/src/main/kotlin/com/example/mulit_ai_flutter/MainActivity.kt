package com.example.mulit_ai_flutter

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        WatchUpdateBridge.messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "between_models/watch_updates")
            .setMethodCallHandler { call, result ->
                if (call.method == "isProcessing") result.success(WatchUpdateBridge.processing)
                else result.notImplemented()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "between_models/clipboard")
            .setMethodCallHandler { call, result ->
                if (call.method != "setHtml") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val plain = call.argument<String>("plain")
                val html = call.argument<String>("html")
                if (plain == null || html == null) {
                    result.error("invalid_arguments", "Missing clipboard content", null)
                    return@setMethodCallHandler
                }
                val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                clipboard.setPrimaryClip(ClipData.newHtmlText("Message", plain, html))
                result.success(null)
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (WatchUpdateBridge.messenger === flutterEngine.dartExecutor.binaryMessenger) {
            WatchUpdateBridge.messenger = null
        }
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
