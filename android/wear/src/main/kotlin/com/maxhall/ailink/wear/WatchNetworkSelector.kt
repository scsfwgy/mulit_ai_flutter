package com.maxhall.ailink.wear

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** Selects a watch Wi-Fi/cellular network without changing the process default. */
class WatchNetworkSelector(context: Context) {
    private val manager = context.getSystemService(ConnectivityManager::class.java)

    fun <T> use(block: (Network) -> T): T {
        val active = manager.allNetworks.firstOrNull { network ->
            val capabilities = manager.getNetworkCapabilities(network) ?: return@firstOrNull false
            ownTransport(capabilities) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        }
        if (active != null) return block(active)

        val available = AtomicReference<Network?>()
        val latch = CountDownLatch(1)
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                if (ownTransport(capabilities) &&
                    capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) {
                    available.set(network)
                    latch.countDown()
                }
            }
        }
        try {
            manager.requestNetwork(request, callback, 10_000)
            if (!latch.await(11, TimeUnit.SECONDS)) {
                throw IOException("手表 Wi-Fi 或蜂窝网络不可用")
            }
            return block(available.get() ?: throw IOException("手表网络不可用"))
        } catch (error: SecurityException) {
            throw IOException("无法获取手表网络", error)
        } finally {
            try { manager.unregisterNetworkCallback(callback) } catch (_: Exception) { }
        }
    }

    private fun ownTransport(capabilities: NetworkCapabilities) =
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
}
