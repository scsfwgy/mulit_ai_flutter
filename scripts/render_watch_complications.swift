// Build with WatchComplicationSnapshot.swift and the widget view definitions.
// This renders the actual SwiftUI components; it is not a watchOS screenshot.
import AppKit
import SwiftUI
import WidgetKit

@main
struct RenderWatchComplications {
  @MainActor static func main() throws {
    let states: [WatchComplicationState] = [.replying, .complete, .loadingAudio, .playing]
    let content = VStack(alignment: .leading, spacing: 20) {
      Text("AI Link · 复杂功能").font(.system(size: 24, weight: .bold))
      Text("SwiftUI 布局预览 · 示例回复").font(.system(size: 13)).foregroundStyle(.secondary)
      ForEach(states, id: \.rawValue) { state in
        VStack(alignment: .leading, spacing: 8) {
          Text(state.label(chinese: true)).font(.system(size: 13)).foregroundStyle(.secondary)
          HStack(spacing: 24) {
            ChatComplicationContentView(snapshot: WatchComplicationSnapshot(state: state,
              preview: state == .replying ? "…保持专注，也给自己留一点休息的时间。" : "今天可以先完成最重要的一件事，再安排休息。",
              language: "zh", updatedAt: .now), layout: .rectangular)
              .frame(width: 184, height: 58)
              .padding(10).background(.black, in: RoundedRectangle(cornerRadius: 14))
            ChatComplicationContentView(snapshot: WatchComplicationSnapshot(state: state,
              preview: "", language: "zh", updatedAt: .now), layout: .circular)
              .frame(width: 48, height: 48).background(.black, in: Circle())
          }
        }
      }
    }.padding(24).frame(width: 350, alignment: .leading)
      .foregroundStyle(.white).background(Color(white: 0.08)).environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/ai-link-complications.png"
    try data.write(to: URL(fileURLWithPath: path))
    print(path)
  }
}
