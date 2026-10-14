import Foundation
import Security

struct WatchVoiceConfiguration: Codable {
  var providerName: String? = nil
  let protocolName: String
  let baseUrl: String
  let apiKey: String
  let asrModel: String
  let ttsModel: String
  let voice: String

  enum CodingKeys: String, CodingKey {
    case protocolName = "protocol"
    case providerName, baseUrl, apiKey, asrModel, ttsModel, voice
  }
}

struct WatchSearchConfiguration: Codable {
  let id: String
  let name: String
  let service: String
  let endpoint: String
  let apiKey: String?
  let maxResults: Int
  let detailed: Bool
  let timeRange: String

  var serviceLabel: String { service == "bocha" ? "Bocha" : service == "tavily" ? "Tavily" : service == "exa" ? "Exa" : service }
}

struct WatchNetworkConfiguration: Codable {
  let version: Int
  let providerId: Int?
  let providerName: String
  let providerPresetId: String?
  let protocolName: String?
  let baseUrl: String?
  let apiKey: String?
  let model: String
  let systemPrompt: String?
  let textReady: Bool
  let asrReady: Bool
  let asr: WatchVoiceConfiguration?
  let tts: WatchVoiceConfiguration?
  var systemAsr: Bool? = nil
  var systemTts: Bool? = nil
  var systemVoiceIdentifier: String? = nil
  var openAIRestricted: Bool? = nil
  var searchEnabled: Bool? = nil
  var search: WatchSearchConfiguration? = nil

  enum CodingKeys: String, CodingKey {
    case protocolName = "protocol"
    case version, providerId, providerName, providerPresetId, baseUrl, apiKey
    case model, systemPrompt, textReady, asrReady, asr, tts, systemAsr, systemTts, systemVoiceIdentifier, openAIRestricted, searchEnabled, search
  }

  static func endpoint(_ base: String, _ suffix: String) throws -> URL {
    guard let root = URLComponents(string: base), let host = root.host, !host.isEmpty,
          root.user == nil, root.password == nil, root.query == nil, root.fragment == nil,
          root.scheme == "https" || (root.scheme == "http" && ["localhost", "127.0.0.1", "10.0.2.2"].contains(host)),
          let result = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + suffix)
    else { throw WatchRequestError("服务地址无效，请在手机重新配置", "Invalid service URL; update settings on iPhone") }
    return result
  }

  static func isOpenAI(_ endpoint: String, presetID: String? = nil, model: String? = nil) -> Bool {
    let id = (model ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if id.hasPrefix("openai/") || id.hasPrefix("~openai/") { return true }
    if presetID?.lowercased() == "openai" { return true }
    let host = URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))?.host?
      .lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) ?? ""
    return host == "openai.com" || host.hasSuffix(".openai.com")
  }

  func blocks(_ endpoint: String, presetID: String? = nil, model: String? = nil) -> Bool {
    openAIRestricted != false && Self.isOpenAI(endpoint, presetID: presetID, model: model)
  }

  var canChat: Bool {
    !blocks(baseUrl ?? "", presetID: providerPresetId, model: model) && textReady && providerId != nil && !(apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !model.isEmpty && model.utf16.count <= 500 && providerName.utf16.count <= 200
      && ["openai_chat", "anthropic_messages"].contains(protocolName ?? "")
      && (try? Self.endpoint(baseUrl ?? "", "/")) != nil
  }

  var canTranscribe: Bool {
    guard asrReady, let voice = asr else { return false }
    return !blocks(voice.baseUrl, model: voice.asrModel) && !voice.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !voice.asrModel.isEmpty
      && ["openAi", "mimo", "doubao"].contains(voice.protocolName)
      && (try? Self.endpoint(voice.baseUrl, "/")) != nil
  }

  var fingerprint: String { "\(providerId ?? -1)|\(protocolName ?? "")|\(baseUrl ?? "")|\(model)" }
}

/// Only Keychain persists the configuration containing selected API credentials.
/// ThisDeviceOnly avoids iCloud Keychain and backup migration to another device.
final class WatchConfigurationStore {
  private let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "ai_link_watch_services_v1",
    kSecAttrAccount as String: "selected-services",
    kSecAttrSynchronizable as String: false,
  ]

  func load() -> WatchNetworkConfiguration? {
    var request = query
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data else { return nil }
    return try? JSONDecoder().decode(WatchNetworkConfiguration.self, from: data)
  }

  func clear() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw WatchRequestError("无法清除安全配置，请解锁后重试", "Could not clear secure settings; unlock and retry")
    }
  }

  func save(_ snapshot: [String: Any]) throws -> WatchNetworkConfiguration {
    let data = try JSONSerialization.data(withJSONObject: snapshot)
    guard data.count <= 60_000 else {
      throw WatchRequestError("手表配置过大", "Watch settings are too large")
    }
    let config = try JSONDecoder().decode(WatchNetworkConfiguration.self, from: data)
    guard config.version == 1 else {
      throw WatchRequestError("请更新手机与手表应用", "Update both phone and watch apps")
    }
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
    }
    guard status == errSecSuccess else {
      throw WatchRequestError("无法安全保存手表配置，请解锁后重试", "Could not save watch settings securely; unlock and retry")
    }
    return config
  }
}

struct WatchRequestError: Error {
  let chinese: String
  let english: String
  let retrySafe: Bool

  init(_ chinese: String, _ english: String, retrySafe: Bool = false) {
    self.chinese = chinese
    self.english = english
    self.retrySafe = retrySafe
  }

  static func network(_ error: Error) -> WatchRequestError {
    if let known = error as? WatchRequestError { return known }
    let source = error as NSError
    let safeCodes: [Int] = [NSURLErrorNotConnectedToInternet, NSURLErrorCannotFindHost,
      NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed, NSURLErrorDataNotAllowed,
      NSURLErrorInternationalRoamingOff]
    let safe = source.domain == NSURLErrorDomain && safeCodes.contains(source.code)
    if source.domain == NSURLErrorDomain && source.code == NSURLErrorTimedOut {
      return WatchRequestError("请求超时，状态不明；请稍后检查再重试", "Request timed out; check the result before retrying")
    }
    return WatchRequestError("请求失败，请检查网络和服务配置", "Request failed; check network and service settings", retrySafe: safe)
  }
}

/// Coalesce automatic triggers; a manual sync always starts a fresh request.
/// Keep retired IDs so late callbacks cannot overwrite a newer configuration.
struct WatchSettingsSync {
  private(set) var requestID: String?
  private(set) var pendingActivation = false
  private var retiredIDs: Set<String> = []

  mutating func begin(manual: Bool) -> String? {
    guard manual || requestID == nil else { return nil }
    if let old = requestID { retiredIDs.insert(old) }
    let id = UUID().uuidString
    requestID = id
    pendingActivation = true
    return id
  }

  mutating func takePending() -> String? {
    guard pendingActivation else { return nil }
    pendingActivation = false
    return requestID
  }

  mutating func finish(_ id: String, success: Bool) -> Bool {
    guard id == requestID else { return false }
    if !success { retiredIDs.insert(id) }
    requestID = nil
    pendingActivation = false
    return true
  }

  func accepts(_ id: String?) -> Bool { id.map { !retiredIDs.contains($0) } ?? true }
}

/// Watch first, with at most one safe fallback to the paired phone.
enum WatchRequestRouting {
  @MainActor
  static func execute<T>(phoneAvailable: @escaping () -> Bool, hasPartial: @escaping () -> Bool,
                         onRoute: (Bool) -> Void, phone: () async throws -> T,
                         watch: () async throws -> T) async throws -> T {
    onRoute(false)
    do { return try await watch() }
    catch {
      let failure = WatchRequestError.network(error)
      guard failure.retrySafe, !hasPartial(), phoneAvailable() else { throw failure }
      onRoute(true)
      return try await phone()
    }
  }
}

struct WatchSyncTurn: Codable, Identifiable {
  let id: String
  let conversationId: String
  let sequence: Int
  let createdAt: Int64
  let providerId: Int?
  let providerName: String
  let providerPresetId: String?
  let model: String
  let transcript: String
  let answer: String
  var source: String? = "apple-watch"
}

/// Pending turns are separate from the 50 display turns and survive reconnects.
final class WatchHistoryStore {
  struct Snapshot: Codable {
    var fingerprint = ""
    var conversationId = UUID().uuidString.lowercased()
    var sequence = 0
    var recent: [WatchSyncTurn] = []
    var pending: [WatchSyncTurn] = []
  }
  private let defaults: UserDefaults
  private let key = "ai_link_watch_independent_history_v1"
  private(set) var snapshot: Snapshot

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    snapshot = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? Snapshot()
  }

  func history(for config: WatchNetworkConfiguration, question: String) -> [[String: String]] {
    let previous = snapshot.fingerprint == config.fingerprint
      ? snapshot.recent.filter { $0.conversationId == snapshot.conversationId }.suffix(12) : []
    return previous.flatMap { [["role": "user", "content": $0.transcript],
                              ["role": "assistant", "content": $0.answer]] }
      + [["role": "user", "content": question]]
  }

  func append(id: String, config: WatchNetworkConfiguration, question: String, answer: String) throws {
    guard !snapshot.recent.contains(where: { $0.id == id }) else { return }
    guard snapshot.pending.count < 100 else {
      throw WatchRequestError("请先连接手机同步已有问答", "Reconnect iPhone to sync pending chats first")
    }
    if snapshot.fingerprint != config.fingerprint {
      snapshot.fingerprint = config.fingerprint
      snapshot.conversationId = UUID().uuidString.lowercased()
      snapshot.sequence = 0
    }
    let turn = WatchSyncTurn(id: id.lowercased(), conversationId: snapshot.conversationId,
      sequence: snapshot.sequence, createdAt: Int64(Date().timeIntervalSince1970 * 1000),
      providerId: config.providerId, providerName: config.providerName,
      providerPresetId: config.providerPresetId, model: config.model, transcript: question, answer: answer)
    snapshot.sequence += 1
    snapshot.recent = Array((snapshot.recent + [turn]).suffix(50))
    snapshot.pending.append(turn)
    persist()
  }

  func acknowledge(_ id: String) {
    snapshot.pending.removeAll { $0.id == id }
    persist()
  }

  func startNewTopic() {
    snapshot.conversationId = UUID().uuidString.lowercased()
    snapshot.sequence = 0
    snapshot.recent = []
    // Older conversations must still reach the phone after an offline reset.
    persist()
  }

  func clear() { snapshot = Snapshot(); defaults.removeObject(forKey: key) }

  private func persist() {
    if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: key) }
  }
}
