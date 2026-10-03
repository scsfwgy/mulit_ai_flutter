import Foundation

/// A local launch route shared by the watch app and its complication extension.
/// The extension needs no access to settings, credentials, audio, or chat history.
enum WatchChatShortcut {
  static let kind = "AILinkChatLauncher"

  static var chatURL: URL {
    let scheme = Bundle.main.object(forInfoDictionaryKey: "AILinkWatchURLScheme") as? String ?? "ailink-watch"
    return URL(string: "\(scheme)://chat")!
  }

  static func opensChat(_ url: URL) -> Bool {
    url.scheme == chatURL.scheme && url.host == "chat"
  }
}
