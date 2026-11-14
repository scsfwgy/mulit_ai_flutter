package com.maxhall.ailink.wear

import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.*
import org.junit.Test

class DeepSeekVoiceAudioTest {
    @Test fun wrapsPcmWithExact24khzWavHeader() {
        val pcm = byteArrayOf(0, 1, 2, 3)
        val wav = deepSeekSpeechWav(pcm)
        val header = ByteBuffer.wrap(wav).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals("RIFF", String(wav.copyOfRange(0, 4), Charsets.US_ASCII))
        assertEquals(wav.size - 8, header.getInt(4))
        assertEquals(24000, header.getInt(24))
        assertEquals(48000, header.getInt(28))
        assertEquals(pcm.size, header.getInt(40))
        assertArrayEquals(pcm, wav.copyOfRange(44, wav.size))
    }

    @Test fun rejectsEmptyAndIncompleteSamples() {
        for (pcm in listOf(byteArrayOf(), byteArrayOf(1))) {
            try {
                deepSeekSpeechWav(pcm)
                fail("Invalid PCM must not reach the player")
            } catch (_: WatchNetworkException) {}
        }
    }
}
