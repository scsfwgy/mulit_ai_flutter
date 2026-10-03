package com.maxhall.ailink.wear

import org.junit.Assert.assertEquals
import org.junit.Test

class WatchRecordingGestureTest {
    @Test fun onlyDiagonalUpwardDragsChangeTheReleaseAction() {
        assertEquals(WatchReleaseAction.CANCEL, WatchReleaseAction.fromDrag(-30f, -40f))
        assertEquals(WatchReleaseAction.REVIEW, WatchReleaseAction.fromDrag(30f, -40f))
        for ((dx, dy) in listOf(0f to 0f, 0f to -80f, -80f to 0f, 80f to 0f,
            -29f to -40f, 29f to -40f, -30f to -39f, 30f to -39f)) {
            assertEquals(WatchReleaseAction.SEND, WatchReleaseAction.fromDrag(dx, dy))
        }
    }

    @Test fun returningToCenterRestoresDirectSending() {
        assertEquals(WatchReleaseAction.CANCEL, WatchReleaseAction.fromDrag(-80f, -80f))
        assertEquals(WatchReleaseAction.REVIEW, WatchReleaseAction.fromDrag(80f, -80f))
        assertEquals(WatchReleaseAction.SEND, WatchReleaseAction.fromDrag(0f, 0f))
    }
}
