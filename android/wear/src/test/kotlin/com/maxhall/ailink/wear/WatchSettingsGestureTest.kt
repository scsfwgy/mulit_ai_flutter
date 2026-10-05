package com.maxhall.ailink.wear

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WatchSettingsGestureTest {
    @Test fun deliberateRightSwipeReturnsToChat() {
        assertTrue(WatchSettingsGesture.shouldReturnToChat(70f, 10f))
        assertTrue(WatchSettingsGesture.shouldReturnToChat(100f, -20f))
    }

    @Test fun scrollingLeftSwipeAndShortDragsStayInSettings() {
        assertFalse(WatchSettingsGesture.shouldReturnToChat(35f, 0f))
        assertFalse(WatchSettingsGesture.shouldReturnToChat(-100f, 0f))
        assertFalse(WatchSettingsGesture.shouldReturnToChat(60f, 90f))
        assertFalse(WatchSettingsGesture.shouldReturnToChat(60f, -90f))
    }
}
