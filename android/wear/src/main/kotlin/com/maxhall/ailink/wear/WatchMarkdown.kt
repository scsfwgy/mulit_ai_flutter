package com.maxhall.ailink.wear

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.text.style.StyleSpan
import android.widget.TextView
import io.noties.markwon.AbstractMarkwonPlugin
import io.noties.markwon.Markwon
import io.noties.markwon.MarkwonConfiguration
import io.noties.markwon.MarkwonVisitor
import io.noties.markwon.core.MarkwonTheme
import io.noties.markwon.ext.strikethrough.StrikethroughPlugin
import org.commonmark.ext.gfm.tables.TableBlock
import org.commonmark.ext.gfm.tables.TableCell
import org.commonmark.ext.gfm.tables.TableRow
import org.commonmark.ext.gfm.tables.TablesExtension
import org.commonmark.node.Node
import org.commonmark.parser.Parser
import java.net.URI

/** Shared by the streaming answer and saved turns. The stored Markdown stays intact. */
class WatchMarkdown(context: Context, textColor: Int, linkColor: Int) {
    private val renderer = Markwon.builder(context)
        .usePlugin(StrikethroughPlugin.create())
        .usePlugin(object : AbstractMarkwonPlugin() {
            override fun configureParser(builder: Parser.Builder) {
                builder.extensions(listOf(TablesExtension.create()))
            }

            override fun configureVisitor(builder: MarkwonVisitor.Builder) {
                // Stack table fields so even wide tables remain readable on a watch.
                builder.on(TableBlock::class.java) { visitor, table ->
                    visitor.blockStart(table)
                    val rows = mutableListOf<TableRow>()
                    fun collect(node: Node) {
                        if (node is TableRow) rows.add(node)
                        else {
                            var child = node.firstChild
                            while (child != null) { collect(child); child = child.next }
                        }
                    }
                    collect(table)
                    val headers = rows.firstOrNull()?.let { cells(it) }.orEmpty()
                    rows.forEachIndexed { rowIndex, row ->
                        if (rowIndex > 0) { visitor.ensureNewLine(); visitor.forceNewLine() }
                        cells(row).forEachIndexed { column, cell ->
                            if (column > 0) {
                                if (rowIndex == 0) visitor.builder().append(" · ") else visitor.ensureNewLine()
                            }
                            if (rowIndex > 0 && column < headers.size) {
                                val start = visitor.length()
                                visitor.visitChildren(headers[column])
                                visitor.builder().setSpan(StyleSpan(Typeface.BOLD), start, visitor.length())
                                visitor.builder().append(": ")
                            }
                            val start = visitor.length()
                            visitor.visitChildren(cell)
                            if (rowIndex == 0) visitor.builder().setSpan(StyleSpan(Typeface.BOLD), start, visitor.length())
                        }
                    }
                    visitor.blockEnd(table)
                }
            }

            override fun configureTheme(builder: MarkwonTheme.Builder) {
                val density = context.resources.displayMetrics.density
                builder.linkColor(linkColor)
                    .headingTextSizeMultipliers(floatArrayOf(1.27f, 1.13f, 1.07f, 1f, 1f, 1f))
                    .headingBreakHeight(0)
                    .blockMargin((14 * density).toInt())
                    .blockQuoteWidth((2 * density).toInt())
                    .blockQuoteColor(linkColor)
                    .codeTextColor(textColor)
                    .codeBlockTextColor(textColor)
                    .codeBackgroundColor(Color.argb(30, 128, 128, 128))
                    .codeBlockBackgroundColor(Color.argb(30, 128, 128, 128))
            }

            override fun configureConfiguration(builder: MarkwonConfiguration.Builder) {
                // Keep non-web schemes in the text without launching another application.
                val defaultResolver = io.noties.markwon.LinkResolverDef()
                builder.linkResolver { view, link ->
                    if (isWebLink(link)) defaultResolver.resolve(view, link)
                }
            }
        })
        .build()

    fun render(view: TextView, source: String) {
        renderer.setMarkdown(view, source)
    }

    companion object {
        private fun cells(row: TableRow): List<TableCell> {
            val result = mutableListOf<TableCell>()
            var child = row.firstChild
            while (child != null) {
                if (child is TableCell) result.add(child)
                child = child.next
            }
            return result
        }

        internal fun isWebLink(value: String): Boolean = try {
            val uri = URI(value)
            uri.scheme?.lowercase() in setOf("https", "http") && !uri.host.isNullOrEmpty()
        } catch (_: Exception) { false }
    }
}
