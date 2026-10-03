package com.maxhall.ailink.wear

import org.junit.Assert.*
import org.junit.Test

class WatchConfigurationRequirementsTest {
    @Test fun bothServicesAreRequired() {
        assertNotNull(missingWatchServices(false, false))
        assertTrue(missingWatchServices(false, true)!!.contains("文字模型"))
        assertTrue(missingWatchServices(true, false)!!.contains("语音识别"))
        assertNull(missingWatchServices(true, true))
    }

    @Test fun aServiceNeedsAnEndpointModelAndKey() {
        assertTrue(watchServiceReady("https://example.com/v1", "key", "model"))
        assertTrue(watchServiceReady("http://10.0.2.2:8080", "key", "model"))
        assertFalse(watchServiceReady("https://example.com", "  ", "model"))
        assertFalse(watchServiceReady("https://example.com", "key", " "))
        assertFalse(watchServiceReady("", "key", "model"))
        assertFalse(watchServiceReady("http://example.com", "key", "model"))
        assertFalse(watchServiceReady("https://key@example.com", "key", "model"))
    }
}
