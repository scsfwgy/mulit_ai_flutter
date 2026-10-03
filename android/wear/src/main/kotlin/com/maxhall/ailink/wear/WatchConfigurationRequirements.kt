package com.maxhall.ailink.wear

import java.net.URI

internal fun watchServiceReady(baseUrl: String, apiKey: String, model: String): Boolean {
    if (apiKey.isBlank() || model.isBlank()) return false
    return try {
        val uri = URI(baseUrl.trim())
        val local = uri.host in setOf("localhost", "127.0.0.1", "10.0.2.2")
        !uri.host.isNullOrBlank() && uri.userInfo == null && uri.query == null && uri.fragment == null &&
            (uri.scheme == "https" || (uri.scheme == "http" && local))
    } catch (_: Exception) { false }
}

internal fun missingWatchServices(textReady: Boolean, asrReady: Boolean): String? = when {
    !textReady && !asrReady -> "请先在手机配置文字模型和语音识别服务及密钥"
    !textReady -> "请先在手机配置文字模型服务、模型和密钥"
    !asrReady -> "请先在手机配置语音识别服务、识别模型和密钥"
    else -> null
}
