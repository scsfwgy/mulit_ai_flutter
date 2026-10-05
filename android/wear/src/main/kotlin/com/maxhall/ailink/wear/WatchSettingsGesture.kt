package com.maxhall.ailink.wear

internal object WatchSettingsGesture {
    // A deliberate horizontal swipe; vertical scrolling and leftward drags stay
    // within settings. Distances are logical pixels, independent of density.
    fun shouldReturnToChat(dx: Float, dy: Float): Boolean =
        dx > 48 && dx > kotlin.math.abs(dy) * 1.5
}
