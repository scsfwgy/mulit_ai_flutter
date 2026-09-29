package com.example.mulit_ai_flutter.wear

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.net.Uri
import android.text.TextUtils
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import androidx.wear.remote.interactions.RemoteActivityHelper
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Asset
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject

class WatchActivity : Activity(), DataClient.OnDataChangedListener,
    MessageClient.OnMessageReceivedListener {
    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var status: TextView
    private lateinit var transcript: TextView
    private lateinit var answer: TextView
    private lateinit var action: TextView
    private lateinit var retry: TextView
    private lateinit var sound: TextView
    private lateinit var companion: TextView
    private lateinit var history: LinearLayout
    private lateinit var historyHint: TextView
    private lateinit var historyScroll: ScrollView
    private lateinit var pages: FrameLayout
    private lateinit var settingsStatus: TextView
    private lateinit var configSummary: TextView
    private lateinit var autoSendSwitch: Switch
    private lateinit var speakSwitch: Switch
    private var page = 0
    private var swipeStartX = 0f
    private var swipeStartY = 0f
    private var updatingSettings = false
    private var backCallback: OnBackInvokedCallback? = null
    private var phoneNodeId: String? = null
    private var companionWarning = false
    private val configStore by lazy { WatchConfigStore(this) }
    private val conversation by lazy { getSharedPreferences("watch_conversation", MODE_PRIVATE) }
    private val watchSettings by lazy { getSharedPreferences("watch_settings", MODE_PRIVATE) }
    @Volatile private var directBusy = false
    private var recorder: AudioRecord? = null
    private var recordingThread: Thread? = null
    @Volatile private var recording = false
    private var requestId: String? = null
    private var pendingTranscript: String? = null
    private var awaitingConfirmation = false
    private var cancelOnRelease = false
    private var pressStartY = 0f
    private var player: MediaPlayer? = null
    private var playingFile: File? = null
    private var lastAudioId: String? = null
    private val requestTimeout = Runnable {
        if (getPreferences(MODE_PRIVATE).getBoolean("pending", false)) {
            showError("等待手机超时，请重试")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestId = savedInstanceState?.getString("requestId")
            ?: getPreferences(MODE_PRIVATE).getString("requestId", null)
        lastAudioId = getPreferences(MODE_PRIVATE).getString("playedAudioId", null)
        buildScreen()
        if (Build.VERSION.SDK_INT >= 33) {
            backCallback = OnBackInvokedCallback {
                if (page == 1) showPage(0) else finish()
            }.also {
                onBackInvokedDispatcher.registerOnBackInvokedCallback(
                    OnBackInvokedDispatcher.PRIORITY_DEFAULT, it)
            }
        }
        renderHistory()
        refreshSettings()
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            if (getPreferences(MODE_PRIVATE).getBoolean("pending", false)) {
                status.text = "正在等待手机回复…"
                action.text = "请稍候"
                action.isEnabled = false
                val sentAt = getPreferences(MODE_PRIVATE).getLong("sentAt", 0)
                handler.postDelayed(
                    requestTimeout,
                    (250_000 - (System.currentTimeMillis() - sentAt)).coerceAtLeast(0),
                )
            }
        } else {
            status.text = "请允许手表使用麦克风"
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 10)
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("requestId", requestId)
        super.onSaveInstanceState(outState)
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, grants: IntArray) {
        super.onRequestPermissionsResult(code, permissions, grants)
        if (code == 10 && grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            status.text = ""
        } else if (code == 10) {
            showError("需要麦克风权限才能录音")
        }
        if (code == 10) checkPhoneApp()
    }

    override fun onResume() {
        super.onResume()
        checkPhoneApp()
        requestConfiguration()
        syncPendingTurns()
    }

    private fun requestConfiguration() {
        executor.execute {
            try {
                val prefs = getPreferences(MODE_PRIVATE)
                val id = prefs.getString("configRequestId", null) ?: UUID.randomUUID().toString().also {
                    prefs.edit().putString("configRequestId", it).apply()
                }
                val request = PutDataMapRequest.create("/between-models/config-request/$id")
                request.dataMap.putLong("updated", System.currentTimeMillis())
                Tasks.await(Wearable.getDataClient(this).putDataItem(request.asPutDataRequest().setUrgent()))
            } catch (_: Exception) { /* Saved configuration remains usable offline. */ }
        }
    }

    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != "/between-models/config") return
        executor.execute {
            try {
                configStore.save(event.data)
                handler.post {
                    refreshSettings()
                    if (!directBusy && !recording) {
                        status.text = ""
                        settingsStatus.text = "配置已同步，可以提问"
                        action.text = "按住说话"
                        action.isEnabled = true
                        companion.visibility = if (phoneNodeId == null) View.GONE else View.VISIBLE
                        companion.text = "同步手机配置"
                    }
                }
            } catch (_: Exception) {
                handler.post { status.text = "配置同步失败，请在手机检查模型和语音服务" }
            }
        }
    }

    private fun checkPhoneApp() {
        executor.execute {
            try {
                val nodes = Tasks.await(Wearable.getNodeClient(this).connectedNodes)
                val installed = if (nodes.isEmpty()) emptySet<String>() else Tasks.await(
                    Wearable.getCapabilityClient(this).getCapability(
                        "between_models_phone_app", CapabilityClient.FILTER_REACHABLE,
                    ),
                ).nodes.map { it.id }.toSet()
                val phone = nodes.firstOrNull { it.id in installed }
                handler.post {
                    val ready = configStore.load() != null
                    if (phone == null) {
                        phoneNodeId = nodes.firstOrNull()?.id
                        if (!ready) {
                            companionWarning = true
                            companion.visibility = View.VISIBLE
                            companion.text = if (phoneNodeId == null) "重新检查连接" else "在手机安装应用"
                            status.text = if (phoneNodeId == null)
                                "尚未连接手机数据通道，请完成 Wear OS 配套应用设置" else "请在手机安装应用并配置模型"
                            action.isEnabled = false
                            action.text = "等待手机配置"
                        } else if (!directBusy && !recording) {
                            companion.visibility = View.GONE
                            status.text = "手机未连接，可用手表 Wi-Fi 或蜂窝网络提问"
                            action.isEnabled = true
                            action.text = "按住说话"
                        }
                    } else {
                        phoneNodeId = phone.id
                        companion.visibility = View.VISIBLE
                        companion.text = "同步手机配置"
                        if (companionWarning && !recording && !directBusy &&
                            !getPreferences(MODE_PRIVATE).getBoolean("pending", false)) {
                            status.text = if (ready) "" else "正在等待手机同步配置…"
                            action.text = "按住说话"
                            action.isEnabled = ready
                        }
                        companionWarning = false
                    }
                    settingsStatus.text = if (phone == null) "手机未连接" else "手机已连接"
                }
            } catch (_: Exception) {
                handler.post {
                    companion.visibility = View.VISIBLE
                    companion.text = "重新检查连接"
                    status.text = "暂时无法检查手机连接"
                    settingsStatus.text = "暂时无法检查手机连接"
                }
            }
        }
    }

    private fun openPhoneStore() {
        val nodeId = phoneNodeId ?: run {
            checkPhoneApp()
            return
        }
        companion.isEnabled = false
        status.text = "正在手机打开安装页…"
        executor.execute {
            try {
                val connected = Tasks.await(Wearable.getNodeClient(this).connectedNodes)
                if (connected.none { it.id == nodeId }) throw IllegalStateException("phone disconnected")
                val intent = Intent(Intent.ACTION_VIEW)
                    .setData(Uri.parse("market://details?id=$packageName"))
                    .addCategory(Intent.CATEGORY_BROWSABLE)
                RemoteActivityHelper(this, { command -> handler.post(command) })
                    .startRemoteActivity(intent, nodeId).get(20, TimeUnit.SECONDS)
                handler.post {
                    status.text = "请在手机完成安装，再点下方检查"
                    companion.text = "重新检查连接"
                    companion.isEnabled = true
                }
            } catch (_: Exception) {
                handler.post {
                    status.text = "无法打开手机商店，请手动安装手机应用"
                    companion.text = "重试打开安装页"
                    companion.isEnabled = true
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        Wearable.getDataClient(this).addListener(this)
        Wearable.getMessageClient(this).addListener(this)
        val id = requestId
        if (id == null) return
        executor.execute {
            try {
                val items = Tasks.await(Wearable.getDataClient(this).dataItems)
                try {
                    for (item in items) {
                        if (item.uri.path == "/between-models/reply/$id") {
                            renderResponse(item)
                        }
                    }
                } finally {
                    items.release()
                }
            } catch (_: Exception) { /* Current request remains visible. */ }
        }
    }

    override fun onStop() {
        Wearable.getDataClient(this).removeListener(this)
        Wearable.getMessageClient(this).removeListener(this)
        if (recording) cancelRecording()
        super.onStop()
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= 33) {
            backCallback?.let { onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it) }
        }
        handler.removeCallbacks(requestTimeout)
        stopPlayback()
        executor.shutdown()
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (page == 1) showPage(0) else super.onBackPressed()
    }

    override fun onDataChanged(events: DataEventBuffer) {
        val id = requestId ?: return
        for (event in events) {
            if (event.type == DataEvent.TYPE_CHANGED &&
                event.dataItem.uri.path == "/between-models/reply/$id") {
                val item = event.dataItem.freeze()
                executor.execute { renderResponse(item) }
            }
        }
    }

    private fun renderResponse(item: com.google.android.gms.wearable.DataItem) {
        try {
            val map = DataMapItem.fromDataItem(item).dataMap
            val id = map.getString("id") ?: return
            val stage = map.getString("stage") ?: return
            val spoken = map.getString("transcript")
            val reply = map.getString("answer")
            val error = map.getString("error")
            val asset = map.getAsset("audio")
            val audioBytes = if (asset != null && lastAudioId != id) {
                val stream = Tasks.await(Wearable.getDataClient(this).getFdForAsset(asset)).inputStream
                stream.use { it.readBytes() }
            } else null
            val format = map.getString("audioFormat") ?: "mp3"
            handler.post {
                if (requestId != id) return@post
                if (!spoken.isNullOrEmpty()) transcript.text = "我：$spoken"
                if (!spoken.isNullOrEmpty()) pendingTranscript = spoken
                if (!reply.isNullOrEmpty()) answer.text = reply
                status.text = when (stage) {
                    "transcribing" -> "正在识别语音…"
                    "transcribed", "thinking" -> "模型正在思考…"
                    "awaiting_confirmation" -> "请确认识别文字"
                    "replying" -> "正在回答…"
                    "complete" -> ""
                    "error" -> error ?: "处理失败，请重试"
                    else -> "正在处理…"
                }
                awaitingConfirmation = stage == "awaiting_confirmation"
                action.text = when (stage) {
                    "awaiting_confirmation" -> "确认发送"
                    "complete", "error" -> "按住再说"
                    else -> "请稍候"
                }
                action.isEnabled = stage == "awaiting_confirmation" || stage == "complete" || stage == "error"
                retry.visibility = if (awaitingConfirmation) View.VISIBLE else View.GONE
                if (stage == "complete" || stage == "error" || awaitingConfirmation) {
                    handler.removeCallbacks(requestTimeout)
                    getPreferences(MODE_PRIVATE).edit().putBoolean("pending", false).apply()
                }
                if (audioBytes != null && stage == "complete") {
                    lastAudioId = id
                    getPreferences(MODE_PRIVATE).edit().putString("playedAudioId", id).apply()
                    playAudio(audioBytes, format)
                }
            }
        } catch (_: Exception) {
            handler.post { if (requestId == item.uri.lastPathSegment) showError("读取手机回复失败") }
        }
    }

    private fun startRecording() {
        if (recording) return
        if (configStore.load() == null) {
            status.text = "先在手机完成模型与语音配置"
            requestConfiguration()
            return
        }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 10)
            return
        }
        handler.removeCallbacks(requestTimeout)
        stopPlayback()
        awaitingConfirmation = false
        pendingTranscript = null
        retry.visibility = View.GONE
        pendingPcm = null
        val previousId = requestId
        requestId = null
        getPreferences(MODE_PRIVATE).edit().putString("requestId", null)
            .putBoolean("pending", false).apply()
        if (previousId != null) executor.execute {
            try {
                val client = Wearable.getDataClient(this)
                val items = Tasks.await(client.dataItems)
                try {
                    for (item in items) {
                        if (item.uri.path == "/between-models/reply/$previousId") {
                            Tasks.await(client.deleteDataItems(item.uri))
                        }
                    }
                } finally {
                    items.release()
                }
            } catch (_: Exception) { /* The old reply is harmless if disconnected. */ }
        }
        val sampleRate = 16000
        val minimum = AudioRecord.getMinBufferSize(
            sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minimum <= 0) {
            showError("手表麦克风不可用")
            return
        }
        try {
            val audio = AudioRecord(
                MediaRecorder.AudioSource.MIC, sampleRate,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
                maxOf(minimum * 2, 4096),
            )
            if (audio.state != AudioRecord.STATE_INITIALIZED) {
                audio.release()
                showError("无法打开手表麦克风")
                return
            }
            recorder = audio
            recording = true
            status.text = "正在聆听…"
            transcript.text = "松开后转写语音"
            answer.text = ""
            action.text = "松开识别 · 上滑取消"
            action.isEnabled = true
            audio.startRecording()
            recordingThread = Thread {
                val samples = ByteArrayOutputStream()
                val buffer = ByteArray(4096)
                val started = System.currentTimeMillis()
                while (recording && System.currentTimeMillis() - started < 30_000) {
                    val count = audio.read(buffer, 0, buffer.size)
                    if (count > 0) samples.write(buffer, 0, count)
                }
                if (recording) handler.post { finishRecording() }
                synchronized(this) {
                    if (samples.size() > 0) pendingPcm = samples.toByteArray()
                }
            }.also { it.start() }
        } catch (_: Exception) {
            recording = false
            recorder?.release()
            recorder = null
            showError("无法录音，请检查麦克风权限")
        }
    }

    @Volatile private var pendingPcm: ByteArray? = null

    private fun finishRecording() {
        if (!recording) return
        recording = false
        recorder?.stop()
        recordingThread?.join(1000)
        recorder?.release()
        recorder = null
        recordingThread = null
        val pcm = pendingPcm
        pendingPcm = null
        if (pcm == null || pcm.size < 3200) {
            showError("录音太短，请再试一次")
            return
        }
        status.text = "正在选择网络并识别语音…"
        action.text = "请稍候"
        action.isEnabled = false
        val id = UUID.randomUUID().toString()
        requestId = id
        lastAudioId = null
        directBusy = true
        executor.execute {
            try {
                val config = configStore.load() ?: throw WatchNetworkException("请先从手机同步配置")
                val recording = wav(pcm)
                val text = routed(
                    "正在通过手机网络识别…",
                    "正在通过手表网络识别…",
                    phone = { node -> WatchPhoneRelay(this, node).transcribe(recording) },
                    watch = { network -> WatchModelClient(config, network).transcribe(recording) },
                )
                handler.post {
                    if (requestId == id) {
                        transcript.text = "我：$text"
                        pendingTranscript = text
                    }
                }
                if (!watchSettings.getBoolean("autoSend", config.optBoolean("autoSend", true))) {
                    directBusy = false
                    handler.post {
                        if (requestId == id) {
                            awaitingConfirmation = true
                            status.text = "请确认识别文字"
                            action.text = "确认发送"
                            action.isEnabled = true
                            retry.visibility = View.VISIBLE
                        }
                    }
                } else {
                    sendTextRouted(id, text, config)
                }
            } catch (error: Exception) {
                directBusy = false
                handler.post {
                    if (requestId == id) showError(
                        routeError(error))
                }
            }
        }
    }

    private fun cancelRecording() {
        recording = false
        try { recorder?.stop() } catch (_: Exception) { }
        recordingThread?.join(1000)
        recorder?.release()
        recorder = null
        recordingThread = null
        pendingPcm = null
        if (::status.isInitialized) {
            status.text = "录音已取消"
            action.text = "按住说话"
        }
    }

    private fun confirmTranscript() {
        val id = requestId ?: return
        val text = pendingTranscript ?: return
        val config = configStore.load() ?: run {
            showError("请先从手机同步配置")
            return
        }
        awaitingConfirmation = false
        retry.visibility = View.GONE
        status.text = "正在请求模型…"
        action.text = "请稍候"
        action.isEnabled = false
        directBusy = true
        executor.execute {
            try {
                sendTextRouted(id, text, config)
            } catch (error: Exception) {
                directBusy = false
                handler.post {
                    if (requestId == id) showError(
                        routeError(error))
                }
            }
        }
    }

    private fun sendTextRouted(id: String, text: String, config: JSONObject) {
        val fingerprint = "${config.optInt("providerId")}:${config.optString("model")}"
        val oldFingerprint = conversation.getString("fingerprint", null)
        val conversationId = if (oldFingerprint == fingerprint)
            conversation.getString("conversationId", null) ?: UUID.randomUUID().toString()
        else UUID.randomUUID().toString()
        val oldTurns = if (oldFingerprint == fingerprint)
            JSONArray(conversation.getString("turns", "[]")) else JSONArray()
        val sequence = if (oldFingerprint == fingerprint) conversation.getInt("sequence", 0) else 0
        val history = JSONArray()
        val start = (oldTurns.length() - 12).coerceAtLeast(0)
        for (index in start until oldTurns.length()) {
            val turn = oldTurns.getJSONObject(index)
            history.put(JSONObject().put("role", "user").put("content", turn.getString("transcript")))
            history.put(JSONObject().put("role", "assistant").put("content", turn.getString("answer")))
        }
        history.put(JSONObject().put("role", "user").put("content", text))
        handler.post { if (requestId == id) status.text = "模型正在回答…" }
        var lastUpdate = 0L
        var receivedText = false
        val onText: (String) -> Unit = { current ->
            if (current.isNotEmpty()) receivedText = true
            val now = System.currentTimeMillis()
            if (now - lastUpdate >= 250) {
                lastUpdate = now
                handler.post { if (requestId == id) answer.text = readable(current) }
            }
        }
        val reply = routed(
            "正在通过手机网络请求模型…",
            "正在通过手表网络请求模型…",
            phone = { node -> WatchPhoneRelay(this, node).reply(
                history.toString().toByteArray(Charsets.UTF_8),
                config.optInt("providerId"), config.optString("model"), onText) },
            watch = { network ->
                try {
                    WatchModelClient(config, network).reply(history, onText)
                } catch (error: IOException) {
                    if (receivedText) throw WatchNetworkException(
                        "连接中断，已收到部分回答；为避免重复请求，请稍后手动重试")
                    throw error
                }
            },
        )
        val turn = JSONObject()
            .put("id", id)
            .put("conversationId", conversationId)
            .put("sequence", sequence)
            .put("createdAt", System.currentTimeMillis())
            .put("providerId", config.optInt("providerId"))
            .put("providerName", config.optString("providerName"))
            .put("providerPresetId", config.optString("providerPresetId"))
            .put("model", config.optString("model"))
            .put("transcript", text)
            .put("answer", reply)
        val recent = JSONArray()
        for (index in (oldTurns.length() - 49).coerceAtLeast(0) until oldTurns.length()) {
            recent.put(oldTurns.getJSONObject(index))
        }
        recent.put(turn)
        conversation.edit().putString("fingerprint", fingerprint)
            .putString("conversationId", conversationId)
            .putInt("sequence", sequence + 1)
            .putString("turns", recent.toString()).apply()
        try {
            queueTurn(turn)
        } catch (_: Exception) {
            // The answer is already saved locally. Retry history sync on next resume.
        }
        directBusy = false
        handler.post {
            if (requestId == id) {
                renderHistory()
                transcript.text = ""
                answer.text = ""
                status.text = ""
                action.text = "按住再说"
                action.isEnabled = true
            }
        }
        if (watchSettings.getBoolean("speak", config.optBoolean("speak", false))) {
            try {
                val speech = readable(reply).take(1800)
                val audio = routed(
                    "正在通过手机网络生成语音…",
                    "正在通过手表网络生成语音…",
                    phone = { node -> WatchPhoneRelay(this, node).speak(speech) },
                    watch = { network -> WatchModelClient(config, network).synthesize(speech) },
                )
                if (audio != null) handler.post {
                    if (requestId == id) playAudio(audio.first, audio.second)
                }
            } catch (_: Exception) { /* Text remains available if speech fails. */ }
        }
    }

    private fun routeError(error: Exception): String = when (error) {
        is WatchNetworkException, is PhoneRelayException -> error.message ?: "网络请求失败"
        is IOException -> "网络连接失败，请检查手机或手表网络"
        else -> "请求失败，请检查网络和服务配置"
    }

    private fun connectedPhone(): String? = try {
        val nodes = Tasks.await(Wearable.getNodeClient(this).connectedNodes)
        val installed = Tasks.await(Wearable.getCapabilityClient(this).getCapability(
            "between_models_phone_app", CapabilityClient.FILTER_REACHABLE,
        )).nodes.map { it.id }.toSet()
        nodes.firstOrNull { it.id in installed }?.id
    } catch (_: Exception) { null }

    private fun <T> routed(
        phoneStatus: String,
        watchStatus: String,
        phone: (String) -> T,
        watch: (android.net.Network) -> T,
    ): T = WatchRouteExecutor().run(
        connectedPhone = connectedPhone(),
        reconnectPhone = ::connectedPhone,
        phone = phone,
        watch = { WatchNetworkSelector(this).use(watch) },
        onPhone = { fallback -> handler.post {
            status.text = if (fallback) "手表网络失败，正在切换手机网络…" else phoneStatus
        } },
        onWatch = { fallback -> handler.post {
            status.text = if (fallback) "手机网络失败，正在切换手表网络…" else watchStatus
        } },
    )

    private fun readable(source: String): String = source
        .replace(Regex("\\[([^]]+)]\\([^)]+\\)"), "$1")
        .replace(Regex("[*_`#>]"), "")
        .trim()

    private fun queueTurn(turn: JSONObject) {
        val pending = JSONArray(conversation.getString("pendingTurns", "[]"))
        pending.put(turn)
        conversation.edit().putString("pendingTurns", pending.toString()).apply()
        flushPendingTurns()
    }

    private fun syncPendingTurns() {
        executor.execute { flushPendingTurns() }
    }

    private fun flushPendingTurns() {
        val pending = JSONArray(conversation.getString("pendingTurns", "[]"))
        val remaining = JSONArray()
        for (index in 0 until pending.length()) {
            val turn = pending.getJSONObject(index)
            try {
                val map = PutDataMapRequest.create("/between-models/turn/${turn.getString("id")}")
                map.dataMap.putAsset("turn", Asset.createFromBytes(
                    turn.toString().toByteArray(Charsets.UTF_8)))
                Tasks.await(Wearable.getDataClient(this)
                    .putDataItem(map.asPutDataRequest().setUrgent()))
            } catch (_: Exception) {
                remaining.put(turn)
            }
        }
        conversation.edit().putString("pendingTurns", remaining.toString()).apply()
    }

    private fun resetForRecording() {
        awaitingConfirmation = false
        pendingTranscript = null
        retry.visibility = View.GONE
        status.text = ""
        action.text = "按住说话"
        action.isEnabled = true
    }

    private fun wav(pcm: ByteArray): ByteArray {
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray())
        header.putInt(pcm.size + 36)
        header.put("WAVEfmt ".toByteArray())
        header.putInt(16)
        header.putShort(1)
        header.putShort(1)
        header.putInt(16000)
        header.putInt(32000)
        header.putShort(2)
        header.putShort(16)
        header.put("data".toByteArray())
        header.putInt(pcm.size)
        return header.array() + pcm
    }

    private fun playAudio(bytes: ByteArray, format: String) {
        stopPlayback()
        try {
            val file = File.createTempFile("watch_reply_", ".$format", cacheDir)
            file.writeBytes(bytes)
            playingFile = file
            player = MediaPlayer().apply {
                setDataSource(file.absolutePath)
                setOnCompletionListener { stopPlayback() }
                prepare()
                start()
            }
            sound.visibility = View.VISIBLE
        } catch (_: Exception) {
            stopPlayback()
        }
    }

    private fun stopPlayback() {
        try { player?.stop() } catch (_: Exception) { }
        player?.release()
        player = null
        playingFile?.delete()
        playingFile = null
        if (::sound.isInitialized) sound.visibility = View.GONE
    }

    private fun showError(message: String) {
        handler.removeCallbacks(requestTimeout)
        getPreferences(MODE_PRIVATE).edit().putBoolean("pending", false).apply()
        status.text = message
        action.text = "按住重试"
        action.isEnabled = true
        awaitingConfirmation = false
        retry.visibility = View.GONE
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                swipeStartX = event.rawX
                swipeStartY = event.rawY
            }
            MotionEvent.ACTION_UP -> {
                val dx = event.rawX - swipeStartX
                val dy = event.rawY - swipeStartY
                val threshold = 55 * resources.displayMetrics.density
                if (!recording && kotlin.math.abs(dx) > threshold &&
                    kotlin.math.abs(dx) > kotlin.math.abs(dy) * 1.3f) {
                    val next = if (dx < 0) 1 else 0
                    if (next != page) {
                        showPage(next)
                        return true
                    }
                }
            }
        }
        return super.dispatchTouchEvent(event)
    }

    private fun showPage(index: Int) {
        page = index
        pages.getChildAt(0).visibility = if (index == 0) View.VISIBLE else View.GONE
        pages.getChildAt(1).visibility = if (index == 1) View.VISIBLE else View.GONE
        if (index == 0) historyScroll.post { historyScroll.fullScroll(View.FOCUS_UP) }
        else refreshSettings()
    }

    private fun refreshSettings() {
        val config = configStore.load()
        configSummary.text = if (config == null) "等待手机配置"
            else "${config.optString("providerName")} · ${config.optString("model")}"
        updatingSettings = true
        autoSendSwitch.isChecked = watchSettings.getBoolean(
            "autoSend", config?.optBoolean("autoSend", true) ?: true)
        speakSwitch.isChecked = watchSettings.getBoolean(
            "speak", config?.optBoolean("speak", false) ?: false)
        updatingSettings = false
    }

    private fun renderHistory() {
        history.removeAllViews()
        val turns = try {
            JSONArray(conversation.getString("turns", "[]"))
        } catch (_: Exception) { JSONArray() }
        if (turns.length() == 0) {
            history.addView(label("还没有问答", 13f, Color.rgb(146, 171, 198)))
        } else {
            for (index in turns.length() - 1 downTo 0) {
                val turn = turns.optJSONObject(index) ?: continue
                val latest = index == turns.length() - 1
                val question = label(
                    if (latest) "我 · ${turn.optString("transcript")}"
                    else "${turn.optString("transcript")} → ${readable(turn.optString("answer"))}",
                    12f, Color.rgb(146, 171, 198),
                ).apply {
                    gravity = Gravity.START
                    if (!latest) {
                        isSingleLine = true
                        ellipsize = TextUtils.TruncateAt.END
                    }
                }
                val response = label(
                    readable(turn.optString("answer")), 15f, Color.WHITE,
                ).apply {
                    gravity = Gravity.START
                    setPadding(0, 4, 0, if (latest) 40 else 14)
                    if (!latest) visibility = View.GONE
                }
                if (!latest) question.setOnClickListener {
                    response.visibility = if (response.visibility == View.VISIBLE) View.GONE else View.VISIBLE
                }
                history.addView(question)
                history.addView(response)
            }
        }
        historyHint.visibility = if (turns.length() > 1) View.VISIBLE else View.GONE
        historyScroll.post { historyScroll.fullScroll(View.FOCUS_UP) }
    }

    private fun buildScreen() {
        pages = FrameLayout(this)
        val chatPage = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(34, 27, 34, 49)
            setBackgroundColor(Color.rgb(9, 12, 19))
        }
        chatPage.addView(label("最近问答  ›", 15f, Color.WHITE, true).apply {
            setOnClickListener { showPage(1) }
        })
        status = label("", 12f, Color.rgb(146, 171, 198))
        status.setPadding(0, 4, 0, 4)
        chatPage.addView(status)
        historyScroll = ScrollView(this).apply { isFillViewport = true }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.TOP
        }
        transcript = label("", 13f, Color.rgb(177, 191, 211))
        transcript.gravity = Gravity.START
        transcript.setPadding(0, 6, 0, 5)
        content.addView(transcript)
        answer = label("", 15f, Color.WHITE)
        answer.gravity = Gravity.START
        content.addView(answer, LinearLayout.LayoutParams(-1, -2))
        history = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        content.addView(history)
        historyScroll.addView(content)
        chatPage.addView(historyScroll, LinearLayout.LayoutParams(-1, 0, 1f))
        historyHint = label("上滑查看更早问答", 11f, Color.rgb(146, 171, 198)).apply {
            visibility = View.GONE
            setPadding(0, 0, 0, 7)
        }
        chatPage.addView(historyHint)
        action = label("按住说话", 16f, Color.WHITE, true).apply {
            gravity = Gravity.CENTER
            setPadding(16, 12, 16, 12)
            background = GradientDrawable().apply {
                setColor(Color.rgb(24, 126, 240))
                cornerRadius = 40f
            }
            setOnTouchListener { _, event ->
                if (!isEnabled) return@setOnTouchListener true
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        pressStartY = event.rawY
                        cancelOnRelease = false
                        if (!awaitingConfirmation) startRecording()
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        if (recording) {
                            val cancel = event.rawY < pressStartY - 65 * resources.displayMetrics.density
                            if (cancel != cancelOnRelease) {
                                cancelOnRelease = cancel
                                status.text = if (cancel) "松开取消录音" else "正在聆听…"
                            }
                        }
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (awaitingConfirmation) confirmTranscript()
                        else if (recording) {
                            if (cancelOnRelease) cancelRecording() else finishRecording()
                        }
                        true
                    }
                    MotionEvent.ACTION_CANCEL -> {
                        if (recording) cancelRecording()
                        true
                    }
                    else -> true
                }
            }
        }
        chatPage.addView(action, LinearLayout.LayoutParams(
            (resources.displayMetrics.widthPixels * 0.66f).toInt(), -2,
        ))
        retry = label("重新录音", 12f, Color.rgb(146, 171, 198)).apply {
            visibility = View.GONE
            setPadding(0, 8, 0, 0)
            setOnClickListener { resetForRecording() }
        }
        chatPage.addView(retry)

        val settingsScroll = ScrollView(this).apply {
            visibility = View.GONE
            setBackgroundColor(Color.rgb(9, 12, 19))
        }
        val settingsPage = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(38, 30, 38, 48)
        }
        settingsPage.addView(label("‹  设置", 18f, Color.WHITE, true).apply {
            setOnClickListener { showPage(0) }
        })
        settingsStatus = label("正在检查手机连接…", 12f, Color.rgb(146, 171, 198))
        settingsStatus.setPadding(0, 7, 0, 10)
        settingsPage.addView(settingsStatus)
        configSummary = label("等待手机配置", 12f, Color.rgb(177, 191, 211))
        configSummary.setPadding(0, 0, 0, 8)
        settingsPage.addView(configSummary)
        autoSendSwitch = Switch(this).apply {
            text = "识别后自动发送"
            textSize = 13f
            setTextColor(Color.WHITE)
            setOnCheckedChangeListener { _, checked ->
                if (!updatingSettings) watchSettings.edit().putBoolean("autoSend", checked).apply()
            }
        }
        settingsPage.addView(autoSendSwitch)
        speakSwitch = Switch(this).apply {
            text = "自动播报回答"
            textSize = 13f
            setTextColor(Color.WHITE)
            setOnCheckedChangeListener { _, checked ->
                if (!updatingSettings) watchSettings.edit().putBoolean("speak", checked).apply()
            }
        }
        settingsPage.addView(speakSwitch)
        companion = label("在手机安装应用", 12f, Color.rgb(80, 165, 255), true).apply {
            setPadding(0, 12, 0, 8)
            setOnClickListener {
                when {
                    text == "同步手机配置" -> {
                        settingsStatus.text = "正在向手机请求最新配置…"
                        requestConfiguration()
                    }
                    phoneNodeId == null || text == "重新检查连接" -> checkPhoneApp()
                    else -> openPhoneStore()
                }
            }
        }
        settingsPage.addView(companion)
        sound = label("停止播放", 12f, Color.rgb(146, 171, 198)).apply {
            visibility = View.GONE
            setPadding(0, 8, 0, 0)
            setOnClickListener { stopPlayback() }
        }
        settingsPage.addView(sound)
        settingsPage.addView(label("模型与语音服务在手机端设置", 11f, Color.rgb(146, 171, 198)))
        settingsScroll.addView(settingsPage)
        pages.addView(chatPage)
        pages.addView(settingsScroll)
        setContentView(pages)
    }

    private fun label(text: String, size: Float, color: Int, bold: Boolean = false) =
        TextView(this).apply {
            this.text = text
            textSize = size
            setTextColor(color)
            gravity = Gravity.CENTER
            if (bold) setTypeface(null, Typeface.BOLD)
        }
}
