package com.maxhall.ailink.wear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WatchPresentationTest {
    @Test fun languageChangesTranslateExistingStatusButPreserveModelIds() {
        val english = translateWatchText("正在识别语音…", "en")
        assertEquals("Transcribing…", english)
        assertEquals("正在识别语音…", translateWatchText(english, "zh"))
        assertEquals("deepseek-flash", translateWatchText("deepseek-flash", "zh"))
        assertEquals("deepseek-flash", translateWatchText("deepseek-flash", "en"))
    }

    @Test fun waveformLevelDistinguishesSilenceAndSpeechAndStaysInRange() {
        assertEquals(0f, WatchRecordingOverlay.levelOf(ByteArray(64), 64), 0f)
        // Alternating positive and negative PCM samples, little endian.
        val quiet = byteArrayOf(0x64, 0, 0x9c.toByte(), 0xff.toByte())
        val loud = byteArrayOf(0xff.toByte(), 0x7f, 0, 0x80.toByte())
        val quietLevel = WatchRecordingOverlay.levelOf(quiet, quiet.size)
        assertTrue(quietLevel > 0f && quietLevel < 1f)
        assertEquals(1f, WatchRecordingOverlay.levelOf(loud, loud.size), 0f)
        assertEquals(0f, WatchRecordingOverlay.levelOf(byteArrayOf(0), 1), 0f)
    }
}
