package com.maxhall.ailink.wear

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import java.util.UUID
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService

class WatchConfigListener : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        for (event in events) {
            if (event.type != DataEvent.TYPE_CHANGED || event.dataItem.uri.path != "/between-models/config-changed") continue
            val prefs = getSharedPreferences("watch_config_requests", MODE_PRIVATE)
            val id = prefs.getString("id", null) ?: UUID.randomUUID().toString().also { prefs.edit().putString("id", it).apply() }
            val request = PutDataMapRequest.create("/between-models/config-request/$id")
            request.dataMap.putLong("updated", System.currentTimeMillis())
            Wearable.getDataClient(this).putDataItem(request.asPutDataRequest().setUrgent())
        }
    }

    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != "/between-models/config") return
        try {
            WatchConfigStore(this).save(event.data)
        } catch (_: Exception) {
            // A malformed configuration is ignored; the watch can request it again.
        }
    }
}
