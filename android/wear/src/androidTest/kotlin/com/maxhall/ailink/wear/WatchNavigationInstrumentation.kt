package com.maxhall.ailink.wear

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import android.os.SystemClock
import android.view.MotionEvent
import android.widget.TextView
import android.widget.ScrollView
import android.widget.FrameLayout
import java.io.File

/** Runs gesture regressions and captures settings on an empty Debug emulator. */
class WatchNavigationInstrumentation : Instrumentation() {
    override fun onCreate(arguments: Bundle?) { super.onCreate(arguments); start() }

    override fun onStart() {
        val result = Bundle()
        val settings = targetContext.getSharedPreferences("watch_settings", 0)
        val originalGuide = settings.all["gestureGuideSeen"] as? Boolean
        val originalLanguage = settings.all["language"] as? String
        val originalMode = settings.all["simpleRecording"] as? Boolean
        var activity: WatchActivity? = null
        var resultCode = 0
        try {
            check(targetContext.packageName.endsWith(".debug"))
            check(WatchConfigStore(targetContext).load() == null &&
                targetContext.getSharedPreferences("watch_conversation", 0)
                    .getString("turns", "[]") == "[]") { "Use an empty QA emulator" }
            settings.edit().putBoolean("gestureGuideSeen", true).putString("language", "zh").commit()
            val screen = startActivitySync(Intent(targetContext, WatchActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as WatchActivity
            activity = screen
            waitForIdleSync()
            val root = screen.window.decorView
            val x = root.width / 2f
            val y = root.height * .23f
            fun page(): Int = WatchActivity::class.java.getDeclaredField("page")
                .apply { isAccessible = true }.getInt(screen)
            fun event(action: Int, px: Float, py: Float, down: Long) {
                runOnMainSync {
                    val touch = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, px, py, 0)
                    screen.dispatchTouchEvent(touch)
                    touch.recycle()
                }
            }
            fun doubleTap(px: Float = x, py: Float = y) {
                repeat(2) {
                    val down = SystemClock.uptimeMillis()
                    event(MotionEvent.ACTION_DOWN, px, py, down)
                    Thread.sleep(35)
                    event(MotionEvent.ACTION_UP, px, py, down)
                    Thread.sleep(75)
                }
                waitForIdleSync()
                Thread.sleep(350)
            }
            fun screenshot(name: String) {
                val bitmap = uiAutomation.takeScreenshot()
                File(targetContext.filesDir, name).outputStream().use {
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                }
                bitmap.recycle()
            }
            doubleTap()
            check(page() == 1) { "Double tap did not enter settings" }
            screenshot("navigation-settings-zh.png")
            doubleTap()
            check(page() == 0) { "Double tap did not return to chat" }
            doubleTap()
            check(page() == 1) { "A consumed tap blocked the next gesture" }

            val conversation = targetContext.getSharedPreferences("watch_conversation", 0)
            val topicBefore = conversation.getString("conversationId", null)
            val newTopic = run {
                val views = mutableListOf<android.view.View>()
                fun visit(view: android.view.View) {
                    views.add(view)
                    if (view is android.view.ViewGroup) repeat(view.childCount) { visit(view.getChildAt(it)) }
                }
                visit(root)
                views.filterIsInstance<TextView>().first { it.text.toString() == "开启新话题" }
            }
            val location = IntArray(2)
            runOnMainSync { newTopic.getLocationInWindow(location) }
            doubleTap(location[0] + newTopic.width / 2f, location[1] + newTopic.height / 2f)
            check(page() == 0 && conversation.getString("conversationId", null) == topicBefore) {
                "Double-tap also activated the new-topic control"
            }
            doubleTap()
            check(page() == 1)

            fun modeLocation(field: String): Pair<Float, Float> {
                val view = WatchActivity::class.java.getDeclaredField(field)
                    .apply { isAccessible = true }.get(screen) as TextView
                runOnMainSync { view.getLocationInWindow(location) }
                return Pair(location[0] + view.width / 2f, location[1] + view.height / 2f)
            }
            val simple = modeLocation("simpleMode")
            val tapDown = SystemClock.uptimeMillis()
            event(MotionEvent.ACTION_DOWN, simple.first, simple.second, tapDown)
            Thread.sleep(35)
            event(MotionEvent.ACTION_UP, simple.first, simple.second, tapDown)
            Thread.sleep(400)
            check(settings.getBoolean("simpleRecording", false) && page() == 1) {
                "Single tap no longer activates settings controls"
            }
            val beginner = modeLocation("beginnerMode")
            doubleTap(beginner.first, beginner.second)
            check(settings.getBoolean("simpleRecording", false) && page() == 0) {
                "Double-tap also changed the recording mode"
            }
            doubleTap()
            check(page() == 1)

            val down = SystemClock.uptimeMillis()
            event(MotionEvent.ACTION_DOWN, x, y, down)
            repeat(4) { step ->
                Thread.sleep(100)
                event(MotionEvent.ACTION_MOVE, x + root.width * .075f * (step + 1), y, down)
            }
            event(MotionEvent.ACTION_UP, x + root.width * .3f, y, down)
            check(page() == 0) { "Slow right swipe did not return to chat" }
            doubleTap()
            check(page() == 1) { "Swipe blocked the next double tap" }
            val scrollDown = SystemClock.uptimeMillis()
            event(MotionEvent.ACTION_DOWN, x, root.height * .75f, scrollDown)
            repeat(4) { step ->
                Thread.sleep(60)
                event(MotionEvent.ACTION_MOVE, x, root.height * (.75f - .08f * (step + 1)), scrollDown)
            }
            event(MotionEvent.ACTION_UP, x, root.height * .43f, scrollDown)
            check(page() == 1) { "Vertical scrolling left settings" }
            val scroll = (WatchActivity::class.java.getDeclaredField("pages")
                .apply { isAccessible = true }.get(screen) as FrameLayout).getChildAt(1) as ScrollView
            runOnMainSync { scroll.scrollTo(0, (100 * screen.resources.displayMetrics.density).toInt()) }
            waitForIdleSync()
            Thread.sleep(200)
            screenshot("navigation-modes-zh.png")
            runOnMainSync {
                WatchActivity::class.java.getDeclaredMethod("applyPhoneLanguage", String::class.java)
                    .apply { isAccessible = true }.invoke(screen, "en")
            }
            waitForIdleSync()
            Thread.sleep(200)
            screenshot("navigation-settings-en.png")
            result.putString("result", "PASS: double-tap navigation, slow swipe return, vertical scroll, single-tap controls, no accidental actions and bilingual screenshots")
            resultCode = -1
        } catch (error: Throwable) {
            result.putString("result", "FAIL: ${error.javaClass.simpleName}: ${error.message}")
        } finally {
            runOnMainSync { activity?.finish() }
            settings.edit().apply {
                if (originalGuide == null) remove("gestureGuideSeen") else putBoolean("gestureGuideSeen", originalGuide)
                if (originalLanguage == null) remove("language") else putString("language", originalLanguage)
                if (originalMode == null) remove("simpleRecording") else putBoolean("simpleRecording", originalMode)
            }.commit()
        }
        finish(resultCode, result)
    }
}
