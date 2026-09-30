import Flutter
import UIKit
import WatchConnectivity

/// A headless Flutter engine reuses the app's cloud voice/chat adapters and SQLite store.
/// WatchConnectivity may wake the iPhone while its Flutter scene is not visible.
final class AppleWatchBridge: NSObject, WCSessionDelegate {
  static let shared = AppleWatchBridge()

  private var workerEngine: FlutterEngine?
  private var workerChannel: FlutterMethodChannel?
  private var workerReady = false
  private var pluginsReady = false
  private var pending: [(String, [String: Any])] = []
  private var backgroundTasks: [String: UIBackgroundTaskIdentifier] = [:]
  private var outgoingAudio: [WCSessionFileTransfer: URL] = [:]

  func start() {
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  func attachCompanionChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "between_models/companion_install", binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard WCSession.isSupported() else {
        result(FlutterError(code: "unavailable", message: "Apple Watch unavailable", details: nil))
        return
      }
      let session = WCSession.default
      switch call.method {
      case "syncPreferences":
        guard let arguments = call.arguments as? [String: Any],
              let language = arguments["language"] as? String,
              ["zh", "en"].contains(language) else {
          result(FlutterError(code: "invalid_language", message: "Unsupported language", details: nil))
          return
        }
        UserDefaults.standard.set(language, forKey: "ai_link_watch_language")
        self.syncPreferences()
        result(nil)
      case "watchStatus":
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        result([
          "platform": "apple",
          "connected": paired ? 1 : 0,
          "installed": installed,
          "reachable": session.isReachable,
          "missing": paired && !installed
            ? [["id": "apple-watch", "name": "Apple Watch"]] : [],
        ])
      case "openWatchStore":
        result(FlutterError(
          code: "manual_install",
          message: "Install the watch app from the Watch app on iPhone.", details: nil
        ))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func syncPreferences() {
    let session = WCSession.default
    guard session.activationState == .activated,
          session.isPaired, session.isWatchAppInstalled,
          let language = UserDefaults.standard.string(forKey: "ai_link_watch_language") else { return }
    // The latest context replaces older preferences and can arrive after reconnect.
    try? session.updateApplicationContext(["kind": "preferences", "language": language])
    if session.isReachable {
      session.sendMessage(["kind": "preferences", "language": language], replyHandler: nil)
    }
  }

  private func startWorkerIfNeeded() {
    guard workerEngine == nil else { return }
    let engine = FlutterEngine(name: "AI Link Watch Worker", project: nil, allowHeadlessExecution: true)
    let channel = FlutterMethodChannel(
      name: "between_models/watch_worker", binaryMessenger: engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(FlutterMethodNotImplemented); return }
      switch call.method {
      case "ready":
        self.workerReady = true
        self.flushPending()
        result(nil)
      case "publish":
        if let update = call.arguments as? [String: Any] {
          self.sendUpdate(update)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    workerEngine = engine
    workerChannel = channel
    guard engine.run(withEntrypoint: "watchBackgroundMain") else {
      workerEngine = nil
      workerChannel = nil
      return
    }
    GeneratedPluginRegistrant.register(with: engine)
    pluginsReady = true
    flushPending()
  }

  private func enqueue(id: String, arguments: [String: Any]) {
    DispatchQueue.main.async {
      self.startWorkerIfNeeded()
      self.pending.append((id, arguments))
      self.flushPending()
    }
  }

  private func flushPending() {
    guard workerReady, pluginsReady, let channel = workerChannel else { return }
    let requests = pending
    pending.removeAll()
    for (id, arguments) in requests {
      backgroundTasks[id] = UIApplication.shared.beginBackgroundTask(withName: "AI Link Watch \(id)") {
        self.sendUpdate(["id": id, "stage": "error", "error": "iPhone 后台处理超时，请重试"])
        self.endBackgroundTask(id)
      }
      channel.invokeMethod("process", arguments: arguments) { [weak self] result in
        if let error = result as? FlutterError {
          self?.sendUpdate(["id": id, "stage": "error", "error": error.message ?? "iPhone 处理失败"])
        }
        self?.endBackgroundTask(id)
      }
    }
  }

  private func endBackgroundTask(_ id: String) {
    guard let task = backgroundTasks.removeValue(forKey: id) else { return }
    UIApplication.shared.endBackgroundTask(task)
  }

  private func sendUpdate(_ update: [String: Any]) {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    guard session.activationState == .activated else { return }
    var message = update
    if let answer = message["answer"] as? String, answer.count > 6_000 {
      message["answer"] = String(answer.prefix(6_000)) + "…"
    }
    if let error = message["error"] as? String, error.count > 500 {
      message["error"] = String(error.prefix(500))
    }
    if let audio = message.removeValue(forKey: "audio") as? FlutterStandardTypedData,
       let id = message["id"] as? String {
      let format = message["audioFormat"] as? String == "wav" ? "wav" : "mp3"
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("watch-\(UUID().uuidString).\(format)")
      do {
        try audio.data.write(to: url, options: .atomic)
        let transfer = session.transferFile(url, metadata: ["id": id, "kind": "audio"])
        outgoingAudio[transfer] = url
      } catch {
        try? FileManager.default.removeItem(at: url)
      }
    }
    let stage = message["stage"] as? String ?? ""
    let shouldQueue = ["complete", "error", "awaiting_confirmation"].contains(stage)
    if session.isReachable {
      session.sendMessage(message, replyHandler: nil) { _ in
        if shouldQueue { session.transferUserInfo(message) }
      }
    } else if shouldQueue {
      session.transferUserInfo(message)
    }
  }

  func session(
    _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
    error: Error?
  ) {
    DispatchQueue.main.async { self.syncPreferences() }
  }

  func sessionWatchStateDidChange(_ session: WCSession) {
    DispatchQueue.main.async { self.syncPreferences() }
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    DispatchQueue.main.async { self.syncPreferences() }
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) { session.activate() }

  func session(_ session: WCSession, didReceive file: WCSessionFile) {
    guard file.metadata?["kind"] as? String == "audio",
          let id = file.metadata?["id"] as? String else { return }
    guard let audio = try? Data(contentsOf: file.fileURL),
          !audio.isEmpty, audio.count <= 4 * 1024 * 1024 else {
      DispatchQueue.main.async {
        self.sendUpdate(["id": id, "stage": "error", "error": "录音无效或超过 4 MB"])
      }
      return
    }
    enqueue(id: id, arguments: [
      "id": id, "kind": "audio", "audio": FlutterStandardTypedData(bytes: audio),
    ])
  }

  func session(
    _ session: WCSession, didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    guard message["kind"] as? String == "confirm",
          let id = message["id"] as? String,
          let transcript = message["transcript"] as? String,
          !transcript.isEmpty, transcript.count <= 5000 else {
      replyHandler(["accepted": false])
      return
    }
    enqueue(id: id, arguments: ["id": id, "kind": "confirm", "transcript": transcript])
    replyHandler(["accepted": true])
  }

  func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
    DispatchQueue.main.async {
      guard let url = self.outgoingAudio.removeValue(forKey: fileTransfer) else { return }
      try? FileManager.default.removeItem(at: url)
    }
  }
}
