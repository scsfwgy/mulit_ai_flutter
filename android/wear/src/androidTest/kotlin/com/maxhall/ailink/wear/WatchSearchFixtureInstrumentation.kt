package com.maxhall.ailink.wear

import android.app.Instrumentation
import android.os.Bundle
import org.json.JSONObject

/** Run only on an empty Debug sandbox; seeds fake settings for rendered QA. */
class WatchSearchFixtureInstrumentation : Instrumentation() {
    override fun onCreate(arguments: Bundle?) { super.onCreate(arguments); start() }
    override fun onStart() {
        val result = Bundle()
        try {
            check(targetContext.packageName.endsWith(".debug"))
            val store = WatchConfigStore(targetContext)
            check(!targetContext.getSharedPreferences("watch_config", 0).contains("data") && store.load() == null) {
                "Use a fresh QA emulator; existing settings are protected"
            }
            val config = JSONObject("""{"version":1,"providerId":7,"providerName":"QA Text","model":"qa-chat",
                "protocol":"openai_chat","baseUrl":"https://example.com/v1","apiKey":"fake-text-key",
                "textReady":true,"asrReady":true,"speak":false,"searchEnabled":true,"searchReady":true,
                "asr":{"providerName":"QA Voice","protocol":"openAi","baseUrl":"https://example.com/v1",
                "apiKey":"fake-voice-key","asrModel":"qa-asr","ttsModel":"qa-tts","voice":"qa-voice"},
                "tts":{"providerName":"QA Voice","protocol":"openAi","baseUrl":"https://example.com/v1",
                "apiKey":"fake-voice-key","asrModel":"qa-asr","ttsModel":"qa-tts","voice":"qa-voice"},
                "search":{"id":"qa-search","name":"QA Tavily","service":"tavily","endpoint":"https://api.tavily.com/search",
                "apiKey":"fake-search-key","maxResults":5,"detailed":false,"timeRange":"any"}}""")
            store.save(config.toString().toByteArray())
            check(store.load()?.getJSONObject("search")?.getString("apiKey") == "fake-search-key")
            check(!targetContext.getSharedPreferences("watch_config", 0).all.toString().contains("fake-search-key"))
            config.put("searchEnabled", false).put("search", JSONObject.NULL)
            store.save(config.toString().toByteArray())
            check(store.load()?.optBoolean("searchEnabled") == false)
            check(store.load()?.optJSONObject("search") == null)
            config.put("searchEnabled", true).put("search", JSONObject("""{"id":"qa-exa","name":"QA Exa","service":"exa",
                "endpoint":"https://api.exa.ai/search","apiKey":"fake-exa-key","maxResults":3,"detailed":true,"timeRange":"week"}"""))
            store.save(config.toString().toByteArray())
            check(store.load()?.getJSONObject("search")?.getString("name") == "QA Exa")
            check(!store.load().toString().contains("fake-search-key"))
            targetContext.getSharedPreferences("watch_settings", 0).edit().putBoolean("gestureGuideSeen", true).apply()
            result.putString("result", "PASS: encrypted settings, off/revocation and provider replacement; fake Exa fixture ready")
            finish(-1, result)
        } catch (error: Throwable) {
            result.putString("result", "FAIL: ${error.javaClass.simpleName}")
            finish(0, result)
        }
    }
}
