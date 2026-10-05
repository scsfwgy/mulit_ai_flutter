import Foundation

@main
struct WatchMarkdownTests {
  static func main() throws {
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
      if !condition() { throw NSError(domain: message, code: 1) }
    }
    func plain(_ block: WatchMarkdownDocument.Block) -> String { String(block.text.characters) }

    let news = WatchMarkdownDocument("""
    ## 新闻摘要

    - **安全警告**：[纽约时报中文网](https://m.cn.nytimes.com)
    - 第二条
      1. 子项

    > 请核实来源

    下一段
    """)
    try expect(news.blocks.map(plain) == ["新闻摘要", "安全警告：纽约时报中文网", "第二条", "子项", "请核实来源", "下一段"], "readable news and separate paragraphs")
    try expect(news.blocks[0].heading == 2 && news.blocks[1].marker == "•" && news.blocks[3].marker == "1." && news.blocks[3].listDepth == 2, "headings and nested ordered lists")
    try expect(news.blocks[4].quote, "quote structure")
    try expect(news.blocks[1].text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }, "bold inline text")
    try expect(news.blocks[1].text.runs.contains { $0.link?.host == "m.cn.nytimes.com" }, "source link retained without raw URL in visible text")

    let code = WatchMarkdownDocument("""
    `api_key` 与 *斜体*

    ```swift
    let api_key = "**literal** # value"
    ```
    """)
    try expect(plain(code.blocks[1]).contains("api_key = \"**literal** # value\"") && code.blocks[1].code, "code is preserved verbatim")
    try expect(code.blocks[0].text.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true }, "inline code")
    try expect(code.blocks[0].text.runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true }, "italic")

    let table = WatchMarkdownDocument("""
    | 名称 | 说明 |
    | --- | --- |
    | 甲 | **很长的说明** |
    | 乙 | [来源](https://example.com) |
    """)
    try expect(table.blocks.count == 3 && plain(table.blocks[1]) == "名称: 甲\n说明: 很长的说明", "table row fields retain their headers")
    try expect(table.blocks[2].text.runs.contains { $0.link != nil }, "table links remain attributed")
    let emptyCell = WatchMarkdownDocument("| 名称 | 值 |\n| --- | --- |\n| | 1 |")
    try expect(plain(emptyCell.blocks[1]) == "名称: \n值: 1", "empty cells do not shift table columns")
    let links = WatchMarkdownDocument("[安全](https://example.com) [禁止](javascript:alert) [文件](file:///tmp/a)")
    try expect(links.blocks[0].text.runs.filter { $0.link != nil }.count == 1, "only web links are interactive")

    let streaming = "## 标题\n\n**正在生成** [来源](https://example.com)\n\n```swift\nlet api_key = 1"
    for end in streaming.indices {
      _ = WatchMarkdownDocument(String(streaming[..<end]))
    }
    try expect(WatchMarkdownDocument(streaming).blocks.last?.code == true, "unfinished streaming fence renders as code")
    print("PASS: watch Markdown news, inline styles, lists, links, code, tables and streaming prefixes")
  }
}
