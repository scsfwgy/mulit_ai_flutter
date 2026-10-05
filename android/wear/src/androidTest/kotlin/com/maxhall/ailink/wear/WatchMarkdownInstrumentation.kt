package com.maxhall.ailink.wear

import android.app.Instrumentation
import android.graphics.Color
import android.os.Bundle
import android.text.Spanned
import android.widget.TextView

/** Native TextView spans need a device/emulator; this test never touches saved settings. */
class WatchMarkdownInstrumentation : Instrumentation() {
    override fun onCreate(arguments: Bundle?) { super.onCreate(arguments); start() }

    override fun onStart() {
        val result = Bundle()
        try {
            runOnMainSync {
                val renderer = WatchMarkdown(targetContext, Color.WHITE, Color.BLUE)
                val view = TextView(targetContext)
                fun render(source: String): Spanned {
                    renderer.render(view, source)
                    return view.text as Spanned
                }
                fun Spanned.hasSpan(name: String) = getSpans(0, length, Any::class.java)
                    .any { it.javaClass.simpleName == name }
                val news = render("## 新闻摘要\n\n- **安全警告**：[纽约时报中文网](https://m.cn.nytimes.com)\n- 第二条")
                check(news.contains("安全警告：纽约时报中文网") && !news.contains("https://") && !news.contains("**"))
                check(news.hasSpan("HeadingSpan") && news.hasSpan("StrongEmphasisSpan") && news.hasSpan("BulletListItemSpan") && news.hasSpan("LinkSpan"))
                val code = render("`api_key`\n\n```swift\nlet api_key = \"**literal** # value\"\n```")
                check(code.contains("api_key = \"**literal** # value\""))
                check(code.hasSpan("CodeSpan") && code.hasSpan("CodeBlockSpan"))
                val table = render("| 名称 | 说明 |\n| --- | --- |\n| 甲 | **很长的说明** |\n| 乙 | [来源](https://example.com) |")
                check(table.contains("名称: 甲\n说明: 很长的说明") && table.hasSpan("LinkSpan"))
                check(WatchMarkdown.isWebLink("https://example.com/path") && !WatchMarkdown.isWebLink("javascript:alert(1)"))
                check(!WatchMarkdown.isWebLink("file:///tmp/a"))
                val streaming = "## 标题\n\n**正在生成** [来源](https://example.com)\n\n```swift\nlet api_key = 1"
                for (end in 0..streaming.length) render(streaming.take(end))
                check(view.text.contains("api_key = 1"))
            }
            result.putString("result", "PASS: native spans, news links, verbatim code, stacked tables and streaming prefixes")
            finish(-1, result)
        } catch (error: Throwable) {
            result.putString("result", "FAIL: ${error.javaClass.simpleName}: ${error.message}")
            finish(0, result)
        }
    }
}
