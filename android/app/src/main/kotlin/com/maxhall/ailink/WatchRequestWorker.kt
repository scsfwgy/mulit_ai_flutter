package com.maxhall.ailink

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
import java.io.ByteArrayOutputStream
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
        val legacyRequest = kind == "audio" || kind == "confirm"
        if (legacyRequest) {
            WatchUpdateBridge.processing = true
            WatchUpdateBridge.notifyPhone()
        }
        return try {
            val payload = withContext(Dispatchers.IO) {
                val client = Wearable.getDataClient(applicationContext)
                val item = Tasks.await(client.getDataItem(uri)) ?: error("Missing request")
                val data = DataMapItem.fromDataItem(item).dataMap
                val args = if (kind == "config") {
                    val nodeId = uri.host ?: error("Missing watch node")
                    mapOf<String, Any>("id" to id, "kind" to kind, "nodeId" to nodeId)
                } else if (kind == "turn") {
                    val asset = data.getAsset("turn") ?: error("Missing watch turn")
                    val stream = Tasks.await(client.getFdForAsset(asset)).inputStream
                        ?: error("Missing watch turn stream")
                    val bytes = stream.use { input ->
                        val output = ByteArrayOutputStream()
                        val chunk = ByteArray(8192)
                        while (true) {
                            val count = input.read(chunk)
                            if (count < 0) break
                            if (output.size() + count > 512 * 1024) error("Watch turn too large")
                            output.write(chunk, 0, count)
                        }
                        output.toByteArray()
                    }
                    if (bytes.isEmpty() || bytes.size > 512 * 1024) error("Watch turn too large")
                    val turn = String(bytes, Charsets.UTF_8)
                    mapOf<String, Any>("id" to id, "kind" to kind, "turn" to turn)
                } else if (kind == "remote-chat") {
                    val asset = data.getAsset("history") ?: error("Missing watch history")
                    val stream = Tasks.await(client.getFdForAsset(asset)).inputStream
                        ?: error("Missing watch history stream")
                    val bytes = stream.use { readLimited(it, 4 * 1024 * 1024) }
                    mapOf<String, Any>(
                        "id" to id, "kind" to kind,
                        "history" to String(bytes, Charsets.UTF_8),
                        "providerId" to data.getInt("providerId"),
                        "model" to (data.getString("model") ?: error("Missing model")),
                    )
                } else if (kind == "remote-tts") {
                    val text = data.getString("text") ?: error("Missing speech text")
                    if (text.length > 1800) error("Speech text too long")
                    mapOf<String, Any>("id" to id, "kind" to kind, "text" to text)
                } else if (kind == "confirm") {
                    val transcript = data.getString("transcript") ?: error("Missing transcript")
                    if (transcript.isBlank() || transcript.length > 10000) error("Invalid transcript")
                    mapOf<String, Any>("id" to id, "kind" to kind, "transcript" to transcript)
                } else {
                    val asset = data.getAsset("audio") ?: error("Missing audio")
                    val stream = Tasks.await(client.getFdForAsset(asset)).inputStream
                        ?: error("Missing audio stream")
                    val bytes = stream.use { readLimited(it, 4 * 1024 * 1024) }
                    if (bytes.isEmpty() || bytes.size > 4 * 1024 * 1024) error("Invalid audio")
                    mapOf<String, Any>("id" to id, "kind" to
                        if (kind == "remote-asr") kind else "audio", "audio" to bytes)
                }
                if (kind == "audio" || kind == "confirm" || kind.startsWith("remote-")) {
                    Tasks.await(client.deleteDataItems(uri))
                }
                args
            }
            if (kind == "audio" || kind == "confirm") {
                publish(id, if (kind == "confirm") "thinking" else "transcribing")
            }
            processWithFlutter(id, payload)
            if (kind == "config" || kind == "turn") {
                withContext(Dispatchers.IO) {
                    Tasks.await(Wearable.getDataClient(applicationContext).deleteDataItems(uri))
                }
            }
            Result.success()
        } catch (_: Exception) {
            if (kind == "config" || kind == "turn") {
                Result.retry()
            } else {
                publish(id, "error", error = "手机未能处理请求，请检查连接后重试",
                    networkFailure = kind.startsWith("remote-"))
                Result.failure()
            }
        } finally {
            if (legacyRequest) {
                WatchUpdateBridge.processing = false
                WatchUpdateBridge.notifyPhone()
            }
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
                                            args["networkFailure"] as? Boolean ?: false,
                                        )
                                        result.success(null)
                                    } catch (_: Exception) {
                                        result.error("sync_failed", "无法同步手表内容", null)
                                    }
                                }
                            }
                        }
                        "sendConfig" -> {
                            val args = call.arguments as? Map<*, *>
                            val nodeId = args?.get("nodeId") as? String
                            val bytes = args?.get("payload") as? ByteArray
                            if (args?.get("id") != id || nodeId.isNullOrBlank() ||
                                bytes == null || bytes.isEmpty() || bytes.size > 60000) {
                                result.error("bad_config", "Invalid watch configuration", null)
                            } else {
                                kotlinx.coroutines.CoroutineScope(Dispatchers.IO).launch {
                                    try {
                                        Tasks.await(Wearable.getMessageClient(applicationContext)
                                            .sendMessage(nodeId, "/between-models/config", bytes))
                                        result.success(null)
                                    } catch (_: Exception) {
                                        result.error("config_sync_failed", "无法发送手表配置", null)
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

    private fun readLimited(input: java.io.InputStream, maxBytes: Int): ByteArray {
        val output = ByteArrayOutputStream()
        val chunk = ByteArray(8192)
        while (true) {
            val count = input.read(chunk)
            if (count < 0) break
            if (output.size() + count > maxBytes) error("Watch asset too large")
            output.write(chunk, 0, count)
        }
        return output.toByteArray()
    }

    private suspend fun publish(
        id: String,
        stage: String,
        transcript: String? = null,
        answer: String? = null,
        error: String? = null,
        audio: ByteArray? = null,
        audioFormat: String? = null,
        networkFailure: Boolean = false,
    ) = withContext(Dispatchers.IO) {
        val map = PutDataMapRequest.create("/between-models/reply/$id")
        map.dataMap.putString("id", id)
        map.dataMap.putString("stage", stage)
        map.dataMap.putLong("updated", System.currentTimeMillis())
        if (transcript != null) map.dataMap.putString("transcript", transcript)
        if (answer != null) {
            val encoded = answer.toByteArray(Charsets.UTF_8)
            if (encoded.size > 60 * 1024) {
                map.dataMap.putAsset("answerAsset", Asset.createFromBytes(encoded))
            } else {
                map.dataMap.putString("answer", answer)
            }
        }
        if (error != null) map.dataMap.putString("error", error)
        if (networkFailure) map.dataMap.putBoolean("networkFailure", true)
        if (audio != null && audio.size <= 24 * 1024 * 1024) {
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
