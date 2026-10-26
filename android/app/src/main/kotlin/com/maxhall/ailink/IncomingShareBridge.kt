package com.maxhall.ailink

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** Copies URI grants immediately; Flutter only sees files owned by this inbox. */
class IncomingShareBridge(private val activity: MainActivity) {
    private var channel: MethodChannel? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val inbox get() = File(activity.filesDir, "share_inbox").apply { mkdirs() }

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "between_models/incoming_share")
        channel!!.setMethodCallHandler { call, result ->
            executor.execute {
                try {
                    val value: Any? = when (call.method) {
                        "peek" -> inbox.listFiles()?.filter { File(it, "ready.json").isFile }
                            ?.sortedBy { it.name }?.firstOrNull()?.let { dir ->
                                val json = JSONObject(File(dir, "ready.json").readText())
                                val files = json.getJSONArray("files")
                                mapOf("id" to dir.name, "error" to json.optString("error"),
                                    "files" to (0 until files.length()).map { index ->
                                        val item = files.getJSONObject(index)
                                        mapOf("path" to File(dir, item.getString("file")).path,
                                            "name" to item.getString("name"), "sharedText" to item.optBoolean("sharedText"))
                                    })
                            }
                        "clear" -> { check(inbox.deleteRecursively()); null }
                        "ack" -> {
                            val id = call.argument<String>("id") ?: ""
                            require(id.matches(Regex("[0-9]+-[a-f0-9-]{36}")))
                            check(File(inbox, id).deleteRecursively())
                            null
                        }
                        else -> { activity.runOnUiThread { result.notImplemented() }; return@execute }
                    }
                    activity.runOnUiThread { result.success(value) }
                } catch (_: Exception) {
                    activity.runOnUiThread { result.error("share_failed", "Share inbox unavailable", null) }
                }
            }
        }
    }

    fun close() { executor.shutdown() }

    @Suppress("DEPRECATION")
    fun receive(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND && intent?.action != Intent.ACTION_SEND_MULTIPLE) return
        // Activity recreation must not enqueue the same intent twice.
        if (intent.getBooleanExtra("ai_link_share_received", false)) return
        intent.putExtra("ai_link_share_received", true)
        val uris = linkedSetOf<Uri>()
        var text: String? = null
        var invalid = false
        try {
            if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.addAll(it) }
            } else intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.add(it) }
            intent.clipData?.let { clip ->
                for (index in 0 until clip.itemCount) clip.getItemAt(index).uri?.let { uris.add(it) }
            }
            text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.takeIf { it.isNotBlank() }
            if (text == null && uris.isEmpty()) {
                text = intent.clipData?.let { clip ->
                    (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).text?.toString() }
                        .joinToString("\n").takeIf { it.isNotBlank() }
                }
            }
        } catch (_: RuntimeException) { invalid = true }
        val sharedText = text
        executor.execute {
            var failedDirectory: File? = null
            try {
                val dir = File(inbox, "${System.currentTimeMillis()}-${UUID.randomUUID()}").apply { mkdirs() }
                failedDirectory = dir
                val files = JSONArray()
                val json = JSONObject().put("files", files)
                try {
                    require(!invalid)
                    require(uris.size + (if (sharedText == null) 0 else 1) in 1..9) { "count" }
                    var total = 0L
                    if (sharedText != null) {
                        val bytes = sharedText.toByteArray(Charsets.UTF_8)
                        require(bytes.size <= 1024 * 1024) { "size" }
                        File(dir, "text.txt").writeBytes(bytes)
                        files.put(JSONObject().put("file", "text.txt").put("name", "Shared text.txt").put("sharedText", true))
                        total += bytes.size
                    }
                    for ((index, uri) in uris.withIndex()) {
                        // Do not accept arbitrary file:// paths from another application.
                        require(uri.scheme == "content")
                        val name = activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                            if (it.moveToFirst()) it.getString(0) else null
                        } ?: "Shared file"
                        val file = File(dir, "file_$index")
                        var size = 0L
                        activity.contentResolver.openInputStream(uri)?.use { source ->
                            file.outputStream().use { output ->
                                val buffer = ByteArray(64 * 1024)
                                while (true) {
                                    val read = source.read(buffer)
                                    if (read < 0) break
                                    size += read
                                    total += read
                                    require(size <= 64L * 1024 * 1024 && total <= 90L * 1024 * 1024) { "size" }
                                    output.write(buffer, 0, read)
                                }
                            }
                        } ?: error("unreadable")
                        files.put(JSONObject().put("file", file.name).put("name", File(name).name))
                    }
                } catch (error: Exception) {
                    dir.listFiles()?.forEach { it.delete() }
                    json.put("files", JSONArray()).put("error", when (error.message) {
                        "size" -> "i18n.attachment_too_large"
                        "count" -> "i18n.attachment_count_limit"
                        else -> "i18n.share_import_failed"
                    })
                }
                File(dir, "ready.json").writeText(json.toString())
                activity.runOnUiThread { channel?.invokeMethod("changed", null) }
            } catch (_: Exception) {
                runCatching { failedDirectory?.deleteRecursively() }
                activity.runOnUiThread { channel?.invokeMethod("failed", null) }
            }
        }
    }
}
