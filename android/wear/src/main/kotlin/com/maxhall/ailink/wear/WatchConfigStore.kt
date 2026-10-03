package com.maxhall.ailink.wear

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** The watch keeps only the selected provider configuration, encrypted at rest. */
class WatchConfigStore(private val context: Context) {
    private val alias = "between_models_watch_config"
    private val prefs = context.getSharedPreferences("watch_config", Context.MODE_PRIVATE)

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build())
        return generator.generateKey()
    }

    fun save(payload: ByteArray) {
        require(payload.isNotEmpty() && payload.size <= 60000)
        val config = JSONObject(String(payload, Charsets.UTF_8))
        require(config.optInt("version") == 1)
        // Missing-service snapshots must replace stale credentials after phone changes.
        require(config.has("textReady") && config.has("asrReady") ||
            config.optString("apiKey").isNotBlank() && config.optString("model").isNotBlank())
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.doFinal(payload)
        prefs.edit()
            .putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .putString("data", Base64.encodeToString(encrypted, Base64.NO_WRAP))
            .apply()
    }

    fun recordingIssue(config: JSONObject? = load()): String? {
        val textReady = config != null && config.optBoolean("textReady", true) &&
            watchServiceReady(config.optString("baseUrl"), config.optString("apiKey"), config.optString("model"))
        val asr = config?.optJSONObject("asr")
        val asrReady = asr != null && config?.optBoolean("asrReady", true) != false &&
            watchServiceReady(asr.optString("baseUrl"), asr.optString("apiKey"), asr.optString("asrModel")) &&
            asr.optString("protocol") in setOf("openAi", "mimo", "doubao")
        return missingWatchServices(textReady, asrReady)
    }

    fun load(): JSONObject? {
        val iv = prefs.getString("iv", null) ?: return null
        val data = prefs.getString("data", null) ?: return null
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(),
                GCMParameterSpec(128, Base64.decode(iv, Base64.DEFAULT)))
            JSONObject(String(cipher.doFinal(Base64.decode(data, Base64.DEFAULT)), Charsets.UTF_8))
        } catch (_: Exception) {
            null
        }
    }
}
