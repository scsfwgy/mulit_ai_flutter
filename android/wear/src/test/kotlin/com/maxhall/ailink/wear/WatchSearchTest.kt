package com.maxhall.ailink.wear

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WatchSearchTest {
    private fun config(service: String) = JSONObject().put("service", service).put("endpoint", "https://example.com/search")
        .put("apiKey", "fake-search-key").put("maxResults", 3).put("detailed", true).put("timeRange", "week")

    @Test fun presetsSendBoundedQueriesAndDoNotExposeKeysInEvidence() {
        for (service in listOf("bocha", "tavily", "exa")) {
            var calls = 0
            val evidence = WatchSearch.evidence(config(service), "👋".repeat(1001)) { _, key, actual, body ->
                calls++
                assertEquals("fake-search-key", key)
                assertEquals(service, actual)
                assertEquals("👋".repeat(1000), body.getString("query"))
                when (service) {
                    "bocha" -> { assertEquals(3, body.getInt("count")); assertEquals("oneWeek", body.getString("freshness")) }
                    "tavily" -> { assertEquals("advanced", body.getString("search_depth")); assertEquals("week", body.getString("time_range")) }
                    "exa" -> { assertEquals("auto", body.getString("type")); assertTrue(body.has("startPublishedDate")) }
                }
                (if (service == "bocha") """{"code":200,"data":{"webPages":{"value":[
                    {"name":"title","url":"https://example.com/source","summary":"evidence fake-search-key"}]}}}"""
                else """{"results":[
                    {"title":"unsafe","url":"https://example.com/fake-search-key","content":"unsafe","text":"unsafe"},
                    {"title":"title","url":"https://example.com/source","content":"evidence fake-search-key","text":"evidence fake-search-key"},
                    {"title":"duplicate","url":"https://example.com/source","content":"duplicate","text":"duplicate"}]}""").toByteArray()
            }
            assertEquals(1, calls)
            assertTrue(evidence.contains("untrusted webpage evidence"))
            assertTrue(evidence.contains("https://example.com/source"))
            assertFalse(evidence.contains("fake-search-key"))
            assertFalse(evidence.contains("duplicate"))
        }
    }

    @Test fun invalidSettingsAndUnusableResponsesStopBeforeModel() {
        val invalid = listOf(config("invalid"), config("tavily").put("apiKey", ""),
            config("tavily").put("endpoint", "http://example.com/search"), config("tavily").put("maxResults", 11))
        for (c in invalid) {
            assertThrows(WatchNetworkException::class.java) {
                WatchSearch.evidence(c, "question") { _, _, _, _ -> fail("invalid settings made request"); ByteArray(0) }
            }
        }
        for (raw in listOf("""{"results":[]}""", """{"error":"echo fake-search-key"}""", "invalid")) {
            val error = assertThrows(WatchNetworkException::class.java) {
                WatchSearch.evidence(config("tavily"), "question") { _, _, _, _ -> raw.toByteArray() }
            }
            assertFalse(error.message.orEmpty().contains("fake-search-key"))
        }
    }
}
