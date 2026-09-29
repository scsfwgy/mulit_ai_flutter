package com.example.mulit_ai_flutter

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object WatchUpdateBridge {
    @Volatile var messenger: BinaryMessenger? = null
    @Volatile var processing = false

    fun notifyPhone() {
        Handler(Looper.getMainLooper()).post {
            messenger?.let {
                MethodChannel(it, "between_models/watch_updates").invokeMethod("changed", null)
            }
        }
    }
}
