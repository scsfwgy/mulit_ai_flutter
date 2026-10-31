package com.maxhall.ailink.wear

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.net.Uri
import android.view.GestureDetector
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
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
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
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject

class WatchActivity : Activity(), DataClient.OnDataChangedListener,
    MessageClient.OnMessageReceivedListener {
    private val executor = Executors.newSingleThreadExecutor()
    // Speech must never hold up a new recording's ASR/model request.
    private val speechExecutor = Executors.newCachedThreadPool()
    private var speechTask: Future<*>? = null
    @Volatile private var speechClient: WatchModelClient? = null
    private var speechGeneration = 0
    private var loadingAudio = false
    private var requestStage: String? = null
    private lateinit var speechIndicator: WatchSpeechIndicator
    // Wear OS requires a pure black background, including when system night mode is off.
    private val backgroundColor = Color.BLACK
    private val primaryColor = Color.WHITE
    private val secondaryColor = Color.rgb(146, 171, 198)
    private val mutedColor = Color.rgb(177, 191, 211)
    private val accentColor = Color.rgb(80, 165, 255)

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var status: TextView
    private lateinit var transcript: TextView
    private lateinit var answer: TextView
    private val markdown by lazy { WatchMarkdown(this, primaryColor, accentColor) }
    private lateinit var confirmation: TextView
    private lateinit var retry: TextView
    private lateinit var sound: TextView
    private lateinit var companion: TextView
    private lateinit var emptyChat: TextView
    private lateinit var history: LinearLayout
    private lateinit var historyScroll: ScrollView
    private lateinit var pages: FrameLayout
    private lateinit var settingsStatus: TextView
    private lateinit var configSummary: TextView
    private lateinit var serviceDetails: LinearLayout
    private lateinit var beginnerMode: TextView
    private lateinit var simpleMode: TextView
    private lateinit var speakSwitch: Switch
    private lateinit var recordingOverlay: WatchRecordingOverlay
    private val localizedLabels = mutableMapOf<TextView, String>()
    private var page = 0
    private var consumeDoubleTap = false
    private var pendingSettingsTap: MotionEvent? = null
    private var settingsTapConsumed = false
    private var holdingChat = false
    private var chatBusy = false
    private var showingGuide = false
    private lateinit var chatGestures: GestureDetector
    private var updatingSettings = false
    private var backCallback: OnBackInvokedCallback? = null
    private var phoneNodeId: String? = null
    private var companionWarning = false
    private val configStore by lazy { WatchConfigStore(this) }
    private val conversation by lazy { getSharedPreferences("watch_conversation", MODE_PRIVATE) }
    private val watchSettings by lazy { getSharedPreferences("watch_settings", MODE_PRIVATE) }
    private var phoneLanguage = "zh"
    @Volatile private var directBusy = false
    private var recorder: AudioRecord? = null
    private var recordingThread: Thread? = null
    @Volatile private var recording = false
    private var recordingStartedAtMs = 0L
    @Volatile private var requestId: String? = null
    private var pendingTranscript: String? = null
    private var awaitingConfirmation = false
    private var pressStartX = 0f
    private var pressStartY = 0f
    private var player: MediaPlayer? = null
    private var playingFile: File? = null
    private var lastAudioId: String? = null
    private val requestTimeout = Runnable {
        if (getPreferences(MODE_PRIVATE).getBoolean("pending", false)) {
            showError(watchText("等待手机超时，请重试"))
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        window.setBackgroundDrawable(ColorDrawable(Color.BLACK))
        window.decorView.setBackgroundColor(Color.BLACK)
        requestId = savedInstanceState?.getString("requestId")
            ?: getPreferences(MODE_PRIVATE).getString("requestId", null)
        lastAudioId = getPreferences(MODE_PRIVATE).getString("playedAudioId", null)
        phoneLanguage = watchSettings.getString("language", "zh") ?: "zh"
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
        showPage(savedInstanceState?.getInt("page") ?: 0)
        if (getPreferences(MODE_PRIVATE).getBoolean("pending", false)) {
            status.text = watchText("正在等待手机回复…")
            chatBusy = true
            setRequestStage("正在思考")
            val sentAt = getPreferences(MODE_PRIVATE).getLong("sentAt", 0)
            handler.postDelayed(
                requestTimeout,
                (250_000 - (System.currentTimeMillis() - sentAt)).coerceAtLeast(0),
            )
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("requestId", requestId)
        outState.putInt("page", page)
        super.onSaveInstanceState(outState)
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, grants: IntArray) {
        super.onRequestPermissionsResult(code, permissions, grants)
        if (code == 10 && grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            status.text = ""
        } else if (code == 10) {
            showError(watchText("需要麦克风权限才能录音"))
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
                        val issue = configStore.recordingIssue()
                        status.text = issue?.let(::watchText) ?: ""
                        settingsStatus.text = issue?.let(::watchText) ?: watchText("配置已同步，可以提问")
                        chatBusy = false
                        companion.visibility = if (phoneNodeId == null) View.GONE else View.VISIBLE
                        companion.text = watchText("同步手机配置")
                    }
                }
            } catch (_: Exception) {
                handler.post { status.text = watchText("配置同步失败，请在手机检查模型和语音服务") }
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
                    val ready = configStore.recordingIssue() == null
                    if (phone == null) {
                        phoneNodeId = nodes.firstOrNull()?.id
                        if (!ready) {
                            companionWarning = true
                            companion.visibility = View.VISIBLE
                            companion.text = if (phoneNodeId == null) watchText("重新检查连接") else watchText("在手机安装应用")
                            status.text = if (phoneNodeId == null)
                                watchText("尚未连接手机数据通道，请完成 Wear OS 配套应用设置") else watchText("请在手机安装应用并配置模型")
                            chatBusy = false
                        } else if (!directBusy && !recording) {
                            companion.visibility = View.GONE
                            status.text = watchText("手机未连接，可用手表 Wi-Fi 或蜂窝网络提问")
                            chatBusy = false
                        }
                    } else {
                        phoneNodeId = phone.id
                        companion.visibility = View.VISIBLE
                        companion.text = watchText("同步手机配置")
                        if (companionWarning && !recording && !directBusy &&
                            !getPreferences(MODE_PRIVATE).getBoolean("pending", false)) {
                            status.text = configStore.recordingIssue()?.let(::watchText) ?: ""
                            chatBusy = false
                        }
                        companionWarning = false
                    }
                    settingsStatus.text = if (phone == null) watchText("手机未连接") else watchText("手机已连接")
                }
            } catch (_: Exception) {
                handler.post {
                    companion.visibility = View.VISIBLE
                    companion.text = watchText("重新检查连接")
                    status.text = watchText("暂时无法检查手机连接")
                    settingsStatus.text = watchText("暂时无法检查手机连接")
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
        status.text = watchText("正在手机打开安装页…")
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
                    status.text = watchText("请在手机完成安装，再点下方检查")
                    companion.text = watchText("重新检查连接")
                    companion.isEnabled = true
                }
            } catch (_: Exception) {
                handler.post {
                    status.text = watchText("无法打开手机商店，请手动安装手机应用")
                    companion.text = watchText("重试打开安装页")
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
        executor.execute {
            try {
                val items = Tasks.await(Wearable.getDataClient(this).dataItems)
                try {
                    for (item in items) {
                        if (item.uri.path == "/between-models/preferences") {
                            val language = DataMapItem.fromDataItem(item).dataMap.getString("language")
                            handler.post { applyPhoneLanguage(language) }
                        } else if (item.uri.path == "/between-models/config-changed") {
                            requestConfiguration()
                        } else if (id != null && item.uri.path == "/between-models/reply/$id") {
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
        pendingSettingsTap?.recycle()
        pendingSettingsTap = null
        if (Build.VERSION.SDK_INT >= 33) {
            backCallback?.let { onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it) }
        }
        handler.removeCallbacks(requestTimeout)
        stopPlayback()
        executor.shutdown()
        speechExecutor.shutdownNow()
        super.onDestroy()
    }

    // API 33+ uses the OnBackInvokedCallback registered in onCreate; keep this for older watches.
    @SuppressLint("GestureBackNavigation")
    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (page == 1) showPage(0) else super.onBackPressed()
    }

    override fun onDataChanged(events: DataEventBuffer) {
        val id = requestId
        for (event in events) {
            if (event.type != DataEvent.TYPE_CHANGED) continue
            if (event.dataItem.uri.path == "/between-models/preferences") {
                val language = DataMapItem.fromDataItem(event.dataItem).dataMap.getString("language")
                handler.post { applyPhoneLanguage(language) }
            } else if (event.dataItem.uri.path == "/between-models/config-changed") {
                requestConfiguration()
            } else if (id != null &&
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
                if (!spoken.isNullOrEmpty()) transcript.text = "${watchText("我")}: $spoken"
                if (!spoken.isNullOrEmpty()) pendingTranscript = spoken
                if (!reply.isNullOrEmpty()) markdown.render(answer, reply)
                status.text = when (stage) {
                    "transcribing" -> watchText("正在识别语音…")
                    "transcribed", "thinking" -> watchText("模型正在思考…")
                    "awaiting_confirmation" -> watchText("请确认识别文字")
                    "replying" -> watchText("正在回答…")
                    "complete" -> ""
                    "error" -> watchText(error ?: "处理失败，请重试")
                    else -> watchText("正在处理…")
                }
                awaitingConfirmation = stage == "awaiting_confirmation"
                chatBusy = stage != "awaiting_confirmation" && stage != "complete" && stage != "error"
                setRequestStage(when (stage) {
                    "transcribing" -> "语音识别中"
                    "transcribed", "thinking" -> "正在思考"
                    "replying" -> "正在回答"
                    else -> null
                })
                setConfirmationVisible(awaitingConfirmation)
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
            handler.post { if (requestId == item.uri.lastPathSegment) showError(watchText("读取手机回复失败")) }
        }
    }

    private fun requireRecordingSetup(): Boolean {
        val issue = configStore.recordingIssue() ?: return true
        status.text = watchText(issue)
        AlertDialog.Builder(this)
            .setTitle(watchText("需要配置服务"))
            .setMessage(watchText(issue) + "\n" + watchText("在手机 AI Link 的设置中，进入模型设置添加文字服务，再进入语音服务添加并选择语音识别服务。完成后回到手表同步配置。"))
            .setPositiveButton(watchText("查看设置")) { _, _ -> showPage(1) }
            .setNegativeButton(watchText("知道了"), null)
            .show()
        requestConfiguration()
        return false
    }

    private fun startRecording() {
        if (recording) return
        stopPlayback()
        if (!requireRecordingSetup()) return
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 10)
            return
        }
        handler.removeCallbacks(requestTimeout)
        stopPlayback()
        awaitingConfirmation = false
        pendingTranscript = null
        setConfirmationVisible(false)
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
            showError(watchText("手表麦克风不可用"))
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
                showError(watchText("无法打开手表麦克风"))
                return
            }
            recorder = audio
            recording = true
            status.text = ""
            transcript.text = ""
            answer.text = ""
            chatBusy = false
            audio.startRecording()
            recordingStartedAtMs = SystemClock.elapsedRealtime()
            recordingOverlay.start()
            recordingThread = Thread {
                val samples = ByteArrayOutputStream()
                val buffer = ByteArray(4096)
                val started = System.currentTimeMillis()
                while (recording && System.currentTimeMillis() - started < 30_000) {
                    val count = audio.read(buffer, 0, buffer.size)
                    if (count > 0) {
                        samples.write(buffer, 0, count)
                        recordingOverlay.level = WatchRecordingOverlay.levelOf(buffer, count)
                    }
                }
                if (recording) handler.post { finishRecording() }
                synchronized(this) {
                    if (samples.size() > 0) pendingPcm = samples.toByteArray()
                }
            }.also { it.start() }
        } catch (_: Exception) {
            recording = false
            recordingOverlay.visibility = View.GONE
            recorder?.release()
            recorder = null
            showError(watchText("无法录音，请检查麦克风权限"))
        }
    }

    @Volatile private var pendingPcm: ByteArray? = null

    private fun finishRecording() {
        if (!recording) return
        val releaseAction = recordingOverlay.releaseAction
        if (releaseAction == WatchReleaseAction.CANCEL) {
            cancelRecording()
            return
        }
        val durationMs = SystemClock.elapsedRealtime() - recordingStartedAtMs
        recording = false
        recordingOverlay.visibility = View.GONE
        recorder?.stop()
        recordingThread?.join(1000)
        recorder?.release()
        recorder = null
        recordingThread = null
        val pcm = pendingPcm
        pendingPcm = null
        if (durationMs < 600) {
            resetForRecording()
            return
        }
        if (pcm == null || pcm.size < 3200) {
            showError(watchText("录音太短，请再试一次"))
            return
        }
        status.text = watchText("正在选择网络并识别语音…")
        historyScroll.post { historyScroll.fullScroll(View.FOCUS_UP) }
        chatBusy = true
        setRequestStage("语音识别中")
        val id = UUID.randomUUID().toString()
        requestId = id
        lastAudioId = null
        directBusy = true
        executor.execute {
            try {
                val config = configStore.load() ?: throw WatchNetworkException(watchText("请先从手机同步配置"))
                val recording = wav(pcm)
                val text = routed(
                    watchText("正在通过手机网络识别…"),
                    watchText("正在通过手表网络识别…"),
                    phone = { node -> WatchPhoneRelay(this, node).transcribe(recording) },
                    watch = { network -> WatchModelClient(config, network).transcribe(recording) },
                )
                handler.post {
                    if (requestId == id) {
                        transcript.text = "${watchText("我")}: $text"
                        pendingTranscript = text
                    }
                }
                if (releaseAction == WatchReleaseAction.REVIEW) {
                    directBusy = false
                    handler.post {
                        if (requestId == id) {
                            awaitingConfirmation = true
                            status.text = watchText("请确认识别文字")
                            chatBusy = false
                            setRequestStage(null)
                            setConfirmationVisible(true)
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
        val accidental = SystemClock.elapsedRealtime() - recordingStartedAtMs < 600
        recording = false
        recordingOverlay.visibility = View.GONE
        try { recorder?.stop() } catch (_: Exception) { }
        recordingThread?.join(1000)
        recorder?.release()
        recorder = null
        recordingThread = null
        pendingPcm = null
        if (::status.isInitialized) {
            status.text = if (accidental) "" else watchText("录音已取消")
        }
    }

    private fun confirmTranscript() {
        if (!requireRecordingSetup()) return
        val id = requestId ?: return
        val text = pendingTranscript ?: return
        val config = configStore.load() ?: run {
            showError(watchText("请先从手机同步配置"))
            return
        }
        awaitingConfirmation = false
        setConfirmationVisible(false)
        status.text = watchText("正在请求模型…")
        chatBusy = true
        setRequestStage("正在思考")
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
        handler.post { if (requestId == id) {
            status.text = watchText("正在请求模型…")
            setRequestStage("正在思考")
        } }
        var lastUpdate = 0L
        var receivedText = false
        val onText: (String) -> Unit = { current ->
            if (current.isNotEmpty()) receivedText = true
            val now = System.currentTimeMillis()
            if (now - lastUpdate >= 250) {
                lastUpdate = now
                handler.post { if (requestId == id) {
                    markdown.render(answer, current)
                    setRequestStage("正在回答")
                } }
            }
        }
        val reply = routed(
            watchText("正在通过手机网络请求模型…"),
            watchText("正在通过手表网络请求模型…"),
            phone = { node -> WatchPhoneRelay(this, node).reply(
                history.toString().toByteArray(Charsets.UTF_8),
                config.optInt("providerId"), config.optString("model"),
                config.optBoolean("searchEnabled", false), config.optJSONObject("search")?.optString("id"), onText) },
            watch = { network ->
                try {
                    WatchModelClient(config, network).reply(history, onText)
                } catch (error: IOException) {
                    if (receivedText) throw WatchNetworkException(
                        watchText("连接中断，已收到部分回答；为避免重复请求，请稍后手动重试"))
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
            .put("searchUsed", config.optBoolean("searchEnabled", false))
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
        handler.post {
            if (requestId == id) {
                directBusy = false
                renderHistory()
                transcript.text = ""
                answer.text = ""
                status.text = ""
                chatBusy = false
                setRequestStage(null)
                if (watchSettings.getBoolean("speak", config.optBoolean("speak", false)) &&
                    config.optJSONObject("tts") != null) startSpeech(id, readable(reply).take(1800), config)
            }
        }
    }

    private fun startSpeech(id: String, speech: String, config: JSONObject) {
        stopPlayback()
        val generation = speechGeneration
        loadingAudio = true
        updateActivityIndicator()
        sound.visibility = View.VISIBLE
        speechTask = speechExecutor.submit {
            try {
                val audio = routed(
                    watchText("正在通过手机网络生成语音…"),
                    watchText("正在通过手表网络生成语音…"),
                    phone = { node -> WatchPhoneRelay(this, node).speak(speech) },
                    watch = { network ->
                        val client = WatchModelClient(config, network)
                        speechClient = client
                        try { client.synthesize(speech) }
                        finally { if (speechClient === client) speechClient = null }
                    },
                    updateStatus = false,
                )
                handler.post {
                    if (requestId != id || generation != speechGeneration) return@post
                    if (audio != null && !recording) playAudio(audio.first, audio.second)
                    else stopPlayback()
                }
            } catch (_: Exception) {
                handler.post {
                    if (requestId == id && generation == speechGeneration) {
                        stopPlayback()
                        status.text = watchText("文字已保存，朗读失败")
                    }
                }
            }
        }
    }

    private fun routeError(error: Exception): String = when (error) {
        is WatchNetworkException, is PhoneRelayException -> watchText(error.message ?: "网络请求失败")
        is IOException -> watchText("网络连接失败，请检查手机或手表网络")
        else -> watchText("请求失败，请检查网络和服务配置")
    }

    private fun connectedPhone(): String? = try {
        val nodes = Tasks.await(Wearable.getNodeClient(this).connectedNodes)
        val installed = Tasks.await(Wearable.getCapabilityClient(this).getCapability(
            "between_models_phone_app", CapabilityClient.FILTER_REACHABLE,
        )).nodes.map { it.id }.toSet()
        nodes.firstOrNull { it.id in installed }?.id
    } catch (error: InterruptedException) {
        throw error
    } catch (_: Exception) { null }

    private fun <T> routed(
        phoneStatus: String,
        watchStatus: String,
        phone: (String) -> T,
        watch: (android.net.Network) -> T,
        updateStatus: Boolean = true,
    ): T {
        val id = requestId
        return WatchRouteExecutor().run(
            connectedPhone = connectedPhone(),
            reconnectPhone = ::connectedPhone,
            phone = phone,
            watch = { WatchNetworkSelector(this).use(watch) },
            onPhone = { fallback -> handler.post {
                if (updateStatus && requestId == id) {
                    status.text = if (fallback) watchText("手表网络失败，正在切换手机网络…") else phoneStatus
                }
            } },
            onWatch = { fallback -> handler.post {
                if (updateStatus && requestId == id) {
                    status.text = if (fallback) watchText("手机网络失败，正在切换手表网络…") else watchStatus
                }
            } },
        )
    }

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
        setConfirmationVisible(false)
        status.text = ""
        chatBusy = false
        setRequestStage(null)
    }

    private fun startNewTopic() {
        if (chatBusy || directBusy || recording) return
        stopPlayback()
        requestId = null
        getPreferences(MODE_PRIVATE).edit().remove("requestId").putBoolean("pending", false).apply()
        // Keep pendingTurns: the Data Layer will deliver the old topic to phone.
        conversation.edit().putString("turns", "[]")
            .putString("conversationId", UUID.randomUUID().toString())
            .putInt("sequence", 0).apply()
        transcript.text = ""
        answer.text = ""
        resetForRecording()
        renderHistory()
        syncPendingTurns()
        showPage(0)
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
                setOnCompletionListener { completed -> if (player === completed) stopPlayback() }
                setOnErrorListener { failed, _, _ ->
                    if (player === failed) stopPlayback()
                    true
                }
                setOnPreparedListener { prepared ->
                    if (player === prepared && !recording) {
                        prepared.start()
                        loadingAudio = false
                        updateActivityIndicator()
                    }
                }
                loadingAudio = true
                updateActivityIndicator()
                prepareAsync()
            }
            sound.visibility = View.VISIBLE
        } catch (_: Exception) {
            stopPlayback()
        }
    }

    private fun setRequestStage(stage: String?) {
        requestStage = stage
        status.visibility = if (stage != null || status.text.isEmpty()) View.GONE else View.VISIBLE
        updateActivityIndicator()
    }

    private fun updateActivityIndicator() {
        if (!::speechIndicator.isInitialized) return
        val stage = requestStage
        if (page != 0 || showingGuide || stage == null && !loadingAudio && player == null) {
            speechIndicator.visibility = View.GONE
            historyScroll.setPadding(0, 0, 0, 0)
            return
        }
        speechIndicator.show(loading = stage != null || loadingAudio,
            labelKey = stage ?: if (loadingAudio) "语音加载中" else "播放语音中")
        historyScroll.setPadding(0, (16 * resources.displayMetrics.density).toInt(), 0, 0)
    }

    private fun stopPlayback() {
        speechGeneration += 1
        speechTask?.cancel(true)
        speechTask = null
        speechClient?.cancel()
        speechClient = null
        loadingAudio = false
        try { player?.stop() } catch (_: Exception) { }
        player?.release()
        player = null
        playingFile?.delete()
        playingFile = null
        if (::sound.isInitialized) sound.visibility = View.GONE
        updateActivityIndicator()
    }

    private fun showError(message: String) {
        handler.removeCallbacks(requestTimeout)
        getPreferences(MODE_PRIVATE).edit().putBoolean("pending", false).apply()
        status.text = watchText(message)
        chatBusy = false
        setRequestStage(null)
        awaitingConfirmation = false
        setConfirmationVisible(false)
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (consumeDoubleTap) {
            chatGestures.onTouchEvent(event)
            if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL) {
                consumeDoubleTap = false
            }
            return true
        }
        if (showingGuide) return super.dispatchTouchEvent(event)
        if (event.actionMasked == MotionEvent.ACTION_DOWN) {
            pressStartX = event.rawX
            pressStartY = event.rawY
            holdingChat = false
            recordingOverlay.releaseAction = WatchReleaseAction.SEND
        }
        settingsTapConsumed = false
        chatGestures.onTouchEvent(event)
        if (consumeDoubleTap) {
            if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL) {
                consumeDoubleTap = false
            }
            return true
        }
        if (settingsTapConsumed) return true
        if (page != 0) {
            if (event.actionMasked == MotionEvent.ACTION_MOVE &&
                WatchSettingsGesture.shouldReturnToChat(
                    (event.rawX - pressStartX) / resources.displayMetrics.density,
                    (event.rawY - pressStartY) / resources.displayMetrics.density,
                )) {
                val cancel = MotionEvent.obtain(event).apply { action = MotionEvent.ACTION_CANCEL }
                super.dispatchTouchEvent(cancel)
                cancel.recycle()
                consumeDoubleTap = true
                showPage(0)
                return true
            }
            return super.dispatchTouchEvent(event)
        }
        if (holdingChat) {
            when (event.actionMasked) {
                MotionEvent.ACTION_MOVE -> {
                    recordingOverlay.releaseAction = WatchReleaseAction.fromDrag(
                        (event.rawX - pressStartX) / resources.displayMetrics.density,
                        (event.rawY - pressStartY) / resources.displayMetrics.density,
                    )
                }
                MotionEvent.ACTION_UP -> {
                    if (recording) {
                        recordingOverlay.releaseAction = WatchReleaseAction.fromDrag(
                            (event.rawX - pressStartX) / resources.displayMetrics.density,
                            (event.rawY - pressStartY) / resources.displayMetrics.density,
                        )
                        finishRecording()
                    }
                    holdingChat = false
                }
                MotionEvent.ACTION_CANCEL -> {
                    if (recording) cancelRecording()
                    holdingChat = false
                }
            }
            return true
        }
        return super.dispatchTouchEvent(event)
    }

    private fun showPage(index: Int) {
        pendingSettingsTap?.recycle()
        pendingSettingsTap = null
        if (index != 0 && recording) cancelRecording()
        page = index
        showingGuide = index == 0 && !watchSettings.getBoolean("gestureGuideSeen", false)
        pages.getChildAt(0).visibility = if (index == 0 && !showingGuide) View.VISIBLE else View.GONE
        pages.getChildAt(1).visibility = if (index == 1) View.VISIBLE else View.GONE
        pages.getChildAt(2).visibility = if (showingGuide) View.VISIBLE else View.GONE
        if (index == 1) refreshSettings()
        updateActivityIndicator()
    }

    private fun setConfirmationVisible(visible: Boolean) {
        confirmation.visibility = if (visible) View.VISIBLE else View.GONE
        retry.visibility = if (visible) View.VISIBLE else View.GONE
    }

    private fun refreshSettings() {
        val simple = watchSettings.getBoolean("simpleRecording", false)
        recordingOverlay.simpleMode = simple
        for ((button, selected) in listOf(beginnerMode to !simple, simpleMode to simple)) {
            button.isSelected = selected
            button.setTextColor(if (selected) Color.WHITE else secondaryColor)
            button.background = GradientDrawable().apply {
                cornerRadius = 10 * resources.displayMetrics.density
                setColor(if (selected) accentColor else Color.rgb(36, 40, 46))
            }
        }
        val config = configStore.load()
        configSummary.text = configStore.recordingIssue(config)?.let(::watchText) ?: ""
        configSummary.visibility = if (configSummary.text.isEmpty()) View.GONE else View.VISIBLE
        serviceDetails.removeAllViews()
        fun section(title: String, service: JSONObject?, modelKey: String, showVoice: Boolean = false, search: Boolean = false) {
            serviceDetails.addView(label(watchText(title), 13f, primaryColor, true).apply {
                gravity = Gravity.START
                setPadding(0, 10, 0, 5)
            })
            fun field(title: String, value: String?, fallback: String = "未配置") {
                serviceDetails.addView(label(watchText(title), 10f, secondaryColor).apply {
                    gravity = Gravity.START
                })
                serviceDetails.addView(label(value?.takeIf { it.isNotBlank() }
                    ?: watchText(fallback), 12f, primaryColor).apply {
                    gravity = Gravity.START
                    setPadding(0, 2, 0, 6)
                })
            }
            if (search) field("状态", if (config?.optBoolean("searchEnabled", false) == true) watchText("已开启") else watchText("已关闭"))
            field("提供商", service?.optString(if (search) "name" else "providerName"),
                if (service?.optString(modelKey)?.isNotBlank() == true) "同步后显示" else "未配置")
            field(if (search) "搜索服务" else "模型 ID", service?.optString(modelKey)?.let {
                if (search && it == "bocha") watchText("博查") else if (search && it == "tavily") "Tavily" else if (search && it == "exa") "Exa" else if (search && it == "deepseek") "DeepSeek" else it
            })
            if (showVoice) field("音色", service?.optString("voice"))
        }
        section("文本模型", config, "model")
        section("语音识别", config?.optJSONObject("asr"), "asrModel")
        section("语音朗读", config?.optJSONObject("tts"), "ttsModel", showVoice = true)
        section("联网搜索", config?.optJSONObject("search"), "service", search = true)
        updatingSettings = true
        speakSwitch.isChecked = watchSettings.getBoolean(
            "speak", config?.optBoolean("speak", false) ?: false)
        updatingSettings = false
    }

    private fun renderHistory() {
        history.removeAllViews()
        val turns = try {
            JSONArray(conversation.getString("turns", "[]"))
        } catch (_: Exception) { JSONArray() }
        for (index in turns.length() - 1 downTo 0) {
            val turn = turns.optJSONObject(index) ?: continue
            history.addView(label("${watchText("我")} · ${turn.optString("transcript")}",
                12f, secondaryColor).apply {
                gravity = Gravity.START
            })
            history.addView(label("", 15f, primaryColor).apply {
                gravity = Gravity.START
                setPadding(0, 4, 0, 18)
                markdown.render(this, turn.optString("answer"))
            })
        }
        updateEmptyChat()
        historyScroll.post { historyScroll.fullScroll(View.FOCUS_UP) }
    }

    private fun updateEmptyChat() {
        if (!::emptyChat.isInitialized || !::history.isInitialized || !::answer.isInitialized) return
        emptyChat.visibility = if (history.childCount == 0 && transcript.text.isEmpty() &&
            answer.text.isEmpty() && status.text.isEmpty()) View.VISIBLE else View.GONE
    }

    private fun buildScreen() {
        pages = FrameLayout(this).apply { setBackgroundColor(backgroundColor) }
        chatGestures = GestureDetector(this, object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(event: MotionEvent): Boolean = true

            override fun onSingleTapUp(event: MotionEvent): Boolean {
                if (page != 1) return false
                pendingSettingsTap?.recycle()
                pendingSettingsTap = MotionEvent.obtain(event)
                settingsTapConsumed = true
                return true
            }

            override fun onSingleTapConfirmed(event: MotionEvent): Boolean {
                // Wait for the double-tap decision before activating settings
                // controls, including the new-topic action and recording mode.
                val tap = pendingSettingsTap ?: return false
                pendingSettingsTap = null
                if (page == 1) super@WatchActivity.dispatchTouchEvent(tap)
                tap.recycle()
                return true
            }

            override fun onDoubleTap(event: MotionEvent): Boolean {
                consumeDoubleTap = true
                showPage(if (page == 0) 1 else 0)
                // Prevent the second tap from also activating a control below it.
                val cancel = MotionEvent.obtain(event).apply { action = MotionEvent.ACTION_CANCEL }
                super@WatchActivity.dispatchTouchEvent(cancel)
                cancel.recycle()
                return true
            }

            override fun onLongPress(event: MotionEvent) {
                if (chatBusy || directBusy || showingGuide || page != 0) return
                holdingChat = true
                val cancel = MotionEvent.obtain(event).apply { action = MotionEvent.ACTION_CANCEL }
                super@WatchActivity.dispatchTouchEvent(cancel)
                cancel.recycle()
                startRecording()
            }
        })
        historyScroll = ScrollView(this).apply {
            isFillViewport = true
            setBackgroundColor(backgroundColor)
            isVerticalScrollBarEnabled = true
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.TOP
            setBackgroundColor(backgroundColor)
            val density = resources.displayMetrics.density
            val round = resources.configuration.isScreenRound
            val horizontal = (if (round) 26 else 12) * density
            val top = (if (round) 40 else 20) * density
            val bottom = (if (round) 40 else 24) * density
            setPadding(horizontal.toInt(), top.toInt(), horizontal.toInt(), bottom.toInt())
        }
        status = label("", 12f, secondaryColor, hideWhenEmpty = true, suppressWhileProcessing = true)
        status.setPadding(0, 0, 0, 8)
        content.addView(status)
        transcript = label("", 12f, mutedColor, hideWhenEmpty = true).apply {
            gravity = Gravity.START
            setPadding(0, 0, 0, 5)
        }
        content.addView(transcript)
        answer = label("", 15f, primaryColor, hideWhenEmpty = true).apply {
            gravity = Gravity.START
            setPadding(0, 0, 0, 18)
        }
        content.addView(answer)
        confirmation = uiLabel("确认发送", 14f, Color.WHITE, true).apply {
            visibility = View.GONE
            setPadding(12, 10, 12, 10)
            background = GradientDrawable().apply {
                setColor(Color.rgb(24, 126, 240))
                cornerRadius = 40f
            }
            setOnClickListener { confirmTranscript() }
        }
        content.addView(confirmation)
        retry = uiLabel("重新录音", 12f, secondaryColor).apply {
            visibility = View.GONE
            setPadding(0, 8, 0, 12)
            setOnClickListener { resetForRecording() }
        }
        content.addView(retry)
        history = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        content.addView(history)
        emptyChat = uiLabel("还没有问答", 13f, secondaryColor).apply { gravity = Gravity.START }
        content.addView(emptyChat)
        historyScroll.addView(content)

        val settingsScroll = ScrollView(this).apply {
            visibility = View.GONE
            setBackgroundColor(backgroundColor)
        }
        val settingsPage = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(backgroundColor)
            setPadding(38, 30, 38, 48)
        }
        settingsPage.addView(uiLabel("设置", 18f, primaryColor, true))
        settingsPage.addView(uiLabel("双击或右滑返回聊天", 10f, secondaryColor).apply {
            setPadding(0, 6, 0, 4)
        })
        settingsStatus = label(watchText("正在检查手机连接…"), 12f, secondaryColor)
        settingsStatus.setPadding(0, 7, 0, 10)
        settingsPage.addView(settingsStatus)
        settingsPage.addView(uiLabel("开启新话题", 14f, accentColor, true).apply {
            setPadding(0, 8, 0, 8)
            setOnClickListener {
                if (chatBusy || directBusy || recording) {
                    settingsStatus.text = watchText("请等待当前回答完成")
                } else startNewTopic()
            }
        })
        settingsPage.addView(uiLabel("清空当前聊天；历史问答同步保存到手机，离线记录将在重连后同步。", 10f, secondaryColor).apply {
            setPadding(0, 0, 0, 12)
        })
        settingsPage.addView(uiLabel("录音界面", 12f, secondaryColor).apply {
            gravity = Gravity.START
            setPadding(0, 0, 0, 6)
        })
        val modes = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, 0, 0, 12)
        }
        fun mode(title: String, simple: Boolean) = uiLabel(title, 12f, primaryColor, true).apply {
            layoutParams = LinearLayout.LayoutParams(0, -2, 1f).apply {
                if (simple) leftMargin = (4 * resources.displayMetrics.density).toInt()
            }
            val padding = (10 * resources.displayMetrics.density).toInt()
            setPadding(0, padding, 0, padding)
            setOnClickListener {
                watchSettings.edit().putBoolean("simpleRecording", simple).apply()
                refreshSettings()
            }
        }
        beginnerMode = mode("新手模式", false)
        simpleMode = mode("简洁模式", true)
        modes.addView(beginnerMode)
        modes.addView(simpleMode)
        settingsPage.addView(modes)
        settingsPage.addView(uiLabel("新手：显示方向提示、波形和计时。\n简洁：仅显示语音图标和音量环。\n两种模式的录音手势相同。", 10f, secondaryColor).apply {
            gravity = Gravity.START
            setPadding(0, 0, 0, (12 * resources.displayMetrics.density).toInt())
        })
        configSummary = label(watchText("等待手机配置"), 12f, mutedColor)
        configSummary.setPadding(0, 0, 0, 8)
        settingsPage.addView(configSummary)
        serviceDetails = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            setPadding(0, 0, 0, 10)
        }
        settingsPage.addView(serviceDetails)
        speakSwitch = Switch(this).apply {
            text = watchText("自动播报回答")
            textSize = 13f
            setTextColor(primaryColor)
            setOnCheckedChangeListener { _, checked ->
                if (!updatingSettings) {
                    watchSettings.edit().putBoolean("speak", checked).apply()
                    if (!checked) stopPlayback()
                }
            }
        }
        settingsPage.addView(speakSwitch)
        companion = label(watchText("在手机安装应用"), 12f, accentColor, true).apply {
            setPadding(0, 12, 0, 8)
            setOnClickListener {
                when {
                    text == watchText("同步手机配置") -> {
                        settingsStatus.text = watchText("正在向手机请求最新配置…")
                        requestConfiguration()
                    }
                    phoneNodeId == null || text == watchText("重新检查连接") -> checkPhoneApp()
                    else -> openPhoneStore()
                }
            }
        }
        settingsPage.addView(companion)
        sound = uiLabel("停止播放", 12f, secondaryColor).apply {
            visibility = View.GONE
            setPadding(0, 8, 0, 0)
            setOnClickListener { stopPlayback() }
        }
        settingsPage.addView(sound)
        settingsPage.addView(uiLabel("模型、语音与联网服务在手机端设置", 11f, secondaryColor))
        settingsPage.addView(uiLabel("长按屏幕说话，松手发送；左上滑取消，右上滑转文字后确认。", 11f, secondaryColor))
        settingsPage.addView(uiLabel("双击切换聊天与设置，设置页右滑返回；上下滑动查看内容。", 11f, secondaryColor))
        settingsPage.addView(uiLabel("返回聊天", 13f, accentColor, true).apply {
            setPadding(0, 12, 0, 8)
            setOnClickListener { showPage(0) }
        })
        settingsScroll.addView(settingsPage)
        val guide = ScrollView(this).apply { setBackgroundColor(backgroundColor) }
        guide.addView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(backgroundColor)
            val density = resources.displayMetrics.density
            setPadding((26 * density).toInt(), (20 * density).toInt(), (26 * density).toInt(), (24 * density).toInt())
            addView(uiLabel("开始聊天", 18f, primaryColor, true))
            for (key in listOf("长按屏幕说话，松手发送；左上滑取消，右上滑转文字后确认。", "双击切换聊天与设置，设置页右滑返回；上下滑动查看内容。")) {
                addView(uiLabel(key, 13f, secondaryColor).apply { setPadding(0, 10, 0, 10) })
            }
            addView(uiLabel("知道了", 15f, accentColor, true).apply {
                setPadding(0, 12, 0, 12)
                setOnClickListener {
                    watchSettings.edit().putBoolean("gestureGuideSeen", true).apply()
                    showPage(0)
                }
            })
        })
        pages.addView(historyScroll)
        pages.addView(settingsScroll)
        pages.addView(guide)
        speechIndicator = WatchSpeechIndicator(this, { accentColor }, ::watchText)
        pages.addView(speechIndicator, FrameLayout.LayoutParams(-2,
            (28 * resources.displayMetrics.density).toInt(), Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply {
            topMargin = ((if (resources.configuration.isScreenRound) 16 else 4) * resources.displayMetrics.density).toInt()
        })
        recordingOverlay = WatchRecordingOverlay(this, ::watchText).apply {
            visibility = View.GONE
        }
        pages.addView(recordingOverlay, FrameLayout.LayoutParams(-1, -1))
        setContentView(pages)
    }

    private fun applyPhoneLanguage(language: String?) {
        if (language != "zh" && language != "en" || language == phoneLanguage) return
        phoneLanguage = language
        watchSettings.edit().putString("language", language).apply()
        for ((view, key) in localizedLabels) view.text = watchText(key)
        for (view in listOf(status, companion, settingsStatus)) {
            view.text = watchText(view.text.toString())
        }
        speakSwitch.text = watchText("自动播报回答")
        val scrollY = historyScroll.scrollY
        renderHistory()
        historyScroll.post { historyScroll.scrollTo(0, scrollY) }
        pendingTranscript?.let { transcript.text = "${watchText("我")}: $it" }
        refreshSettings()
        recordingOverlay.invalidate()
        speechIndicator.invalidate()
        speechIndicator.requestLayout()
    }

    private fun watchText(text: String): String = translateWatchText(text, phoneLanguage)

    private fun uiLabel(key: String, size: Float, color: Int, bold: Boolean = false) =
        label(watchText(key), size, color, bold).also { localizedLabels[it] = key }

    private fun label(text: String, size: Float, color: Int, bold: Boolean = false,
                      hideWhenEmpty: Boolean = false, suppressWhileProcessing: Boolean = false) =
        object : TextView(this) {
            override fun onTextChanged(text: CharSequence?, start: Int, before: Int, count: Int) {
                super.onTextChanged(text, start, before, count)
                if (hideWhenEmpty) {
                    visibility = if (text.isNullOrEmpty() || suppressWhileProcessing && requestStage != null) View.GONE else View.VISIBLE
                    updateEmptyChat()
                }
            }
        }.apply {
            this.text = text
            textSize = size
            setTextColor(color)
            gravity = Gravity.CENTER
            if (hideWhenEmpty && text.isEmpty()) visibility = View.GONE
            if (bold) setTypeface(null, Typeface.BOLD)
        }
}
