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

/** Recording feedback only; the held pointer remains on the button below it. */
class WatchRecordingOverlay(
    context: Context,
    private val dark: () -> Boolean,
    private val text: (String) -> String,
) : View(context) {
    @Volatile var level = 0f
    var cancelling = false
    private var startedAt = 0L
    private var smoothedLevel = 0f
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val density: Float
        get() = minOf(resources.displayMetrics.density, minOf(width, height) * .88f / 198)

    fun start() {
        startedAt = SystemClock.elapsedRealtime()
        level = 0f
        smoothedLevel = 0f
        cancelling = false
        visibility = VISIBLE
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val elapsed = SystemClock.elapsedRealtime() - startedAt
        val cx = width / 2f
        val cy = height / 2f
        val top = cy - 99 * density
        val accent = if (cancelling) Color.rgb(255, 69, 58) else Color.rgb(24, 126, 240)
        val foreground = if (dark()) Color.WHITE else Color.rgb(23, 31, 42)
        val secondary = if (dark()) Color.rgb(177, 191, 211) else Color.rgb(77, 92, 111)
        canvas.drawColor(0xA0000000.toInt())
        paint.style = Paint.Style.FILL
        paint.color = if (dark()) Color.rgb(28, 28, 30) else Color.WHITE
        canvas.drawCircle(cx, cy, 99 * density, paint)

        val micY = top + 30 * density
        paint.color = Color.argb(30, Color.red(accent), Color.green(accent), Color.blue(accent))
        canvas.drawCircle(cx, micY, 18 * density, paint)
        paint.color = accent
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 2 * density
        paint.strokeCap = Paint.Cap.ROUND
        if (cancelling) {
            canvas.drawLine(cx - 5 * density, micY - 5 * density, cx + 5 * density, micY + 5 * density, paint)
            canvas.drawLine(cx + 5 * density, micY - 5 * density, cx - 5 * density, micY + 5 * density, paint)
        } else {
            canvas.drawRoundRect(cx - 3 * density, micY - 8 * density, cx + 3 * density,
                micY + 2 * density, 3 * density, 3 * density, paint)
            canvas.drawArc(cx - 7 * density, micY - 6 * density, cx + 7 * density,
                micY + 6 * density, 0f, 180f, false, paint)
            canvas.drawLine(cx, micY + 6 * density, cx, micY + 10 * density, paint)
            canvas.drawLine(cx - 4 * density, micY + 10 * density, cx + 4 * density, micY + 10 * density, paint)
        }
        drawText(canvas, text(if (cancelling) "松开取消录音" else "正在录音"), cx,
            top + 66 * density, 13f, foreground, true)

        smoothedLevel += (level - smoothedLevel) * .22f
        paint.style = Paint.Style.FILL
        paint.color = accent
        for (index in 0 until 19) {
            val weight = 1 - abs(index - 9) / 10f
            val pulse = abs(sin(elapsed / 1500.0 * Math.PI * 2 + index * .63)).toFloat() * .72f + .28f
            val barHeight = (3 + 26 * (.15f + smoothedLevel * .85f) * weight * pulse) * density
            val x = cx + (index - 9) * 6 * density
            val y = top + 92 * density
            canvas.drawRoundRect(x - 1.5f * density, y - barHeight / 2,
                x + 1.5f * density, y + barHeight / 2, 2 * density, 2 * density, paint)
        }
        val seconds = elapsed / 1000
        val time = "%02d:%02d.%d".format(java.util.Locale.ROOT, seconds / 60, seconds % 60, elapsed % 1000 / 100)
        drawText(canvas, time, cx, top + 136 * density, 22f, foreground, true)
        drawText(canvas, text(if (cancelling) "松开取消" else "松开转写"), cx,
            top + 158 * density, 11f, if (cancelling) accent else secondary)
        if (!cancelling) drawText(canvas, text("上滑取消"), cx, top + 177 * density, 10f, secondary)
        if (visibility == VISIBLE) postInvalidateOnAnimation()
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
