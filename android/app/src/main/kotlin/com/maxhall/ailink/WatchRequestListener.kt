package com.maxhall.ailink

import android.content.Context
import android.net.Uri
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.workDataOf
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.WearableListenerService

class WatchRequestListener : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        for (event in events) {
            if (event.type != DataEvent.TYPE_CHANGED) continue
            val uri = event.dataItem.uri
            val id = uri.lastPathSegment ?: continue
            val kind = when {
                uri.path.orEmpty().startsWith("/between-models/request/") -> "audio"
                uri.path.orEmpty().startsWith("/between-models/confirm/") -> "confirm"
                uri.path.orEmpty().startsWith("/between-models/config-request/") -> "config"
                uri.path.orEmpty().startsWith("/between-models/turn/") -> "turn"
                uri.path.orEmpty().startsWith("/between-models/remote-asr/") -> "remote-asr"
                uri.path.orEmpty().startsWith("/between-models/remote-chat/") -> "remote-chat"
                uri.path.orEmpty().startsWith("/between-models/remote-tts/") -> "remote-tts"
                else -> continue
            }
            if (!id.matches(Regex("[a-f0-9-]{36}"))) continue
            schedule(applicationContext, uri, kind)
        }
    }

    companion object {
        private fun schedule(context: Context, uri: Uri, kind: String) {
            val id = uri.lastPathSegment ?: return
            val request = OneTimeWorkRequestBuilder<WatchRequestWorker>()
                .setInputData(workDataOf("uri" to uri.toString(), "id" to id, "kind" to kind))
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                "watch-$kind-$id", ExistingWorkPolicy.KEEP, request,
            )
        }
    }
}
