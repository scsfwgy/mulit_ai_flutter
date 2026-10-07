import Flutter
import UIKit
import WatchConnectivity

/// A headless Flutter engine reuses the app's cloud voice/chat adapters and SQLite store.
/// WatchConnectivity may wake the iPhone while its Flutter scene is not visible.
final class AppleWatchBridge: NSObject, WCSessionDelegate {
  static let shared = AppleWatchBridge()

  private var pendingConfiguration: [String: Any]?
  private var workerEngine: FlutterEngine?
  private var workerChannel: FlutterMethodChannel?
  private var workerReady = false
  private var pluginsReady = false
  private var pending: [(String, [String: Any])] = []
  private var backgroundTasks: [String: UIBackgroundTaskIdentifier] = [:]
  private var outgoingAudio: [WCSessionFileTransfer: URL] = [:]
  private var phoneUpdates: FlutterMethodChannel?
  private var processingIDs: Set<String> = []
  private var receivedRequests: Set<String> = []
  private var purchaseSyncTask: Task<Void, Never>?
  private var purchaseSyncAgain = false
  private var purchaseSnapshot: [String: Any]?

  func start() {
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  func attachCompanionChannel(messenger: FlutterBinaryMessenger) {
    let updates = FlutterMethodChannel(name: "between_models/watch_updates", binaryMessenger: messenger)
    updates.setMethodCallHandler { [weak self] call, result in
      if call.method == "isProcessing" { result(!(self?.processingIDs.isEmpty ?? true)) }
      else { result(FlutterMethodNotImplemented) }
    }
    phoneUpdates = updates
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
      case "syncConfiguration":
        guard let arguments = call.arguments as? [String: Any],
              let config = arguments["configuration"] as? [String: Any],
              config["version"] as? Int == 1,
              let data = try? JSONSerialization.data(withJSONObject: config), data.count <= 60_000 else {
          result(FlutterError(code: "bad_config", message: "Invalid watch configuration", details: nil))
          return
        }
        self.pendingConfiguration = config
        self.sendPendingConfiguration()
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

  private func sendPendingConfiguration() {
    let session = WCSession.default
    guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
          let config = pendingConfiguration else { return }
    pendingConfiguration = nil
    sendUpdate(["kind": "preferences", "configuration": config,
      "textReady": config["textReady"] ?? false, "asrReady": config["asrReady"] ?? false,
      "speak": config["speak"] ?? false, "autoSend": config["autoSend"] ?? true])
  }

  private func syncPreferences() {
    let session = WCSession.default
    guard session.activationState == .activated,
          session.isPaired, session.isWatchAppInstalled,
          let language = UserDefaults.standard.string(forKey: "ai_link_watch_language") else { return }
    if UserDefaults.standard.bool(forKey: "ai_link_watch_independent") {
      let id = UUID().uuidString
      enqueue(id: id, arguments: ["id": id, "kind": "apple-configuration"])
      return
    }
    // Preserve display metadata when refreshing the phone's language.
    var preferences = UserDefaults.standard.dictionary(forKey: "ai_link_watch_preferences") ?? [:]
    preferences["kind"] = "preferences"
    preferences["language"] = language
    preferences["purchases"] = purchaseSnapshot
    try? session.updateApplicationContext(preferences)
    if session.isReachable {
      session.sendMessage(preferences, replyHandler: nil)
    }
  }

  @MainActor
  func syncPurchases() {
    guard WCSession.isSupported() else { return }
    if purchaseSyncTask != nil { purchaseSyncAgain = true; return }
    let session = WCSession.default
    guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
    purchaseSyncTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { self.purchaseSyncTask = nil }
      repeat {
        self.purchaseSyncAgain = false
        guard let snapshot = await ApplePurchaseStore.shared.companionSnapshot() else { continue }
        self.purchaseSnapshot = snapshot
        // updateApplicationContext replaces the entire dictionary. Retain the
        // service configuration and language while adding independent purchases.
        var context = session.applicationContext
        context["purchases"] = snapshot
        try? session.updateApplicationContext(context)
        if session.isReachable {
          session.sendMessage(["kind": "purchases", "purchases": snapshot], replyHandler: nil)
        }
      } while self.purchaseSyncAgain
    }
  }

  @MainActor
  private func startWorkerIfNeeded() -> Bool {
    guard workerEngine == nil else { return true }
    let engine = FlutterEngine(name: "AI Link Watch Worker", project: nil, allowHeadlessExecution: true)
    // Flutter requires a running engine before installing channel handlers.
    guard engine.run(withEntrypoint: "watchBackgroundMain") else { return false }
    workerEngine = engine
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
    workerChannel = channel
    GeneratedPluginRegistrant.register(with: engine)
    ApplePurchaseBridge.shared.attach(messenger: engine.binaryMessenger)
    pluginsReady = true
    flushPending()
    return true
  }

  private func enqueue(id: String, arguments: [String: Any]) {
    DispatchQueue.main.async {
      if ["audio", "confirm", "remote-asr", "remote-chat", "remote-tts", "turn"].contains(arguments["kind"] as? String ?? "") {
        self.processingIDs.insert(id)
        self.phoneUpdates?.invokeMethod("changed", arguments: nil)
      }
      guard self.startWorkerIfNeeded() else {
        self.processingIDs.remove(id)
        self.phoneUpdates?.invokeMethod("changed", arguments: nil)
        self.sendUpdate(["id": id, "stage": "error", "error": "iPhone 处理器无法启动，请打开手机应用后重试"])
        return
      }
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
        if !(result is FlutterError), arguments["kind"] as? String == "turn" {
          self?.sendUpdate(["id": id, "kind": "turn-ack"])
        }
        self?.processingIDs.remove(id)
        self?.phoneUpdates?.invokeMethod("changed", arguments: nil)
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
    if message["kind"] as? String == "preferences" {
      // Flutter's optional fields arrive as NSNull, which WCSession property lists reject.
      message = propertyList(message) as? [String: Any] ?? [:]
      message["language"] = UserDefaults.standard.string(forKey: "ai_link_watch_language") ?? "zh"
      message["purchases"] = purchaseSnapshot
      UserDefaults.standard.set(message.filter { $0.key != "id" && $0.key != "configuration" && $0.key != "purchases" }, forKey: "ai_link_watch_preferences")
      try? session.updateApplicationContext(message)
      if session.isReachable { session.sendMessage(message, replyHandler: nil) }
      return
    }
    if message["stage"] as? String == "complete", message["audio"] == nil {
      sendResultFile(message, session: session)
    }
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
    if ["complete", "error", "awaiting_confirmation"].contains(stage) {
      phoneUpdates?.invokeMethod("changed", arguments: nil)
    }
    if stage == "complete" && message["remote"] as? Bool == true { return }
    let shouldQueue = ["complete", "error", "awaiting_confirmation"].contains(stage) || message["kind"] as? String == "turn-ack"
    if session.isReachable {
      session.sendMessage(message, replyHandler: nil) { _ in
        if shouldQueue { session.transferUserInfo(message) }
      }
    } else if shouldQueue {
      session.transferUserInfo(message)
    }
  }

  private func propertyList(_ value: Any) -> Any {
    if let map = value as? [String: Any] {
      return map.filter { !($0.value is NSNull) }.mapValues(propertyList)
    }
    if let list = value as? [Any] { return list.filter { !($0 is NSNull) }.map(propertyList) }
    return value
  }

  func session(
    _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
    error: Error?
  ) {
    DispatchQueue.main.async { self.sendPendingConfiguration(); self.syncPreferences(); self.syncPurchases() }
  }

  func sessionWatchStateDidChange(_ session: WCSession) {
    DispatchQueue.main.async { self.sendPendingConfiguration(); self.syncPreferences(); self.syncPurchases() }
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    DispatchQueue.main.async { self.sendPendingConfiguration(); self.syncPreferences(); self.syncPurchases() }
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) { session.activate() }

  private func sendResultFile(_ update: [String: Any], session: WCSession) {
    guard update["remote"] as? Bool == true, let id = update["id"] as? String else { return }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("result-\(UUID().uuidString).json")
    do {
      try JSONSerialization.data(withJSONObject: update).write(to: url, options: .atomic)
      outgoingAudio[session.transferFile(url, metadata: ["kind": "remote-result", "id": id])] = url
    } catch {
      try? FileManager.default.removeItem(at: url)
      sendUpdate(["id": id, "stage": "error", "error": "手机结果传输失败"])
    }
  }

  private func accept(_ arguments: [String: Any]) -> Bool {
    guard let id = arguments["id"] as? String,
          let kind = arguments["kind"] as? String else { return false }
    if kind.hasPrefix("remote-") {
      guard let deadline = arguments["expiresAt"] as? Double, deadline >= Date().timeIntervalSince1970,
            deadline <= Date().addingTimeInterval(60).timeIntervalSince1970 else {
        sendUpdate(["id": id, "stage": "error", "error": "请求已过期，请重新操作"])
        return false
      }
      guard !receivedRequests.contains(id) else { return true }
      if receivedRequests.count >= 1000 { receivedRequests.removeAll() }
      receivedRequests.insert(id)
    }
    var accepted = arguments
    if kind == "remote-chat" { accepted["requireComplete"] = true }
    enqueue(id: id, arguments: accepted)
    return true
  }

  func session(_ session: WCSession, didReceive file: WCSessionFile) {
    guard let kind = file.metadata?["kind"] as? String, let id = file.metadata?["id"] as? String,
          let data = try? Data(contentsOf: file.fileURL), !data.isEmpty, data.count <= 4 * 1024 * 1024 else { return }
    DispatchQueue.main.async {
      if kind == "turn" {
        guard let raw = String(data: data, encoding: .utf8) else { return }
        self.enqueue(id: id, arguments: ["id": id, "kind": "turn", "turn": raw])
      } else if kind == "remote-request" {
        guard let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              args["kind"] as? String == "remote-chat", args["id"] as? String == id else { return }
        _ = self.accept(args)
      } else if kind == "audio" || kind == "remote-asr" {
        var args = file.metadata ?? [:]
        args["id"] = id
        args["kind"] = kind
        args["audio"] = FlutterStandardTypedData(bytes: data)
        _ = self.accept(args)
      }
    }
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any],
               replyHandler: @escaping ([String: Any]) -> Void) {
    DispatchQueue.main.async {
      let kind = message["kind"] as? String ?? ""
      guard let id = message["id"] as? String else { replyHandler(["accepted": false]); return }
      if kind == "purchases" {
        // Do not involve the Flutter background worker or service configuration.
        Task { @MainActor in
          await ApplePurchaseStore.shared.refresh()
          if let snapshot = await ApplePurchaseStore.shared.companionSnapshot() {
            replyHandler(["accepted": true, "purchases": snapshot])
            self.syncPurchases()
          } else { replyHandler(["accepted": false]) }
        }
      } else if kind == "preferences" {
        let independent = message["version"] as? Int == 2
        if independent { UserDefaults.standard.set(true, forKey: "ai_link_watch_independent") }
        self.enqueue(id: id, arguments: ["id": id, "kind": independent ? "apple-configuration" : "apple-preferences"])
        replyHandler(["accepted": true])
        self.syncPurchases()
      } else if kind == "remote-tts", let text = message["text"] as? String, text.count <= 1800 {
        replyHandler(["accepted": self.accept(message)])
      } else if kind == "confirm", let text = message["transcript"] as? String, !text.isEmpty, text.count <= 5000 {
        replyHandler(["accepted": self.accept(message)])
      } else { replyHandler(["accepted": false]) }
    }
  }

  func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
    DispatchQueue.main.async {
      guard let url = self.outgoingAudio.removeValue(forKey: fileTransfer) else { return }
      try? FileManager.default.removeItem(at: url)
    }
  }
}
