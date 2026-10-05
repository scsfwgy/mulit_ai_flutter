import SwiftUI

struct WatchMarkdownView: View {
  private let blocks: [WatchMarkdownDocument.Block]

  init(_ source: String) { blocks = WatchMarkdownDocument(source).blocks }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(blocks) { block in
        if block.divider {
          Divider()
        } else {
          HStack(alignment: .top, spacing: 6) {
            if block.quote { Rectangle().fill(.secondary).frame(width: 2) }
            if block.listDepth > 0 {
              Text(block.marker ?? " ").frame(minWidth: 12, alignment: .leading)
            }
            formattedText(block)
              .font(font(block))
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .font(.system(size: 15))
          .padding(.leading, CGFloat(max(0, block.listDepth - 1)) * 10)
          .padding(block.code || block.tableRow != nil ? 6 : 0)
          .background {
            if block.code || block.tableRow != nil {
              RoundedRectangle(cornerRadius: 5).fill(.primary.opacity(0.08))
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func font(_ block: WatchMarkdownDocument.Block) -> Font {
    if block.code { return .system(size: 13, design: .monospaced) }
    if let level = block.heading {
      return .system(size: level == 1 ? 19 : level == 2 ? 17 : 16, weight: .semibold)
    }
    return .system(size: 15, weight: block.tableHeader ? .semibold : .regular)
  }

  private func formattedText(_ block: WatchMarkdownDocument.Block) -> Text {
    var text = block.text
    for run in block.text.runs where run.inlinePresentationIntent?.contains(.code) == true {
      text[run.range].font = .system(size: 13, design: .monospaced)
      text[run.range].backgroundColor = .primary.opacity(0.08)
    }
    return Text(text)
  }
}
