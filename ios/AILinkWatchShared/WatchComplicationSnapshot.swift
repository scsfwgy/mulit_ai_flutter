import Foundation
import Security

enum WatchComplicationState: String, Codable {
  case idle, recording, transcribing, confirming, thinking, replying, complete
  case loadingAudio, playing, failed, unknown

  var symbol: String {
    switch self {
    case .idle: return "mic.fill"
    case .recording: return "waveform"
    case .transcribing: return "text.bubble"
    case .confirming: return "paperplane"
    case .thinking: return "ellipsis.bubble"
    case .replying: return "text.bubble.fill"
    case .complete: return "checkmark.bubble.fill"
    case .loadingAudio: return "hourglass"
    case .playing: return "speaker.wave.2.fill"
    case .failed: return "exclamationmark.bubble"
    case .unknown: return "arrow.up.forward.app"
    }
  }

  var isActive: Bool {
    ![.idle, .complete, .failed, .unknown].contains(self)
  }

  func label(chinese: Bool) -> String {
    let labels: (String, String)
    switch self {
    case .idle: labels = ("准备就绪", "Ready")
    case .recording: labels = ("录音中", "Recording")
    case .transcribing: labels = ("语音识别中", "Transcribing")
    case .confirming: labels = ("等待确认", "Confirm to send")
    case .thinking: labels = ("正在思考", "Thinking")
    case .replying: labels = ("正在回答", "Answering")
    case .complete: labels = ("回答完成", "Reply ready")
    case .loadingAudio: labels = ("语音加载中", "Loading audio")
    case .playing: labels = ("语音播放中", "Playing audio")
    case .failed: labels = ("请求未完成", "Request failed")
    case .unknown: labels = ("打开查看状态", "Open for status")
    }
    return chinese ? labels.0 : labels.1
  }
}

/// Only a bounded display preview crosses into the widget's dedicated group.
struct WatchComplicationSnapshot: Codable, Equatable {
  var state: WatchComplicationState
  var preview: String
  var language: String
  var updatedAt: Date

  static var empty: Self { Self(state: .idle, preview: "", language: "zh", updatedAt: .now) }
  var chinese: Bool { language != "en" }
  var label: String { state.label(chinese: chinese) }
  var expiresAt: Date? {
    guard state.isActive else { return nil }
    return updatedAt.addingTimeInterval(state == .playing ? 900 : 180)
  }

  func display(at date: Date) -> Self {
    guard let expiry = expiresAt, date >= expiry else { return self }
    var value = self
    value.state = .unknown
    return value
  }

  static func make(phase: String, recording: Bool, loadingAudio: Bool, playing: Bool,
                   confirming: Bool, question: String, answer: String, lastAnswer: String, language: String,
                   secrets: [String] = [], date: Date = .now) -> Self {
    let state: WatchComplicationState
    if recording { state = .recording }
    else if loadingAudio { state = .loadingAudio }
    else if playing { state = .playing }
    else if confirming { state = .confirming }
    else {
      switch phase {
      case "transcribing": state = .transcribing
      case "thinking": state = .thinking
      case "replying": state = .replying
      case "complete": state = .complete
      case "error": state = .failed
      default: state = lastAnswer.isEmpty ? .idle : .complete
      }
    }
    let text: String
    if state == .thinking && answer.isEmpty { text = question }
    else { text = answer.isEmpty && state == .complete ? lastAnswer : answer }
    return Self(state: state, preview: excerpt(text, tail: state == .replying, secrets: secrets),
                language: language, updatedAt: date)
  }

  static func excerpt(_ text: String, tail: Bool, secrets: [String]) -> String {
    var clean = text
    // Redact before truncation so clipping cannot expose a partial known key.
    for secret in secrets.filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
      clean = clean.replacingOccurrences(of: secret, with: "•••")
    }
    clean = clean.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
      .replacingOccurrences(of: #"[`*#>_]"#, with: "", options: .regularExpression)
      .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    let limit = 140
    if clean.count <= limit { return clean }
    return tail ? "…" + String(clean.suffix(limit)) : String(clean.prefix(limit)) + "…"
  }
}

struct WatchComplicationStore {
  private var query: [String: Any]? {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "AILinkWidgetKeychainGroup") as? String,
          !group.isEmpty, !group.contains("$(") else { return nil }
    return [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ai_link_widget_snapshot_v1",
            kSecAttrAccount as String: "latest", kSecAttrAccessGroup as String: group,
            kSecAttrSynchronizable as String: false]
  }

  func load() -> WatchComplicationSnapshot? {
    guard var query else { return nil }
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data, data.count < 8192 else { return nil }
    return try? JSONDecoder().decode(WatchComplicationSnapshot.self, from: data)
  }

  @discardableResult func save(_ snapshot: WatchComplicationSnapshot) -> Bool {
    guard let query, let data = try? JSONEncoder().encode(snapshot), data.count < 8192 else { return false }
    let attributes: [String: Any] = [kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
    let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if result == errSecItemNotFound {
      return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
    }
    return result == errSecSuccess
  }
}
