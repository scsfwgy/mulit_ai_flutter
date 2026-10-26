package com.maxhall.ailink

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.result.contract.ActivityResultContracts
import androidx.wear.remote.interactions.RemoteActivityHelper
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val incomingShares = IncomingShareBridge(this)

    override fun onCreate(savedInstanceState: Bundle?) {
        if (savedInstanceState?.getBoolean("ai_link_share_received") == true) {
            intent?.putExtra("ai_link_share_received", true)
        }
        super.onCreate(savedInstanceState)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean("ai_link_share_received", intent?.getBooleanExtra("ai_link_share_received", false) == true)
        super.onSaveInstanceState(outState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        incomingShares.receive(intent)
    }

    private val companionExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        incomingShares.attach(flutterEngine.dartExecutor.binaryMessenger)
        incomingShares.receive(intent)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "between_models/attachments")
            .setMethodCallHandler { call, result ->
                if (call.method == "supportsLimitedPhotoPicker") {
                    result.success(ActivityResultContracts.PickVisualMedia.isPhotoPickerAvailable(this))
                } else result.notImplemented()
            }
        WatchUpdateBridge.messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "between_models/watch_updates")
            .setMethodCallHandler { call, result ->
                if (call.method == "isProcessing") result.success(WatchUpdateBridge.processing)
                else result.notImplemented()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "between_models/companion_install")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "syncPreferences" -> {
                        val language = call.argument<String>("language")
                        if (language != "zh" && language != "en") {
                            result.error("invalid_language", "Unsupported language", null)
                        } else companionExecutor.execute {
                            try {
                                val request = PutDataMapRequest.create("/between-models/preferences")
                                request.dataMap.putString("language", language)
                                Tasks.await(Wearable.getDataClient(this).putDataItem(
                                    request.asPutDataRequest().setUrgent()), 15, TimeUnit.SECONDS)
                                runOnUiThread { result.success(null) }
                            } catch (_: Exception) {
                                runOnUiThread { result.error("sync_unavailable", "Watch preferences sync unavailable", null) }
                            }
                        }
                    }
                    "syncConfiguration" -> {
                        val config = call.argument<Map<String, Any?>>("configuration")
                        val bytes = config?.let { JSONObject(it).toString().toByteArray(Charsets.UTF_8) }
                        if (bytes == null || bytes.size > 60000 || config?.get("version") != 1) {
                            result.error("bad_config", "Invalid watch configuration", null)
                        } else companionExecutor.execute {
                            try {
                                // Persist only a change marker. Credentials use the paired message channel,
                                // and a reconnecting watch requests the latest snapshot from the phone.
                                val request = PutDataMapRequest.create("/between-models/config-changed")
                                request.dataMap.putLong("updated", System.currentTimeMillis())
                                Tasks.await(Wearable.getDataClient(this).putDataItem(
                                    request.asPutDataRequest().setUrgent()), 15, TimeUnit.SECONDS)
                                val nodes = Tasks.await(Wearable.getNodeClient(this).connectedNodes)
                                val installed = Tasks.await(Wearable.getCapabilityClient(this).getCapability(
                                    "between_models_watch_app", CapabilityClient.FILTER_REACHABLE)).nodes.map { it.id }.toSet()
                                for (node in nodes.filter { it.id in installed }) {
                                    Tasks.await(Wearable.getMessageClient(this).sendMessage(node.id, "/between-models/config", bytes))
                                }
                                runOnUiThread { result.success(null) }
                            } catch (_: Exception) {
                                runOnUiThread { result.error("sync_unavailable", "Watch configuration sync unavailable", null) }
                            }
                        }
                    }
                    "watchStatus" -> companionExecutor.execute {
                        try {
                            val nodes = Tasks.await(Wearable.getNodeClient(this).connectedNodes)
                            if (nodes.isEmpty()) {
                                runOnUiThread {
                                    result.success(mapOf(
                                        "connected" to 0,
                                        "installed" to 0,
                                        "missing" to emptyList<Map<String, String>>(),
                                    ))
                                }
                                return@execute
                            }
                            val installed = Tasks.await(
                                Wearable.getCapabilityClient(this).getCapability(
                                    "between_models_watch_app", CapabilityClient.FILTER_REACHABLE,
                                ),
                            ).nodes.map { it.id }.toSet()
                            val missing = nodes.filter { it.id !in installed }.map {
                                mapOf("id" to it.id, "name" to it.displayName)
                            }
                            runOnUiThread {
                                result.success(mapOf(
                                    "connected" to nodes.size,
                                    "installed" to nodes.count { it.id in installed },
                                    "missing" to missing,
                                ))
                            }
                        } catch (_: Exception) {
                            runOnUiThread { result.error("unavailable", "无法检查手表连接，请稍后重试", null) }
                        }
                    }
                    "openWatchStore" -> {
                        val nodeId = call.argument<String>("nodeId")
                        if (nodeId.isNullOrBlank()) {
                            result.error("invalid_node", "未选择手表", null)
                        } else companionExecutor.execute {
                            try {
                                val connected = Tasks.await(Wearable.getNodeClient(this).connectedNodes)
                                if (connected.none { it.id == nodeId }) {
                                    throw IllegalStateException("手表已断开连接")
                                }
                                val intent = Intent(Intent.ACTION_VIEW)
                                    .setData(Uri.parse("market://details?id=$packageName"))
                                    .addCategory(Intent.CATEGORY_BROWSABLE)
                                RemoteActivityHelper(this, { command -> runOnUiThread(command) })
                                    .startRemoteActivity(intent, nodeId)
                                    .get(20, TimeUnit.SECONDS)
                                runOnUiThread { result.success(null) }
                            } catch (_: Exception) {
                                runOnUiThread {
                                    result.error("store_unavailable", "无法在手表打开安装页，请检查连接或手动安装", null)
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "between_models/clipboard")
            .setMethodCallHandler { call, result ->
                if (call.method != "setHtml") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val plain = call.argument<String>("plain")
                val html = call.argument<String>("html")
                if (plain == null || html == null) {
                    result.error("invalid_arguments", "Missing clipboard content", null)
                    return@setMethodCallHandler
                }
                val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                clipboard.setPrimaryClip(ClipData.newHtmlText("Message", plain, html))
                result.success(null)
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (WatchUpdateBridge.messenger === flutterEngine.dartExecutor.binaryMessenger) {
            WatchUpdateBridge.messenger = null
        }
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        incomingShares.close()
        companionExecutor.shutdown()
        super.onDestroy()
    }
}
