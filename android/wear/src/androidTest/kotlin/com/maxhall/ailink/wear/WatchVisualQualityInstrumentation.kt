package com.maxhall.ailink.wear

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.LayerDrawable
import android.os.Bundle
import android.view.ContextThemeWrapper
import android.view.View
import android.widget.FrameLayout
import androidx.core.splashscreen.R as SplashR
import java.io.File

/** Run on an empty QA emulator in both day and night system modes. */
class WatchVisualQualityInstrumentation : Instrumentation() {
    override fun onCreate(arguments: Bundle?) { super.onCreate(arguments); start() }

    override fun onStart() {
        val result = Bundle()
        val settings = targetContext.getSharedPreferences("watch_settings", 0)
        val originalGuide = settings.all["gestureGuideSeen"] as? Boolean
        var activity: WatchActivity? = null
        var resultCode = 0
        try {
            check(targetContext.packageName.endsWith(".debug"))
            check(WatchConfigStore(targetContext).load() == null &&
                targetContext.getSharedPreferences("watch_conversation", 0)
                    .getString("turns", "[]") == "[]") { "Use an empty QA emulator" }
            runOnMainSync {
                val starting = ContextThemeWrapper(targetContext, R.style.Theme_AILink_Wear_Starting)
                val attrs = starting.obtainStyledAttributes(intArrayOf(
                    SplashR.attr.windowSplashScreenBackground, SplashR.attr.windowSplashScreenAnimatedIcon,
                    SplashR.attr.postSplashScreenTheme))
                check(attrs.getColor(0, Color.WHITE) == Color.BLACK)
                check(attrs.getResourceId(2, 0) == R.style.Theme_AILink_Wear)
                val icon = attrs.getDrawable(1) as LayerDrawable
                val size = (48 * targetContext.resources.displayMetrics.density + .5f).toInt()
                check(icon.getLayerWidth(0) == size && icon.getLayerHeight(0) == size)
                check(icon.getDrawable(0) is BitmapDrawable) {
                    "Splash icon must be the circular launcher bitmap, not an adaptive icon"
                }
                attrs.recycle()
            }
            settings.edit().putBoolean("gestureGuideSeen", false).commit()
            val screen = startActivitySync(Intent(targetContext, WatchActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as WatchActivity
            activity = screen
            waitForIdleSync()
            val pages = WatchActivity::class.java.getDeclaredField("pages")
                .apply { isAccessible = true }.get(screen) as FrameLayout
            val showPage = WatchActivity::class.java.getDeclaredMethod("showPage", Int::class.java)
                .apply { isAccessible = true }
            fun capture(name: String) {
                waitForIdleSync()
                android.os.SystemClock.sleep(400)
                val bitmap = uiAutomation.takeScreenshot()
                File(targetContext.filesDir, "quality-$name.png").outputStream().use {
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                }
                bitmap.recycle()
            }
            for (name in listOf("guide", "chat", "settings")) {
                val index = if (name == "settings") 1 else 0
                val childIndex = if (name == "guide") 2 else index
                settings.edit().putBoolean("gestureGuideSeen", name != "guide").commit()
                runOnMainSync {
                    showPage.invoke(screen, index)
                    check((pages.background as ColorDrawable).color == Color.BLACK)
                    check(pages.getChildAt(childIndex).visibility == View.VISIBLE)
                    check((pages.getChildAt(childIndex).background as ColorDrawable).color == Color.BLACK)
                }
                capture(name)
            }
            runOnMainSync { showPage.invoke(screen, 0) }
            val overlay = WatchActivity::class.java.getDeclaredField("recordingOverlay")
                .apply { isAccessible = true }.get(screen) as WatchRecordingOverlay
            for (simple in listOf(false, true)) {
                for (action in WatchReleaseAction.entries) {
                    runOnMainSync {
                        overlay.start()
                        overlay.simpleMode = simple
                        overlay.releaseAction = action
                        val bitmap = Bitmap.createBitmap(overlay.width, overlay.height, Bitmap.Config.ARGB_8888)
                        overlay.draw(Canvas(bitmap))
                        // Inside the old light circular panel, away from controls.
                        check(bitmap.getPixel((bitmap.width * .92f).toInt(), bitmap.height / 2) == Color.BLACK)
                        check(bitmap.getPixel(bitmap.width / 2, 0) == Color.BLACK)
                        bitmap.recycle()
                    }
                    capture("recording-$simple-$action")
                }
            }
            runOnMainSync { overlay.visibility = View.GONE }
            result.putString("result", "PASS: black splash theme, 48dp launcher icon, black chat/settings/guide and both recording modes in all release states")
            resultCode = -1
        } catch (error: Throwable) {
            result.putString("result", "FAIL: ${error.javaClass.simpleName}: ${error.message}")
        } finally {
            runOnMainSync { activity?.finish() }
            settings.edit().apply {
                if (originalGuide == null) remove("gestureGuideSeen") else putBoolean("gestureGuideSeen", originalGuide)
            }.commit()
        }
        finish(resultCode, result)
    }
}
