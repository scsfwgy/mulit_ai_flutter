import Foundation

/// Foundation parses both block structure and inline formatting; no changes to saved answers.
struct WatchMarkdownDocument {
  struct Block: Identifiable {
    var id: Int
    var text: AttributedString
    var heading: Int? = nil
    var code = false
    var quote = false
    var divider = false
    var marker: String? = nil
    var listDepth = 0
    var tableRow: Int? = nil
    var tableID: Int? = nil
    var tableColumn = 0
    var tableColumnCount = 0
    var tableHeader = false
  }

  let blocks: [Block]

  init(_ source: String) {
    guard let parsed = try? AttributedString(markdown: source,
      options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)) else {
      blocks = [Block(id: 0, text: AttributedString(source))]
      return
    }
    var result: [Block] = []
    var seenListItems = Set<Int>()
    for run in parsed.runs {
      let components = run.presentationIntent?.components ?? []
      let id = components.first?.identity ?? 0
      var text = AttributedString(parsed[run.range])
      text.presentationIntent = nil
      if let url = run.link, !Self.isWebLink(url) { text.link = nil }
      if result.last?.id == id {
        result[result.count - 1].text.append(text)
        continue
      }
      var block = Block(id: id, text: text)
      var itemID: Int?
      var ordinal: Int?
      var ordered = false
      for component in components {
        switch component.kind {
        case .header(let level): block.heading = level
        case .codeBlock: block.code = true
        case .blockQuote: block.quote = true
        case .thematicBreak: block.divider = true
        case .listItem(let number):
          if itemID == nil { itemID = component.identity; ordinal = number }
          block.listDepth += 1
        case .orderedList:
          if block.listDepth == 1 { ordered = true }
        case .tableHeaderRow: block.tableRow = component.identity; block.tableHeader = true
        case .tableRow: block.tableRow = component.identity
        case .table(let columns): block.tableID = component.identity; block.tableColumnCount = columns.count
        case .tableCell(let column): block.tableColumn = column
        default: break
        }
      }
      if let itemID, seenListItems.insert(itemID).inserted {
        block.marker = ordered ? "\(ordinal ?? 1)." : "•"
      }
      result.append(block)
    }
    // Stack table fields instead of shrinking multiple columns into the watch width.
    var arranged: [Block] = []
    var headers: [Int: [AttributedString]] = [:]
    var index = 0
    while index < result.count {
      var block = result[index]
      guard let rowID = block.tableRow, let tableID = block.tableID else {
        arranged.append(block); index += 1; continue
      }
      var cells = Array(repeating: AttributedString(), count: block.tableColumnCount)
      while index < result.count && result[index].tableRow == rowID {
        let cell = result[index]
        if cell.tableColumn < cells.count { cells[cell.tableColumn] = cell.text }
        index += 1
      }
      block.id = rowID
      block.text = AttributedString()
      if block.tableHeader { headers[tableID] = cells }
      for (column, cell) in cells.enumerated() {
        if column > 0 { block.text.append(AttributedString(block.tableHeader ? " · " : "\n")) }
        if !block.tableHeader, let labels = headers[tableID], column < labels.count {
          var label = labels[column]
          label.inlinePresentationIntent = .stronglyEmphasized
          block.text.append(label)
          block.text.append(AttributedString(": "))
        }
        block.text.append(cell)
      }
      arranged.append(block)
    }
    blocks = arranged
  }

  static func isWebLink(_ url: URL) -> Bool {
    ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false
  }
}
