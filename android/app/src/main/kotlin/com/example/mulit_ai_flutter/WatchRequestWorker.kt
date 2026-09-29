package com.example.mulit_ai_flutter

import android.content.Context
import android.net.Uri
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Asset
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

class WatchRequestWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val id = inputData.getString("id") ?: return Result.failure()
        val uri = inputData.getString("uri")?.let(Uri::parse) ?: return Result.failure()
        val kind = inputData.getString("kind") ?: return Result.failure()
        WatchUpdateBridge.processing = true
        WatchUpdateBridge.notifyPhone()
        return try {
            val payload = withContext(Dispatchers.IO) {
                val client = Wearable.getDataClient(applicationContext)
                val item = Tasks.await(client.getDataItem(uri)) ?: error("Missing request")
                val data = DataMapItem.fromDataItem(item).dataMap
                val args = if (kind == "confirm") {
                    val transcript = data.getString("transcript") ?: error("Missing transcript")
                    if (transcript.isBlank() || transcript.length > 10000) error("Invalid transcript")
                    mapOf<String, Any>("id" to id, "kind" to kind, "transcript" to transcript)
                } else {
                    val asset = data.getAsset("audio") ?: error("Missing audio")
                    val stream = Tasks.await(client.getFdForAsset(asset)).inputStream
                        ?: error("Missing audio stream")
                    val bytes = stream.use { it.readBytes() }
                    if (bytes.isEmpty() || bytes.size > 4 * 1024 * 1024) error("Invalid audio")
                    mapOf<String, Any>("id" to id, "kind" to "audio", "audio" to bytes)
                }
                Tasks.await(client.deleteDataItems(uri))
                args
            }
            publish(id, if (kind == "confirm") "thinking" else "transcribing")
            processWithFlutter(id, payload)
            Result.success()
        } catch (_: Exception) {
            publish(id, "error", error = "手机未能处理请求，请检查连接后重试")
            Result.failure()
        } finally {
            WatchUpdateBridge.processing = false
            WatchUpdateBridge.notifyPhone()
        }
    }

    private suspend fun processWithFlutter(id: String, payload: Map<String, Any>) {
        val loader = FlutterInjector.instance().flutterLoader()
        withContext(Dispatchers.Main) { loader.startInitialization(applicationContext) }
        withContext(Dispatchers.Main) { loader.ensureInitializationComplete(applicationContext, null) }
        val ready = CompletableDeferred<Unit>()
        val finished = CompletableDeferred<Unit>()
        val engine = withContext(Dispatchers.Main) {
            FlutterEngine(applicationContext).also { flutterEngine ->
                val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "between_models/watch_worker")
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "ready" -> {
                            ready.complete(Unit)
                            result.success(null)
                        }
                        "publish" -> {
                            val args = call.arguments as? Map<*, *>
                            if (args?.get("id") != id) {
                                result.error("bad_request", "Invalid watch request", null)
                            } else {
                                kotlinx.coroutines.CoroutineScope(Dispatchers.IO).launch {
                                    try {
                                        publish(
                                            id,
                                            args["stage"] as? String ?: "replying",
                                            args["transcript"] as? String,
                                            args["answer"] as? String,
                                            args["error"] as? String,
                                            args["audio"] as? ByteArray,
                                            args["audioFormat"] as? String,
                                        )
                                        result.success(null)
                                    } catch (_: Exception) {
                                        result.error("sync_failed", "无法同步手表内容", null)
                                    }
                                }
                            }
                        }
                        else -> result.notImplemented()
                    }
                }
                val entrypoint = DartExecutor.DartEntrypoint(
                    loader.findAppBundlePath(), "watchBackgroundMain",
                )
                flutterEngine.dartExecutor.executeDartEntrypoint(entrypoint)
                this@WatchRequestWorker.channel = channel
            }
        }
        try {
            withTimeout(20_000) { ready.await() }
            withContext(Dispatchers.Main) {
                channel?.invokeMethod("process", payload,
                    object : MethodChannel.Result {
                        override fun success(result: Any?) { finished.complete(Unit) }
                        override fun error(code: String, message: String?, details: Any?) {
                            finished.completeExceptionally(IllegalStateException(code))
                        }
                        override fun notImplemented() {
                            finished.completeExceptionally(IllegalStateException("not_implemented"))
                        }
                    })
            }
            withTimeout(240_000) { finished.await() }
        } finally {
            channel = null
            withContext(Dispatchers.Main) { engine.destroy() }
        }
    }

    private var channel: MethodChannel? = null

    private suspend fun publish(
        id: String,
        stage: String,
        transcript: String? = null,
        answer: String? = null,
        error: String? = null,
        audio: ByteArray? = null,
        audioFormat: String? = null,
    ) = withContext(Dispatchers.IO) {
        val map = PutDataMapRequest.create("/between-models/reply/$id")
        map.dataMap.putString("id", id)
        map.dataMap.putString("stage", stage)
        map.dataMap.putLong("updated", System.currentTimeMillis())
        if (transcript != null) map.dataMap.putString("transcript", transcript)
        if (answer != null) map.dataMap.putString("answer", answer)
        if (error != null) map.dataMap.putString("error", error)
        if (audio != null && audio.size <= 16 * 1024 * 1024) {
            map.dataMap.putAsset("audio", Asset.createFromBytes(audio))
            map.dataMap.putString("audioFormat", audioFormat ?: "mp3")
        }
        Tasks.await(Wearable.getDataClient(applicationContext).putDataItem(map.asPutDataRequest().setUrgent()))
        if (stage == "thinking" || stage == "complete" || stage == "error") {
            WatchUpdateBridge.notifyPhone()
        }
        Unit
    }
}
