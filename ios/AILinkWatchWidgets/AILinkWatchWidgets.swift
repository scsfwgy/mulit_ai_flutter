import SwiftUI
import WidgetKit

struct ChatLauncherEntry: TimelineEntry {
  let date: Date
}

struct ChatLauncherProvider: TimelineProvider {
  func placeholder(in context: Context) -> ChatLauncherEntry { entry }

  func getSnapshot(in context: Context, completion: @escaping (ChatLauncherEntry) -> Void) {
    completion(entry)
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<ChatLauncherEntry>) -> Void) {
    // The launcher has no changing data or network requests.
    completion(Timeline(entries: [entry], policy: .never))
  }

  private var entry: ChatLauncherEntry {
    ChatLauncherEntry(date: Date())
  }
}

struct ChatLauncherView: View {
  @Environment(\.widgetFamily) private var family

  var body: some View {
    content
      .widgetURL(WatchChatShortcut.chatURL)
      .containerBackground(.fill.tertiary, for: .widget)
      .accessibilityLabel("AI Link")
  }

  @ViewBuilder private var content: some View {
    switch family {
    case .accessoryRectangular:
      HStack(spacing: 8) {
        Image(systemName: "mic.fill")
          .font(.title2).widgetAccentable()
        Text(verbatim: "AI Link").font(.headline).widgetAccentable()
          .lineLimit(1).minimumScaleFactor(0.75)
        Spacer(minLength: 0)
      }
    case .accessoryInline:
      Label("AI Link", systemImage: "mic.fill")
    default:
      ZStack {
        AccessoryWidgetBackground()
        Image(systemName: "mic.fill")
          .font(.system(size: 24, weight: .semibold)).widgetAccentable()
      }
    }
  }
}

@main
struct AILinkWatchWidgets: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: WatchChatShortcut.kind, provider: ChatLauncherProvider()) { _ in
      ChatLauncherView()
    }
    .configurationDisplayName("AI Link")
    .description("AI Link")
    .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

#Preview(as: .accessoryCircular) {
  AILinkWatchWidgets()
} timeline: {
  ChatLauncherEntry(date: .now)
}

#Preview(as: .accessoryRectangular) {
  AILinkWatchWidgets()
} timeline: {
  ChatLauncherEntry(date: .now)
}
