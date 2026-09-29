package com.maxhall.ailink.wear

import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService

class WatchConfigListener : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != "/between-models/config") return
        try {
            WatchConfigStore(this).save(event.data)
        } catch (_: Exception) {
            // A malformed configuration is ignored; the watch can request it again.
        }
    }
}
