package com.example.mulit_ai_flutter.wear

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Asset
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import java.util.concurrent.Executors

class WatchActivity : Activity(), DataClient.OnDataChangedListener {
    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var status: TextView
    private lateinit var transcript: TextView
    private lateinit var answer: TextView
    private lateinit var action: TextView
    private lateinit var retry: TextView
    private lateinit var sound: TextView
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
            status.text = "按住下方按钮开始说话"
        } else if (code == 10) {
            showError("需要麦克风权限才能录音")
        }
    }

    override fun onStart() {
        super.onStart()
        Wearable.getDataClient(this).addListener(this)
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
        if (recording) cancelRecording()
        super.onStop()
    }

    override fun onDestroy() {
        handler.removeCallbacks(requestTimeout)
        stopPlayback()
        executor.shutdown()
        super.onDestroy()
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
                    "complete" -> "回答完成"
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
        status.text = "正在发送到手机…"
        action.text = "请稍候"
        action.isEnabled = false
        val id = UUID.randomUUID().toString()
        requestId = id
        lastAudioId = null
        getPreferences(MODE_PRIVATE).edit().putString("requestId", id)
            .putBoolean("pending", true).putLong("sentAt", System.currentTimeMillis()).apply()
        handler.postDelayed(requestTimeout, 250_000)
        executor.execute {
            try {
                val nodes = Tasks.await(Wearable.getNodeClient(this).connectedNodes)
                if (nodes.isEmpty()) {
                    handler.post { showError("请连接已安装手机端的安卓手机") }
                    return@execute
                }
                val map = PutDataMapRequest.create("/between-models/request/$id")
                map.dataMap.putString("id", id)
                map.dataMap.putAsset("audio", Asset.createFromBytes(wav(pcm)))
                Tasks.await(Wearable.getDataClient(this).putDataItem(map.asPutDataRequest().setUrgent()))
                handler.post { if (requestId == id) status.text = "正在等待手机处理…" }
            } catch (_: Exception) {
                handler.post { if (requestId == id) showError("发送失败，请确认手机已连接") }
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
        awaitingConfirmation = false
        retry.visibility = View.GONE
        status.text = "正在发送文字…"
        action.text = "请稍候"
        action.isEnabled = false
        getPreferences(MODE_PRIVATE).edit().putBoolean("pending", true)
            .putLong("sentAt", System.currentTimeMillis()).apply()
        handler.postDelayed(requestTimeout, 250_000)
        executor.execute {
            try {
                val map = PutDataMapRequest.create("/between-models/confirm/$id")
                map.dataMap.putString("id", id)
                map.dataMap.putString("transcript", text)
                Tasks.await(Wearable.getDataClient(this).putDataItem(map.asPutDataRequest().setUrgent()))
            } catch (_: Exception) {
                handler.post { if (requestId == id) showError("发送失败，请确认手机已连接") }
            }
        }
    }

    private fun resetForRecording() {
        awaitingConfirmation = false
        pendingTranscript = null
        retry.visibility = View.GONE
        status.text = "按住下方按钮开始说话"
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

    private fun buildScreen() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(30, 28, 30, 54)
            setBackgroundColor(Color.rgb(9, 12, 19))
        }
        val scroll = ScrollView(this).apply { isFillViewport = true }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
        }
        val title = label("模型之间", 19f, Color.WHITE, true)
        content.addView(title)
        status = label("按住下方按钮开始说话", 13f, Color.rgb(146, 171, 198))
        content.addView(status)
        transcript = label("", 13f, Color.rgb(177, 191, 211))
        transcript.setPadding(0, 12, 0, 8)
        content.addView(transcript)
        answer = label("", 15f, Color.WHITE)
        answer.gravity = Gravity.START
        content.addView(answer, LinearLayout.LayoutParams(-1, -2))
        scroll.addView(content)
        root.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
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
        root.addView(action, LinearLayout.LayoutParams(
            (resources.displayMetrics.widthPixels * 0.66f).toInt(), -2,
        ))
        retry = label("重新录音", 12f, Color.rgb(146, 171, 198)).apply {
            visibility = View.GONE
            setPadding(0, 8, 0, 0)
            setOnClickListener { resetForRecording() }
        }
        root.addView(retry)
        sound = label("停止播放", 12f, Color.rgb(146, 171, 198)).apply {
            visibility = View.GONE
            setPadding(0, 8, 0, 0)
            setOnClickListener { stopPlayback() }
        }
        root.addView(sound)
        setContentView(root)
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
