import SwiftUI

@main
struct AILinkWatchApp: App {
  @StateObject private var session = WatchChatSession()

  var body: some Scene {
    WindowGroup {
      WatchContentView(session: session)
    }
  }
}
