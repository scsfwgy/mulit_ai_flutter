package com.maxhall.ailink.wear

import java.io.IOException

class WatchNetworkException(message: String) : Exception(message)
class PhoneRelayException(message: String, val networkFailure: Boolean) : Exception(message)

/** Performs at most one cross-device failover for each independent API stage. */
class WatchRouteExecutor {
    fun <T> run(
        connectedPhone: String?,
        reconnectPhone: () -> String?,
        phone: (String) -> T,
        watch: () -> T,
        onPhone: (fallback: Boolean) -> Unit = {},
        onWatch: (fallback: Boolean) -> Unit = {},
    ): T {
        if (Thread.currentThread().isInterrupted) throw InterruptedException()
        if (connectedPhone != null) {
            onPhone(false)
            try {
                return phone(connectedPhone)
            } catch (error: PhoneRelayException) {
                if (Thread.currentThread().isInterrupted) throw InterruptedException()
                if (!error.networkFailure) throw error
                onWatch(true)
                try {
                    return watch()
                } catch (_: IOException) {
                    throw WatchNetworkException("手机与手表网络均不可用，请检查连接后重试")
                }
            }
        }
        onWatch(false)
        try {
            return watch()
        } catch (error: IOException) {
            if (Thread.currentThread().isInterrupted) throw InterruptedException()
            val node = reconnectPhone() ?: throw error
            onPhone(true)
            try {
                return phone(node)
            } catch (phoneError: PhoneRelayException) {
                if (phoneError.networkFailure) {
                    throw WatchNetworkException("手机与手表网络均不可用，请检查连接后重试")
                }
                throw phoneError
            }
        }
    }
}
