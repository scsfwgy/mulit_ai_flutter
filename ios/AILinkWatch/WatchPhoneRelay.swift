import Foundation
import WatchConnectivity

/// Main-thread continuations correlate each phase, including queued file results.
@MainActor
final class WatchPhoneRelay {
  private struct Pending {
    let continuation: CheckedContinuation<[String: Any], Error>
    let onText: (String) -> Void
    let audio: Bool
  }
  private var pending: [String: Pending] = [:]
  private var files: [WCSessionFileTransfer: URL] = [:]

  func request(_ kind: String, arguments: [String: Any] = [:], audio: Data? = nil,
               onText: @escaping (String) -> Void = { _ in }) async throws -> [String: Any] {
    let session = WCSession.default
    guard session.activationState == .activated, session.isReachable else {
      throw WatchRequestError("手机不可达", "Phone unavailable", retrySafe: true)
    }
    let id = UUID().uuidString.lowercased()
    return try await withTaskCancellationHandler(operation: {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        pending[id] = Pending(continuation: continuation, onText: onText, audio: kind == "remote-tts")
        var message = arguments
        message["id"] = id
        message["kind"] = kind
        message["expiresAt"] = Date().addingTimeInterval(30).timeIntervalSince1970
        do {
          // Histories and recordings can exceed the interactive message size limit.
          if audio != nil || kind == "remote-chat" {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(id).\(audio == nil ? "json" : "wav")")
            try (audio ?? JSONSerialization.data(withJSONObject: message)).write(to: url, options: .atomic)
            files[session.transferFile(url, metadata: ["kind": audio == nil ? "remote-request" : kind,
              "id": id, "expiresAt": message["expiresAt"]!])] = url
          } else {
            session.sendMessage(message, replyHandler: { reply in
              if reply["accepted"] as? Bool != true {
                Task { @MainActor in self.fail(id, WatchRequestError("手机拒绝请求，请同步配置", "Phone rejected request; sync settings")) }
              }
            }, errorHandler: { _ in
              // Delivery status is ambiguous; never automatically resubmit.
              Task { @MainActor in self.fail(id, WatchRequestError("手机响应状态不明，请稍后重试", "Phone delivery status unknown; check before retrying")) }
            })
          }
        } catch { fail(id, WatchRequestError("请求传输失败", "Request transfer failed")) }
        Task { @MainActor in
          try? await Task.sleep(for: .seconds(kind == "remote-asr" ? 90 : 240))
          self.fail(id, WatchRequestError("手机处理超时，状态不明；请稍后检查再重试", "Phone timed out; check before retrying"))
        }
      }
    }, onCancel: {
      Task { @MainActor in self.fail(id, CancellationError()) }
    })
  }

  @discardableResult
  func receive(_ update: [String: Any]) -> Bool {
    guard let id = update["id"] as? String, let request = pending[id] else { return false }
    if let answer = update["answer"] as? String { request.onText(answer) }
    if update["stage"] as? String == "error" {
      fail(id, WatchRequestError(update["error"] as? String ?? "手机请求失败", "Phone request failed; check settings",
        retrySafe: update["retrySafe"] as? Bool == true))
    } else if update["stage"] as? String == "complete" {
      // For TTS, completion means receiving the audio file, not its notification.
      if !request.audio || update["audioURL"] is URL {
        pending.removeValue(forKey: id)?.continuation.resume(returning: update)
      }
    }
    return true
  }

  func finished(_ transfer: WCSessionFileTransfer, error: Error?) {
    if let url = files.removeValue(forKey: transfer) { try? FileManager.default.removeItem(at: url) }
    if error != nil, let id = transfer.file.metadata?["id"] as? String {
      fail(id, WatchRequestError("手机传输失败，状态不明", "Phone transfer failed; delivery status unknown"))
    }
  }

  private func fail(_ id: String, _ error: Error) {
    pending.removeValue(forKey: id)?.continuation.resume(throwing: error)
  }
}
