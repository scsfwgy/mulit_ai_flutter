import SwiftUI
import WidgetKit

struct ChatLauncherEntry: TimelineEntry {
  let date: Date
  let snapshot: WatchComplicationSnapshot
}

struct ChatLauncherProvider: TimelineProvider {
  func placeholder(in context: Context) -> ChatLauncherEntry { sample }

  func getSnapshot(in context: Context, completion: @escaping (ChatLauncherEntry) -> Void) {
    completion(context.isPreview ? sample : entry)
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<ChatLauncherEntry>) -> Void) {
    let current = entry
    var entries = [current]
    // Expire a transient state even if the app is suspended or killed.
    if let expiry = current.snapshot.expiresAt, expiry > current.date {
      entries.append(ChatLauncherEntry(date: expiry, snapshot: current.snapshot.display(at: expiry)))
    }
    completion(Timeline(entries: entries, policy: .never))
  }

  private var entry: ChatLauncherEntry {
    let date = Date()
    let snapshot = (WatchComplicationStore().load() ?? .empty).display(at: date)
    return ChatLauncherEntry(date: date, snapshot: snapshot)
  }

  private var sample: ChatLauncherEntry {
    ChatLauncherEntry(date: .now, snapshot: WatchComplicationSnapshot(state: .complete,
      preview: "抬起手腕查看最新回复，点按打开完整聊天。", language: "zh", updatedAt: .now))
  }
}

struct ChatLauncherView: View {
  @Environment(\.widgetFamily) private var family
  let snapshot: WatchComplicationSnapshot

  var body: some View {
    ChatComplicationContentView(snapshot: snapshot, layout: layout)
      .widgetURL(WatchChatShortcut.chatURL)
      .containerBackground(.fill.tertiary, for: .widget)
      .accessibilityLabel("AI Link, \(snapshot.label)")
  }

  private var layout: WatchComplicationLayout {
    switch family {
    case .accessoryRectangular: return .rectangular
    case .accessoryInline: return .inline
    default: return .circular
    }
  }
}

enum WatchComplicationLayout { case rectangular, inline, circular }

/// Kept separate from the widget host so the exact layout can be rendered locally.
struct ChatComplicationContentView: View {
  let snapshot: WatchComplicationSnapshot
  let layout: WatchComplicationLayout

  @ViewBuilder var body: some View {
    switch layout {
    case .rectangular:
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 4) {
          Image(systemName: snapshot.state.symbol).widgetAccentable()
          Text(snapshot.label).lineLimit(1).minimumScaleFactor(0.8)
          Spacer(minLength: 2)
          Text(verbatim: "AI Link").fontWeight(.semibold)
        }.font(.system(size: 11))
        Text(snapshot.preview.isEmpty
          ? (snapshot.chinese ? "点按打开聊天" : "Tap to open chat") : snapshot.preview)
          .font(.system(size: 13, weight: .medium))
          .lineLimit(2).multilineTextAlignment(.leading)
          .truncationMode(snapshot.state == .replying ? .head : .tail)
          .frame(maxWidth: .infinity, alignment: .leading)
          .privacySensitive()
      }
    case .inline:
      Label(snapshot.state == .idle ? "AI Link" : snapshot.label, systemImage: snapshot.state.symbol)
    case .circular:
      ZStack {
        AccessoryWidgetBackground()
        Image(systemName: snapshot.state.symbol)
          .font(.system(size: 24, weight: .semibold)).widgetAccentable()
      }
    }
  }
}

@main
struct AILinkWatchWidgets: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: WatchChatShortcut.kind, provider: ChatLauncherProvider()) { entry in
      ChatLauncherView(snapshot: entry.snapshot)
    }
    .configurationDisplayName("AI Link")
    .description("AI Link")
    .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

#Preview(as: .accessoryCircular) {
  AILinkWatchWidgets()
} timeline: {
  ChatLauncherEntry(date: .now, snapshot: .empty)
}

#Preview(as: .accessoryRectangular) {
  AILinkWatchWidgets()
} timeline: {
  ChatLauncherEntry(date: .now, snapshot: WatchComplicationSnapshot(state: .replying,
    preview: "先完成最重要的一件事，再给自己留一点休息时间。", language: "zh", updatedAt: .now))
}
