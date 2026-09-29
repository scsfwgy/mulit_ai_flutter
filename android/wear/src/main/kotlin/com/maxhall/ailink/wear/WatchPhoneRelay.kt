package com.maxhall.ailink.wear

import android.content.Context
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Asset
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

data class PhoneRelayResult(
    val transcript: String? = null,
    val answer: String? = null,
    val audio: ByteArray? = null,
    val audioFormat: String? = null,
)

/** Phone performs only the API call; the watch owns the turn and its history. */
class WatchPhoneRelay(private val context: Context, private val phoneNodeId: String) {
    private val client = Wearable.getDataClient(context)

    fun transcribe(wav: ByteArray): String {
        val result = request("remote-asr", 90_000, {
            it.dataMap.putAsset("audio", Asset.createFromBytes(wav))
        })
        return result.transcript?.takeIf { it.isNotBlank() }
            ?: throw PhoneRelayException("手机未返回识别文字", false)
    }

    fun reply(history: ByteArray, providerId: Int, model: String,
              onText: (String) -> Unit): String {
        var receivedText = false
        val result = try {
            request("remote-chat", 240_000, {
                it.dataMap.putAsset("history", Asset.createFromBytes(history))
                it.dataMap.putInt("providerId", providerId)
                it.dataMap.putString("model", model)
            }) { partial ->
                if (partial.isNotEmpty()) receivedText = true
                onText(partial)
            }
        } catch (error: PhoneRelayException) {
            if (receivedText && error.networkFailure) {
                throw PhoneRelayException("连接中断，已收到部分回答；为避免重复请求，请稍后手动重试", false)
            }
            throw error
        }
        return result.answer?.takeIf { it.isNotEmpty() }
            ?: throw PhoneRelayException("手机模型未返回文字", false)
    }

    fun speak(text: String): Pair<ByteArray, String> {
        val result = request("remote-tts", 90_000, {
            it.dataMap.putString("text", text)
        })
        return (result.audio ?: throw PhoneRelayException("手机未返回朗读音频", false)) to
            (result.audioFormat ?: "mp3")
    }

    private fun request(
        kind: String,
        timeoutMs: Long,
        fill: (PutDataMapRequest) -> Unit,
        onText: (String) -> Unit = {},
    ): PhoneRelayResult {
        val nodes = try { Tasks.await(Wearable.getNodeClient(context).connectedNodes) }
        catch (_: Exception) { throw PhoneRelayException("手机连接不可用", true) }
        if (nodes.none { it.id == phoneNodeId }) {
            throw PhoneRelayException("手机已断开连接", true)
        }
        val id = UUID.randomUUID().toString()
        val path = "/between-models/$kind/$id"
        val replyPath = "/between-models/reply/$id"
        val request = PutDataMapRequest.create(path).apply(fill)
        val updates = LinkedBlockingQueue<DataItem>()
        val listener = object : DataClient.OnDataChangedListener {
            override fun onDataChanged(events: DataEventBuffer) {
                for (event in events) {
                    if (event.type == DataEvent.TYPE_CHANGED &&
                        event.dataItem.uri.path == replyPath) {
                        updates.offer(event.dataItem.freeze())
                    }
                }
            }
        }
        val requestUri: android.net.Uri
        try {
            Tasks.await(client.addListener(listener))
            requestUri = Tasks.await(client.putDataItem(request.asPutDataRequest().setUrgent())).uri
        } catch (_: Exception) {
            client.removeListener(listener)
            throw PhoneRelayException("无法将请求发送到手机", true)
        }
        try {
            val deadline = System.currentTimeMillis() + timeoutMs
            var lastUpdate = 0L
            while (System.currentTimeMillis() < deadline) {
                val waitMs = (deadline - System.currentTimeMillis()).coerceAtLeast(1)
                val item = updates.poll(waitMs, TimeUnit.MILLISECONDS) ?: break
                val map = DataMapItem.fromDataItem(item).dataMap
                val stage = map.getString("stage") ?: continue
                val updated = map.getLong("updated")
                if (stage == "replying" && updated > lastUpdate) {
                    lastUpdate = updated
                    val partial = map.getString("answer") ?: readAsset(
                        map.getAsset("answerAsset"), 512 * 1024)?.toString(Charsets.UTF_8)
                    if (!partial.isNullOrEmpty()) onText(partial)
                }
                if (stage == "complete" || stage == "error") {
                    val result = PhoneRelayResult(
                        transcript = map.getString("transcript"),
                        answer = map.getString("answer") ?: readAsset(
                            map.getAsset("answerAsset"), 512 * 1024)?.toString(Charsets.UTF_8),
                        audio = readAsset(map.getAsset("audio"), 24 * 1024 * 1024),
                        audioFormat = map.getString("audioFormat"),
                    )
                    try { Tasks.await(client.deleteDataItems(item.uri)) } catch (_: Exception) { }
                    if (stage == "error") throw PhoneRelayException(
                        map.getString("error") ?: "手机请求失败",
                        map.getBoolean("networkFailure"),
                    )
                    return result
                }
            }
        } finally {
            client.removeListener(listener)
            try { Tasks.await(client.deleteDataItems(requestUri)) } catch (_: Exception) { }
        }
        // The phone may still be processing. Do not retry a billable request automatically.
        throw PhoneRelayException("手机请求状态不明，请稍后检查后重试", false)
    }

    private fun readAsset(asset: Asset?, maxBytes: Int): ByteArray? {
        if (asset == null) return null
        val stream = Tasks.await(client.getFdForAsset(asset)).inputStream ?: return null
        return stream.use { limitedBytes(it, maxBytes) }
    }

    private fun limitedBytes(input: InputStream, maxBytes: Int): ByteArray {
        val output = ByteArrayOutputStream()
        val chunk = ByteArray(8192)
        while (true) {
            val count = input.read(chunk)
            if (count < 0) break
            if (output.size() + count > maxBytes) {
                throw PhoneRelayException("手机返回内容过大", false)
            }
            output.write(chunk, 0, count)
        }
        return output.toByteArray()
    }
}
