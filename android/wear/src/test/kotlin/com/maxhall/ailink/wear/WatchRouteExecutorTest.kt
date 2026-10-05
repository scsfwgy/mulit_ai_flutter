package com.maxhall.ailink.wear

import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class WatchRouteExecutorTest {
    private val router = WatchRouteExecutor()

    @Test fun interruptedSpeechDoesNotFallBackToAnotherBillableRequest() {
        var phoneCalls = 0
        try {
            assertThrows(InterruptedException::class.java) {
                router.run(
                    connectedPhone = null,
                    reconnectPhone = { "phone" },
                    phone = { phoneCalls++; "wrong" },
                    watch = {
                        Thread.currentThread().interrupt()
                        throw IOException("cancelled speech socket")
                    },
                )
            }
            assertEquals(0, phoneCalls)
        } finally { Thread.interrupted() }
    }

    @Test fun connectedPhoneIsPreferred() {
        val calls = mutableListOf<String>()
        val answer = router.run(
            connectedPhone = "phone",
            reconnectPhone = { null },
            phone = { calls += "phone"; "answer" },
            watch = { calls += "watch"; "wrong" },
        )
        assertEquals("answer", answer)
        assertEquals(listOf("phone"), calls)
    }

    @Test fun phoneNetworkFailureFallsBackToWatchOnce() {
        val calls = mutableListOf<String>()
        val answer = router.run(
            connectedPhone = "phone",
            reconnectPhone = { null },
            phone = { calls += "phone"; throw PhoneRelayException("offline", true) },
            watch = { calls += "watch"; "answer" },
        )
        assertEquals("answer", answer)
        assertEquals(listOf("phone", "watch"), calls)
    }

    @Test fun providerErrorDoesNotTriggerAnotherRequest() {
        var watchCalls = 0
        assertThrows(PhoneRelayException::class.java) {
            router.run(
                connectedPhone = "phone",
                reconnectPhone = { null },
                phone = { throw PhoneRelayException("bad key", false) },
                watch = { watchCalls++; "wrong" },
            )
        }
        assertEquals(0, watchCalls)
    }

    @Test fun disconnectedWatchCanUsePhoneAfterReconnection() {
        val calls = mutableListOf<String>()
        val answer = router.run(
            connectedPhone = null,
            reconnectPhone = { "phone" },
            phone = { calls += "phone"; "answer" },
            watch = { calls += "watch"; throw IOException("offline") },
        )
        assertEquals("answer", answer)
        assertEquals(listOf("watch", "phone"), calls)
    }

    @Test fun bothNetworkFailuresStopAfterTwoAttempts() {
        val calls = mutableListOf<String>()
        assertThrows(WatchNetworkException::class.java) {
            router.run(
                connectedPhone = "phone",
                reconnectPhone = { null },
                phone = { calls += "phone"; throw PhoneRelayException("offline", true) },
                watch = { calls += "watch"; throw IOException("offline") },
            )
        }
        assertEquals(listOf("phone", "watch"), calls)
    }
}
