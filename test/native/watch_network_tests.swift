import Foundation

@main
struct WatchNetworkTests {
  @MainActor static func main() async throws {
    let base = ProcessInfo.processInfo.environment["WATCH_TEST_URL"]!
    func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
      if !value() { throw NSError(domain: message, code: 1) }
    }
    func config(model: String = "chat", protocolName: String = "openai_chat", voice: String = "openAi", search: WatchSearchConfiguration? = nil, searchEnabled: Bool? = nil) -> WatchNetworkConfiguration {
      let speech = WatchVoiceConfiguration(protocolName: voice, baseUrl: base,
        apiKey: "watch-test-key", asrModel: "asr", ttsModel: "tts", voice: "voice")
      return WatchNetworkConfiguration(version: 1, providerId: 7, providerName: "Test", providerPresetId: nil,
        protocolName: protocolName, baseUrl: base, apiKey: "watch-test-key", model: model,
        systemPrompt: "system", textReady: true, asrReady: true, asr: speech, tts: speech, searchEnabled: searchEnabled, search: search)
    }
    let client = WatchNetworkClient()
    defer { client.close() }
    let history = [["role": "user", "content": "question"]]
    for proto in ["openai_chat", "anthropic_messages"] {
      var partial = ""
      let answer = try await client.reply(history: history, config: config(protocolName: proto)) { partial = $0 }
      try expect(answer == "你好👋" && partial == answer, "streamed Unicode reply")
    }
    for service in ["bocha", "tavily", "exa"] {
      let search = WatchSearchConfiguration(id: "search", name: "Search", service: service,
        endpoint: base + "/search/" + service, apiKey: "watch-search-key", maxResults: 3, detailed: true, timeRange: "week")
      for proto in ["openai_chat", "anthropic_messages"] {
        let answer = try await client.reply(history: history, config: config(model: "grounded", protocolName: proto,
          search: search, searchEnabled: true)) { _ in }
        try expect(answer == "你好👋", "grounded answer for \(service) / \(proto)")
      }
    }
    for failure in ["redirect", "rejected", "empty", "huge"] {
      let search = WatchSearchConfiguration(id: "search", name: "Search", service: "tavily",
        endpoint: base + "/search/" + failure, apiKey: "watch-search-key", maxResults: 3, detailed: true, timeRange: "week")
      do {
        _ = try await client.reply(history: history, config: config(model: "grounded", search: search, searchEnabled: true)) { _ in }
        throw NSError(domain: "failed search reached model", code: 1)
      } catch let error as WatchRequestError {
        try expect(!error.retrySafe && !error.chinese.contains("watch-search-key"), "no automatic retry or credential leak on search failure")
      }
    }
    let oldSnapshot = try JSONEncoder().encode(config())
    let oldConfig = try JSONDecoder().decode(WatchNetworkConfiguration.self, from: oldSnapshot)
    try expect(oldConfig.searchEnabled == nil && oldConfig.search == nil, "old snapshots default to search off")
    for proto in ["openAi", "mimo", "doubao"] {
      let c = config(voice: proto)
      let transcript = try await client.transcribe(Data([82, 73, 70, 70]), config: c)
      try expect(transcript == "hello", "transcription \(proto)")
      let audio = try await client.synthesize("hello", config: c)
      try expect(audio?.0 == Data("audio".utf8), "synthesis \(proto)")
    }
    for model in ["truncated", "rejected", "redirect"] {
      do {
        _ = try await client.reply(history: history, config: config(model: model)) { _ in }
        throw NSError(domain: "must reject \(model)", code: 1)
      } catch let error as WatchRequestError {
        try expect(!error.retrySafe, "must not retry \(model)")
        try expect(!error.chinese.contains("watch-test-key"), "no credential in error")
      }
    }
    var phoneCalls = 0, watchCalls = 0
    var routes: [Bool] = []
    let safe = WatchRequestError("offline", "offline", retrySafe: true)
    let value: String = try await WatchRequestRouting.execute(phoneAvailable: { true }, hasPartial: { false },
      onRoute: { routes.append($0) }, phone: { phoneCalls += 1; return "phone" }, watch: { watchCalls += 1; return "watch" })
    try expect(value == "watch" && phoneCalls == 0 && watchCalls == 1 && routes == [false],
      "reachable phone must not override usable watch network")
    watchCalls = 0; routes = []
    let fallback: String = try await WatchRequestRouting.execute(phoneAvailable: { true }, hasPartial: { false },
      onRoute: { routes.append($0) }, phone: { phoneCalls += 1; return "phone" }, watch: { watchCalls += 1; throw safe })
    try expect(fallback == "phone" && phoneCalls == 1 && watchCalls == 1 && routes == [false, true],
      "watch failure falls back to phone once")
    for failure in [safe, WatchRequestError.network(URLError(.timedOut)), WatchRequestError("HTTP 401", "HTTP 401")] {
      for partial in [false, true] {
        phoneCalls = 0
        let unavailable = failure.retrySafe && !partial
        do {
          let _: String = try await WatchRequestRouting.execute(phoneAvailable: { !unavailable }, hasPartial: { partial },
            onRoute: { _ in }, phone: { phoneCalls += 1; return "wrong" }, watch: { throw failure })
          throw NSError(domain: "unsafe retry", code: 1)
        } catch is WatchRequestError { try expect(phoneCalls == 0, "timeout/partial/service error/offline phone must not switch") }
      }
    }
    var reachable = false
    phoneCalls = 0
    let recovered: String = try await WatchRequestRouting.execute(phoneAvailable: { reachable }, hasPartial: { false },
      onRoute: { _ in }, phone: { phoneCalls += 1; return "phone" }, watch: { reachable = true; throw safe })
    try expect(recovered == "phone" && phoneCalls == 1, "watch failure after phone reconnect")
    watchCalls = 0; phoneCalls = 0
    do {
      let _: String = try await WatchRequestRouting.execute(phoneAvailable: { true }, hasPartial: { false },
        onRoute: { _ in }, phone: { phoneCalls += 1; throw safe }, watch: { watchCalls += 1; throw safe })
      throw NSError(domain: "must fail after fallback", code: 1)
    } catch is WatchRequestError { try expect(watchCalls == 1 && phoneCalls == 1, "failed phone fallback must not bounce to watch") }
    var settingsSync = WatchSettingsSync()
    let startupID = settingsSync.begin(manual: false)!
    try expect(settingsSync.pendingActivation && settingsSync.requestID == startupID, "cold launch waits for activation")
    try expect(settingsSync.begin(manual: false) == nil, "coalesce launch and foreground triggers")
    try expect(settingsSync.takePending() == startupID && settingsSync.takePending() == nil, "send once after activation")
    let manualID = settingsSync.begin(manual: true)!
    try expect(manualID != startupID && settingsSync.takePending() == manualID, "manual sync immediately starts a new request")
    try expect(!settingsSync.accepts(startupID) && !settingsSync.finish(startupID, success: true), "ignore superseded callbacks")
    try expect(settingsSync.requestID == manualID, "stale completion cannot end manual sync")
    try expect(settingsSync.finish(manualID, success: false) && !settingsSync.accepts(manualID), "ignore late response after failure")
    let nextID = settingsSync.begin(manual: true)!
    try expect(settingsSync.accepts(nextID) && settingsSync.finish(nextID, success: true), "fresh manual retry succeeds")
    try expect(settingsSync.requestID == nil && !settingsSync.pendingActivation, "success finishes sync")
    try expect(settingsSync.begin(manual: false) != nil, "next activation attempts sync again")
    let defaults = UserDefaults(suiteName: "ai-link-watch-test-\(UUID().uuidString)")!
    let store = WatchHistoryStore(defaults: defaults)
    let id = UUID().uuidString.lowercased()
    try store.append(id: id, config: config(), question: "q", answer: "a")
    try store.append(id: id, config: config(), question: "q", answer: "a")
    try expect(store.snapshot.pending.count == 1 && store.snapshot.sequence == 1, "deduplicate outbox")
    let restored = WatchHistoryStore(defaults: defaults)
    try expect(restored.snapshot.pending.first?.id == id, "persist pending until ack")
    restored.acknowledge(id)
    try expect(restored.snapshot.pending.isEmpty && restored.history(for: config(), question: "next").count == 3,
      "ack clears outbox and retains context")
    try restored.append(id: UUID().uuidString.lowercased(), config: config(model: "other"), question: "new", answer: "a")
    try expect(restored.snapshot.sequence == 1 && restored.snapshot.pending.first?.sequence == 0,
      "new model starts separate conversation")
    let oldConversation = restored.snapshot.conversationId
    let pendingID = restored.snapshot.pending.first!.id
    restored.startNewTopic()
    let newTopic = WatchHistoryStore(defaults: defaults)
    try expect(newTopic.snapshot.conversationId != oldConversation && newTopic.snapshot.sequence == 0,
      "new topic persists a fresh conversation ID and sequence")
    try expect(newTopic.snapshot.recent.isEmpty && newTopic.snapshot.pending.first?.id == pendingID,
      "new topic clears display but preserves offline outbox")
    try expect(newTopic.history(for: config(model: "other"), question: "next").count == 1,
      "new topic excludes previous model context")
    try newTopic.append(id: UUID().uuidString.lowercased(), config: config(model: "other"), question: "next", answer: "a")
    try expect(newTopic.snapshot.pending.count == 2 && newTopic.snapshot.pending.last?.sequence == 0
      && newTopic.snapshot.pending.last?.conversationId == newTopic.snapshot.conversationId,
      "old and new topics keep separate phone history with independent sequence")
    newTopic.acknowledge(pendingID)
    try expect(newTopic.snapshot.pending.count == 1 && newTopic.snapshot.recent.count == 1,
      "late old topic acknowledgement leaves new topic intact")
    let saved = String(decoding: defaults.data(forKey: "ai_link_watch_independent_history_v1")!, as: UTF8.self)
    try expect(!saved.contains("watch-test-key") && !saved.contains("apiKey"), "history contains no credentials")
    restored.clear()
    for bad in ["http://example.com", "https://user:key@example.com", "https://example.com?x=y"] {
      do { _ = try WatchNetworkConfiguration.endpoint(bad, "/chat"); throw NSError(domain: "unsafe URL", code: 1) }
      catch is WatchRequestError {}
    }
    print("PASS: native protocols, routing, startup/manual sync, redirects, truncated streams, outbox and credential isolation")
  }
}
