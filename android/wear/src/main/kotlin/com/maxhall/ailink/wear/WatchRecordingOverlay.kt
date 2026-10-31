package com.maxhall.ailink.wear

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.SystemClock
import android.util.TypedValue
import android.view.View
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.sin
import kotlin.math.sqrt

internal enum class WatchReleaseAction {
    SEND, CANCEL, REVIEW;

    companion object {
        fun fromDrag(dx: Float, dy: Float): WatchReleaseAction {
            if (dy > -40f) return SEND
            if (dx <= -30f) return CANCEL
            if (dx >= 30f) return REVIEW
            return SEND
        }
    }
}

/** Recording feedback only; the held pointer remains on the chat below it. */
internal class WatchRecordingOverlay(
    context: Context,
    private val text: (String) -> String,
) : View(context) {
    @Volatile var level = 0f
    var releaseAction = WatchReleaseAction.SEND
    var simpleMode = false
    private var startedAt = 0L
    private var smoothedLevel = 0f
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val density: Float
        get() = minOf(resources.displayMetrics.density, minOf(width, height) * .88f / 198)

    fun start() {
        startedAt = SystemClock.elapsedRealtime()
        level = 0f
        smoothedLevel = 0f
        releaseAction = WatchReleaseAction.SEND
        visibility = VISIBLE
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val elapsed = SystemClock.elapsedRealtime() - startedAt
        val cx = width / 2f
        val cy = height / 2f
        val top = cy - 99 * density
        val accent = when (releaseAction) {
            WatchReleaseAction.CANCEL -> Color.rgb(255, 69, 58)
            WatchReleaseAction.REVIEW -> Color.rgb(48, 176, 89)
            WatchReleaseAction.SEND -> Color.rgb(24, 126, 240)
        }
        val foreground = Color.WHITE
        val secondary = Color.rgb(177, 191, 211)
        canvas.drawColor(Color.BLACK)
        if (simpleMode) {
            drawSimpleRecording(canvas, cx, cy, accent, elapsed)
            if (visibility == VISIBLE) postInvalidateOnAnimation()
            return
        }
        paint.style = Paint.Style.FILL
        val micY = top + 78 * density
        paint.color = Color.argb(30, Color.red(accent), Color.green(accent), Color.blue(accent))
        canvas.drawCircle(cx, micY, 32 * density, paint)
        paint.color = accent
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 3 * density
        paint.strokeCap = Paint.Cap.ROUND
        if (releaseAction == WatchReleaseAction.CANCEL) {
            canvas.drawLine(cx - 10 * density, micY - 10 * density, cx + 10 * density, micY + 10 * density, paint)
            canvas.drawLine(cx + 10 * density, micY - 10 * density, cx - 10 * density, micY + 10 * density, paint)
        } else if (releaseAction == WatchReleaseAction.REVIEW) {
            for (line in -1..1) {
                val y = micY + line * 8 * density
                canvas.drawLine(cx - 12 * density, y, cx + (if (line == 1) 6 else 12) * density, y, paint)
            }
        } else {
            paint.style = Paint.Style.FILL
            canvas.drawRoundRect(cx - 6 * density, micY - 16 * density, cx + 6 * density,
                micY + 3 * density, 6 * density, 6 * density, paint)
            paint.style = Paint.Style.STROKE
            canvas.drawArc(cx - 12 * density, micY - 8 * density, cx + 12 * density,
                micY + 10 * density, 0f, 180f, false, paint)
            canvas.drawLine(cx, micY + 10 * density, cx, micY + 17 * density, paint)
            canvas.drawLine(cx - 7 * density, micY + 17 * density, cx + 7 * density, micY + 17 * density, paint)
        }
        drawTarget(canvas, cx - 42 * density, top + 29 * density, "↖", "取消",
            releaseAction == WatchReleaseAction.CANCEL, Color.rgb(255, 69, 58), secondary)
        drawTarget(canvas, cx + 42 * density, top + 29 * density, "↗", "转文字",
            releaseAction == WatchReleaseAction.REVIEW, Color.rgb(48, 176, 89), secondary)
        smoothedLevel += (level - smoothedLevel) * .22f
        paint.style = Paint.Style.FILL
        paint.color = accent
        for (index in 0 until 19) {
            val weight = 1 - abs(index - 9) / 10f
            val pulse = abs(sin(elapsed / 1500.0 * Math.PI * 2 + index * .63)).toFloat() * .72f + .28f
            val barHeight = (2 + 12 * (.15f + smoothedLevel * .85f) * weight * pulse) * density
            val x = cx + (index - 9) * 5 * density
            val y = top + 124 * density
            canvas.drawRoundRect(x - 1.5f * density, y - barHeight / 2,
                x + 1.5f * density, y + barHeight / 2, 2 * density, 2 * density, paint)
        }
        val seconds = elapsed / 1000
        val time = "%02d:%02d.%d".format(java.util.Locale.ROOT, seconds / 60, seconds % 60, elapsed % 1000 / 100)
        drawText(canvas, time, cx, top + 155 * density, 18f, foreground, true)
        val hint = when (releaseAction) {
            WatchReleaseAction.CANCEL -> "松开取消"
            WatchReleaseAction.REVIEW -> "松开转文字"
            WatchReleaseAction.SEND -> "松开发送"
        }
        drawText(canvas, text(hint), cx, top + 177 * density, 11f,
            if (releaseAction == WatchReleaseAction.SEND) secondary else accent)
        if (visibility == VISIBLE) postInvalidateOnAnimation()
    }

    private fun drawTarget(canvas: Canvas, x: Float, y: Float, arrow: String, label: String,
                           selected: Boolean, accent: Int, secondary: Int) {
        if (selected) {
            paint.style = Paint.Style.FILL
            paint.color = accent
            paint.color = Color.argb(38, Color.red(accent), Color.green(accent), Color.blue(accent))
            canvas.drawRoundRect(x - 31 * density, y - 12 * density, x + 31 * density,
                y + 12 * density, 12 * density, 12 * density, paint)
        }
        drawText(canvas, "$arrow ${text(label)}", x, y + 4 * density, 10f, if (selected) accent else secondary)
    }

    private fun drawSimpleRecording(canvas: Canvas, cx: Float, cy: Float, accent: Int, elapsed: Long) {
        smoothedLevel += (level - smoothedLevel) * .22f
        val radius = 69 * density
        val pulse = (sin(elapsed / 1000.0 * Math.PI * 2).toFloat() + 1) / 2
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 2 * density
        paint.color = Color.argb(115, Color.red(accent), Color.green(accent), Color.blue(accent))
        canvas.drawCircle(cx, cy, radius * (1.04f + smoothedLevel * .1f + pulse * .02f), paint)
        paint.style = Paint.Style.FILL
        paint.color = Color.argb(51, Color.red(accent), Color.green(accent), Color.blue(accent))
        canvas.drawCircle(cx, cy, radius, paint)
        paint.color = accent
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 4 * density
        paint.strokeCap = Paint.Cap.ROUND
        when (releaseAction) {
            WatchReleaseAction.CANCEL -> {
                canvas.drawLine(cx - 15 * density, cy - 15 * density, cx + 15 * density, cy + 15 * density, paint)
                canvas.drawLine(cx + 15 * density, cy - 15 * density, cx - 15 * density, cy + 15 * density, paint)
            }
            WatchReleaseAction.REVIEW -> {
                for (line in -1..1) {
                    val y = cy + line * 12 * density
                    canvas.drawLine(cx - 18 * density, y, cx + (if (line == 1) 8 else 18) * density, y, paint)
                }
            }
            WatchReleaseAction.SEND -> {
                paint.style = Paint.Style.FILL
                canvas.drawRoundRect(cx - 9 * density, cy - 25 * density, cx + 9 * density,
                    cy + 5 * density, 9 * density, 9 * density, paint)
                paint.style = Paint.Style.STROKE
                canvas.drawArc(cx - 18 * density, cy - 12 * density, cx + 18 * density,
                    cy + 16 * density, 0f, 180f, false, paint)
                canvas.drawLine(cx, cy + 16 * density, cx, cy + 27 * density, paint)
                canvas.drawLine(cx - 10 * density, cy + 27 * density, cx + 10 * density, cy + 27 * density, paint)
            }
        }
    }

    private fun drawText(canvas: Canvas, value: String, x: Float, y: Float,
                         size: Float, color: Int, bold: Boolean = false) {
        paint.style = Paint.Style.FILL
        paint.color = color
        paint.textAlign = Paint.Align.CENTER
        paint.textSize = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, size, resources.displayMetrics) *
            density / resources.displayMetrics.density
        paint.isFakeBoldText = bold
        canvas.drawText(value, x, y, paint)
        paint.isFakeBoldText = false
    }

    companion object {
        /** Map the captured PCM's RMS to the same -55 to -10 dB range as phone UI. */
        internal fun levelOf(pcm: ByteArray, count: Int): Float {
            val size = minOf(count, pcm.size) / 2
            if (size == 0) return 0f
            var squares = 0.0
            for (index in 0 until size) {
                val sample = ((pcm[index * 2].toInt() and 255) or
                    (pcm[index * 2 + 1].toInt() shl 8)).toShort().toDouble()
                squares += sample * sample
            }
            val rms = sqrt(squares / size) / 32768
            val db = if (rms > 0) 20 * log10(rms) else -55.0
            return ((db + 55) / 45).toFloat().coerceIn(0f, 1f)
        }
    }
}
