package com.maxhall.ailink.wear

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.os.SystemClock
import android.view.View
import kotlin.math.sin

/** Small pinned indicator, leaving the chat's long-press target untouched. */
class WatchSpeechIndicator(context: Context, private val color: () -> Int,
                           private val text: (String) -> String) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val density = resources.displayMetrics.density
    private var loading = true
    private var labelKey = "语音加载中"

    init { visibility = GONE }

    fun show(loading: Boolean, labelKey: String = if (loading) "语音加载中" else "播放语音中") {
        this.loading = loading
        this.labelKey = labelKey
        contentDescription = text(labelKey)
        visibility = VISIBLE
        requestLayout()
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        paint.textSize = 10 * density
        val label = text(labelKey)
        setMeasuredDimension((paint.measureText(label) + 40 * density).toInt(), (28 * density).toInt())
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val time = SystemClock.uptimeMillis() / 1000.0
        val centerY = height / 2f
        paint.color = color()
        if (loading) {
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 2 * density
            paint.strokeCap = Paint.Cap.ROUND
            canvas.drawArc(RectF(4 * density, centerY - 7 * density,
                18 * density, centerY + 7 * density), (time * 260 % 360).toFloat(), 260f, false, paint)
        } else {
            paint.style = Paint.Style.FILL
            for (index in 0..4) {
                val bar = (5 + 11 * (sin(time * 7 + index * 1.3) + 1) / 2).toFloat() * density
                val left = (3 + index * 5) * density
                canvas.drawRoundRect(left, centerY - bar / 2, left + 3 * density,
                    centerY + bar / 2, 2 * density, 2 * density, paint)
            }
        }
        paint.style = Paint.Style.FILL
        paint.textSize = 10 * density
        canvas.drawText(text(labelKey),
            32 * density, centerY - (paint.ascent() + paint.descent()) / 2, paint)
        if (visibility == VISIBLE) postInvalidateDelayed(80)
    }
}
