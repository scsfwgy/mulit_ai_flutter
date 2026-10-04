import AVFoundation
import Combine
import Foundation
import WatchConnectivity

enum WatchReleaseAction {
  case send, cancel, review

  static func fromDrag(_ translation: CGSize) -> WatchReleaseAction {
    guard translation.height <= -40 else { return .send }
    if translation.width <= -30 { return .cancel }
    if translation.width >= 30 { return .review }
    return .send
  }
}

struct WatchTurn: Codable, Identifiable {
  let id: String
  let question: String
  var answer: String
}

/// Watch-first requests and optional phone fallback share watch-owned history.
@MainActor
final class WatchChatSession: NSObject, ObservableObject, WCSessionDelegate, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
  @Published private(set) var turns: [WatchTurn] = []
  @Published private(set) var status = ""
  @Published private(set) var transcript = ""
  @Published private(set) var answer = ""
  @Published private(set) var recording = false
  @Published private(set) var busy = false
  @Published private(set) var awaitingConfirmation = false
  @Published private(set) var elapsed = 0
  @Published private(set) var elapsedMs = 0
  @Published private(set) var level = 0.0
  @Published var releaseAction = WatchReleaseAction.send
  @Published private(set) var language = UserDefaults.standard.string(forKey: "ai_link_phone_language") ?? "zh"
  @Published private(set) var speak = false
  @Published private(set) var playing = false
  @Published private(set) var syncingSettings = false
  @Published private(set) var settingsStatus = ""
  @Published private(set) var modelSummary = ""
  @Published private(set) var scrollGeneration = 0
  @Published var configurationPrompt = false
  @Published private(set) var textReady = false
  @Published private(set) var asrReady = false
  private var recordingPreflight = false
  private var phase = "idle"
  private var settingsSync = WatchSettingsSync()
  private var settingsRequestID: String? { settingsSync.requestID }
  private var statusLabels: (String, String)?

  private var recorder: AVAudioRecorder?
  private var player: AVAudioPlayer?
  private var playbackURL: URL?
  private var timer: Timer?
  private var recordURL: URL?
  private var recordedAt: Date?
  private var activeID: String?
  private var outgoing: [WCSessionFileTransfer: URL] = [:]
  private var pressActive = false
  private var permissionPending = false
  private let configurationStore = WatchConfigurationStore()
  private let independentHistory = WatchHistoryStore()
  private let networkClient = WatchNetworkClient()
  @Published private(set) var configuration: WatchNetworkConfiguration?
  private var turnConfiguration: WatchNetworkConfiguration?
  private var syncID: String?
  private var processingTask: Task<Void, Never>?
  @MainActor private lazy var relay = WatchPhoneRelay()
  private let historyKey = "ai_link_watch_history_v1"

  override init() {
    super.init()
    if let data = UserDefaults.standard.data(forKey: historyKey),
       let saved = try? JSONDecoder().decode([WatchTurn].self, from: data) {
      turns = Array(saved.suffix(50))
    }
    configuration = configurationStore.load()
    textReady = configuration?.canChat ?? false
    asrReady = configuration?.canTranscribe ?? false
    for turn in independentHistory.snapshot.recent where !turns.contains(where: { $0.id == turn.id }) {
      turns.append(WatchTurn(id: turn.id, question: turn.transcript, answer: turn.answer))
    }
    turns = Array(turns.suffix(50))
    let defaults = UserDefaults.standard
    speak = defaults.object(forKey: "ai_link_watch_speak") as? Bool
      ?? defaults.object(forKey: "ai_link_phone_speak") as? Bool ?? false
    modelSummary = defaults.string(forKey: "ai_link_phone_model_summary") ?? localized("等待手机配置", "Waiting for phone settings")
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
      refreshPhoneSettings()
    }
  }

  var phoneAvailable: Bool {
    WCSession.isSupported() && WCSession.default.activationState == .activated
      && WCSession.default.isCompanionAppInstalled && WCSession.default.isReachable
  }

  var visibleHistory: [WatchTurn] { turns.filter { $0.id != activeID } }
  var chinese: Bool { language == "zh" }

  var connectionLabel: String {
    phoneAvailable ? localized("手机已连接", "Phone connected") : localized("手机未连接 · 使用手表网络", "Phone offline · using watch network")
  }

  var configurationGuidance: String {
    let missing = !textReady && !asrReady
      ? localized("请先配置文字模型和语音识别服务。", "Set up text and speech recognition services first.")
      : !textReady
      ? localized("请先配置文字模型服务、模型和 API Key。", "Set up a text service, model and API key first.")
      : localized("请先配置语音识别服务、识别模型和 API Key。", "Set up a speech recognition service, model and API key first.")
    return missing + localized(
      "\n在手机 AI Link 的设置中，进入模型设置添加文字服务，再进入语音服务添加并选择语音识别服务。完成后回到手表同步配置。",
      "\nOn phone: AI Link → Settings → Model settings; then Voice services → Speech recognition service. Return to the watch and sync settings when done.")
  }

  var actionLabel: String {
    if awaitingConfirmation { return localized("确认发送", "Confirm and send") }
    if busy || recordingPreflight { return localized("请稍候", "Please wait") }
    if !textReady || !asrReady { return localized("配置服务", "Set up services") }
    if phase == "error" { return localized("按住重试", "Hold to retry") }
    if phase == "complete" { return localized("按住再说", "Hold to speak again") }
    return localized("按住说话", "Hold to speak")
  }

  func setSpeak(_ value: Bool) {
    speak = value
    UserDefaults.standard.set(value, forKey: "ai_link_watch_speak")
    if !value { stopPlayback() }
  }

  func refreshPhoneSettings(manual: Bool = false) {
    objectWillChange.send()
    // A local wipe must not be undone by a cached application context on launch.
    if manual { UserDefaults.standard.removeObject(forKey: "ai_link_watch_config_cleared") }
    guard !UserDefaults.standard.bool(forKey: "ai_link_watch_config_cleared") else { return }
    guard let id = settingsSync.begin(manual: manual) else { return }
    syncingSettings = true
    settingsStatus = localized("正在向手机请求最新配置…", "Requesting latest phone settings…")
    sendPendingSettingsRequest()
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
      guard let self, self.settingsRequestID == id else { return }
      self.finishSettingsRequest(success: false)
    }
  }

  private func sendPendingSettingsRequest() {
    guard WCSession.isSupported() else { finishSettingsRequest(success: false); return }
    // Activation is asynchronous on cold launch. Send the already-created
    // request after activation rather than mistaking it for an offline phone.
    guard WCSession.default.activationState == .activated else {
      WCSession.default.activate()
      return
    }
    guard let id = settingsSync.takePending() else { return }
    guard phoneAvailable else { finishSettingsRequest(success: false); return }
    syncPendingTurns()
    WCSession.default.sendMessage(["kind": "preferences", "id": id, "version": 2], replyHandler: { [weak self] reply in
      DispatchQueue.main.async {
        guard let self, self.settingsRequestID == id else { return }
        if reply["accepted"] as? Bool != true { self.finishSettingsRequest(success: false) }
      }
    }, errorHandler: { [weak self] _ in
      DispatchQueue.main.async {
        guard let self, self.settingsRequestID == id else { return }
        self.finishSettingsRequest(success: false)
      }
    })
  }

  private func finishSettingsRequest(success: Bool) {
    guard let id = settingsRequestID, settingsSync.finish(id, success: success) else { return }
    syncingSettings = false
    settingsStatus = success
      ? (textReady && asrReady ? localized("配置已同步", "Settings synced") : configurationGuidance)
      : (textReady && asrReady
          ? localized("同步失败，继续使用上次配置", "Sync failed; using saved settings")
          : localized("同步失败，尚无可用配置；请连接手机后重试", "Sync failed; no usable saved settings. Connect iPhone and retry"))
    guard recordingPreflight else { return }
    recordingPreflight = false
    guard success || (textReady && asrReady) else {
      setStatus("无法校验服务配置，请打开手机应用后重试", "Could not check services. Open the phone app and retry")
      return
    }
    guard textReady && asrReady else {
      pressActive = false
      configurationPrompt = true
      setStatus("先在手机完成模型与语音配置", "Set up text and voice services on your phone")
      return
    }
    if pressActive { requestMicrophoneAndRecord() }
    else { setStatus("", "") }
  }

  func resetForRecording() {
    guard !busy else { return }
    activeID = nil
    awaitingConfirmation = false
    transcript = ""
    answer = ""
    phase = "idle"
    setStatus("", "")
    scrollGeneration += 1
  }

  func cancelRecording() {
    recordingPreflight = false
    stopRecording(action: .cancel)
  }

  func startRecording() {
    pressActive = true
    releaseAction = .send
    guard !recording && !busy && !permissionPending && !recordingPreflight else { return }
    guard independentHistory.snapshot.pending.count < 100 else {
      setStatus("请先连接手机同步已有问答", "Reconnect iPhone to sync pending chats first")
      return
    }
    if textReady && asrReady {
      requestMicrophoneAndRecord()
      return
    }
    guard phoneAvailable, !UserDefaults.standard.bool(forKey: "ai_link_watch_config_cleared") else {
      configurationPrompt = true
      return
    }
    // Only missing setup blocks recording on phone sync; usable cached settings
    // let the watch start without waiting for the phone processor.
    recordingPreflight = true
    setStatus("正在检查服务配置…", "Checking service settings…")
    refreshPhoneSettings()
  }

  private func requestMicrophoneAndRecord() {
    permissionPending = true
    AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
      DispatchQueue.main.async {
        guard let self else { return }
        self.permissionPending = false
        if granted && self.pressActive { self.beginRecording() }
        if !granted {
          self.setStatus("请允许手表使用麦克风", "Allow microphone access on your watch")
        }
      }
    }
  }

  private func beginRecording() {
    guard !recording && !busy && textReady && asrReady else { return }
    do {
      stopPlayback()
      try AVAudioSession.sharedInstance().setCategory(.playAndRecord)
      try AVAudioSession.sharedInstance().setActive(true)
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).wav")
      recordURL = url
      recorder = try AVAudioRecorder(url: url, settings: [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
      ])
      recorder?.delegate = self
      recorder?.isMeteringEnabled = true
      guard recorder?.record() == true else { throw NSError(domain: "AILinkWatch", code: 1) }
      recordedAt = Date()
      elapsed = 0
      elapsedMs = 0
      level = 0
      recording = true
      setStatus("正在录音，左上取消，右上确认", "Recording · up-left cancels, up-right reviews")
      timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
        DispatchQueue.main.async {
          guard let self, self.recording else { return }
          self.elapsedMs = Int(Date().timeIntervalSince(self.recordedAt ?? Date()) * 1000)
          self.elapsed = self.elapsedMs / 1000
          self.recorder?.updateMeters()
          self.level = min(1, max(0, Double((self.recorder?.averagePower(forChannel: 0) ?? -55) + 55) / 45))
          if self.elapsed >= 90 { self.stopRecording(action: self.releaseAction) }
        }
      }
    } catch {
      recorder?.stop()
      recorder = nil
      if let url = recordURL { try? FileManager.default.removeItem(at: url) }
      recordURL = nil
      phase = "error"
      setStatus("无法开始录音", "Could not start recording")
      try? AVAudioSession.sharedInstance().setActive(false)
    }
  }

  func stopRecording(action: WatchReleaseAction) {
    let cancel = action == .cancel
    pressActive = false
    // Keep the preflight pending until its reply so missing setup still shows guidance.
    guard recording else { return }
    let duration = recorder?.currentTime ?? 0
    recorder?.stop()
    recorder = nil
    try? AVAudioSession.sharedInstance().setActive(false)
    timer?.invalidate()
    timer = nil
    recording = false
    releaseAction = .send
    defer { recordURL = nil }
    guard let url = recordURL else { return }
    if cancel || duration < 0.6 {
      try? FileManager.default.removeItem(at: url)
      setStatus(cancel && duration >= 0.6 ? "已取消" : "", cancel && duration >= 0.6 ? "Canceled" : "")
      return
    }
    guard let config = configuration, config.canChat, config.canTranscribe else {
      try? FileManager.default.removeItem(at: url)
      configurationPrompt = true
      return
    }
    let id = UUID().uuidString.lowercased()
    activeID = id
    turnConfiguration = config
    transcript = ""
    answer = ""
    awaitingConfirmation = false
    busy = true
    phase = "transcribing"
    scrollGeneration += 1
    setStatus("正在识别语音…", "Transcribing…")
    processingTask = Task { @MainActor in
      defer { try? FileManager.default.removeItem(at: url) }
      do {
        let wav = try Data(contentsOf: url)
        let text: String = try await routed(phone: {
          let result = try await self.relay.request("remote-asr", audio: wav)
          guard let text = result["transcript"] as? String, !text.isEmpty else {
            throw WatchRequestError("识别结果无效", "Invalid transcript")
          }
          return text
        }, watch: { try await self.networkClient.transcribe(wav, config: config) })
        self.transcript = text
        if action == .review {
          self.awaitingConfirmation = true
          self.busy = false
          self.phase = "awaiting_confirmation"
          self.setStatus("确认后发送", "Confirm to send")
        } else { await self.sendTurn(id: id, config: config) }
      } catch { self.failRequest(error) }
    }
  }

  func confirmTranscript() {
    guard awaitingConfirmation, !transcript.isEmpty, let id = activeID,
          let config = turnConfiguration else { return }
    awaitingConfirmation = false
    busy = true
    processingTask = Task { @MainActor in await self.sendTurn(id: id, config: config) }
  }

  @MainActor private func routed<T>(phone: () async throws -> T, watch: () async throws -> T) async throws -> T {
    try await WatchRequestRouting.execute(phoneAvailable: { self.phoneAvailable },
      hasPartial: { ["thinking", "replying"].contains(self.phase) && !self.answer.isEmpty }, onRoute: { phone in
        if self.phase == "thinking" {
          self.setStatus(phone ? "手机正在请求模型…" : "手表正在请求模型…",
                         phone ? "Phone requesting model…" : "Watch requesting model…")
        }
      }, phone: phone, watch: watch)
  }

  @MainActor private func sendTurn(id: String, config: WatchNetworkConfiguration) async {
    phase = "thinking"
    do {
      let history = independentHistory.history(for: config, question: transcript)
      let onText: (String) -> Void = { value in
        // Both relay callbacks and the native client run in this task's actor.
        self.answer = value
        self.phase = "replying"
        self.setStatus("正在回答…", "Answering…")
      }
      let result: String = try await routed(phone: {
        let data = try JSONSerialization.data(withJSONObject: history)
        let response = try await self.relay.request("remote-chat", arguments: [
          "history": String(decoding: data, as: UTF8.self), "providerId": config.providerId!, "model": config.model,
        ], onText: onText)
        guard let answer = response["answer"] as? String, !answer.isEmpty else {
          throw WatchRequestError("模型回复无效", "Invalid model reply")
        }
        return answer
      }, watch: { try await self.networkClient.reply(history: history, config: config, onText: onText) })
      answer = result
      try independentHistory.append(id: id, config: config, question: transcript, answer: result)
      turns.append(WatchTurn(id: id, question: transcript, answer: result))
      turns = Array(turns.suffix(50))
      if let data = try? JSONEncoder().encode(turns) { UserDefaults.standard.set(data, forKey: historyKey) }
      phase = "complete"
      setStatus("", "")
      syncPendingTurns()
      if speak, config.tts != nil {
        do {
          let audio: (Data, String)? = try await routed(phone: {
            let text = String(String.UnicodeScalarView(result.unicodeScalars.prefix(1800)))
            let reply = try await self.relay.request("remote-tts", arguments: ["text": text])
            guard let url = reply["audioURL"] as? URL else { return nil }
            defer { try? FileManager.default.removeItem(at: url) }
            return (try Data(contentsOf: url), url.pathExtension)
          }, watch: { try await self.networkClient.synthesize(result, config: config) })
          if let (data, format) = audio {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("speech-\(UUID().uuidString).\(format)")
            try data.write(to: url, options: .atomic)
            playAudio(at: url)
          }
        } catch { setStatus("文字已保存，朗读失败", "Text saved; speech failed") }
      }
      busy = false
    } catch { failRequest(error) }
  }

  @MainActor private func failRequest(_ error: Error) {
    let failure = WatchRequestError.network(error)
    busy = false
    phase = "error"
    setStatus(failure.chinese, failure.english)
  }

  private func syncPendingTurns() {
    guard phoneAvailable, syncID == nil, let turn = independentHistory.snapshot.pending.first else { return }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("turn-\(UUID().uuidString).json")
    do {
      try JSONEncoder().encode(turn).write(to: url, options: .atomic)
      syncID = turn.id
      outgoing[WCSession.default.transferFile(url, metadata: ["kind": "turn", "id": turn.id])] = url
      DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
        if self.syncID == turn.id { self.syncID = nil }
      }
    } catch { try? FileManager.default.removeItem(at: url); syncID = nil }
  }

  func clearLocalData() {
    guard !busy && !recording else { return }
    stopPlayback()
    do { try configurationStore.clear() }
    catch { failRequest(error); return }
    UserDefaults.standard.set(true, forKey: "ai_link_watch_config_cleared")
    configuration = nil
    turnConfiguration = nil
    independentHistory.clear()
    for transfer in outgoing.keys { transfer.cancel() }
    for url in outgoing.values { try? FileManager.default.removeItem(at: url) }
    outgoing.removeAll()
    syncID = nil
    turns = []
    modelSummary = localized("等待手机配置", "Waiting for phone settings")
    UserDefaults.standard.removeObject(forKey: "ai_link_phone_model_summary")
    UserDefaults.standard.removeObject(forKey: historyKey)
    textReady = false
    asrReady = false
    resetForRecording()
    setStatus("已清除手表配置和问答", "Watch settings and chats cleared")
  }

  @MainActor private func apply(_ update: [String: Any]) {
    if update["kind"] as? String == "turn-ack", let id = update["id"] as? String {
      independentHistory.acknowledge(id)
      if syncID == id { syncID = nil }
      syncPendingTurns()
      return
    }
    if relay.receive(update) { return }
    if update["kind"] as? String == "preferences" {
      let updateID = update["id"] as? String
      guard settingsSync.accepts(updateID) else { return }
      guard let language = update["language"] as? String, ["zh", "en"].contains(language) else { return }
      self.language = language
      UserDefaults.standard.set(language, forKey: "ai_link_phone_language")
      if let labels = statusLabels { status = localized(labels.0, labels.1) }
      if UserDefaults.standard.bool(forKey: "ai_link_watch_config_cleared") { return }
      guard let snapshot = update["configuration"] as? [String: Any] else {
        if updateID == settingsRequestID { finishSettingsRequest(success: false) }
        return
      }
      do {
        // Assign only after decoding and Keychain persistence both succeed.
        // A broken snapshot or storage failure leaves the previous cache usable.
        let saved = try configurationStore.save(snapshot)
        configuration = saved
        textReady = saved.canChat
        asrReady = saved.canTranscribe
      } catch {
        if updateID == settingsRequestID { finishSettingsRequest(success: false) }
        return
      }
      let defaults = UserDefaults.standard
      if let value = update["speak"] as? Bool {
        defaults.set(value, forKey: "ai_link_phone_speak")
        if defaults.object(forKey: "ai_link_watch_speak") == nil { speak = value }
      }
      if let config = configuration {
        let name = config.providerName
        let model = config.model
        modelSummary = name.isEmpty ? localized("等待手机配置", "Waiting for phone settings") : "\(name) · \(model)"
        defaults.set(modelSummary, forKey: "ai_link_phone_model_summary")
        if update["id"] as? String == settingsRequestID { finishSettingsRequest(success: true) }
      }
      syncPendingTurns()
      return
    }
  }

  private func playAudio(at url: URL) {
    guard speak && !recording else { try? FileManager.default.removeItem(at: url); return }
    stopPlayback()
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback)
      try AVAudioSession.sharedInstance().setActive(true)
      player = try AVAudioPlayer(contentsOf: url)
      player?.delegate = self
      playbackURL = url
      if player?.play() != true { throw NSError(domain: "AILinkWatch", code: 2) }
      playing = true
    } catch {
      try? FileManager.default.removeItem(at: url)
      player = nil
      playing = false
      playbackURL = nil
      try? AVAudioSession.sharedInstance().setActive(false)
      setStatus("文字已保存，语音播放失败", "Text saved; audio playback failed")
    }
  }

  func stopPlayback() {
    player?.stop()
    if let url = playbackURL { try? FileManager.default.removeItem(at: url) }
    playbackURL = nil
    player = nil
    playing = false
    try? AVAudioSession.sharedInstance().setActive(false)
  }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    DispatchQueue.main.async { self.stopPlayback() }
  }

  private func localized(_ chinese: String, _ english: String) -> String {
    self.chinese ? chinese : english
  }

  private func setStatus(_ chinese: String, _ english: String) {
    statusLabels = (chinese, english)
    status = localized(chinese, english)
  }

  nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
    DispatchQueue.main.async {
      self.apply(session.receivedApplicationContext)
      self.objectWillChange.send()
      if state == .activated { self.sendPendingSettingsRequest() }
      else { self.finishSettingsRequest(success: false) }
    }
  }

  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    DispatchQueue.main.async {
      self.objectWillChange.send()
      if session.isReachable { self.refreshPhoneSettings() }
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    DispatchQueue.main.async { self.apply(applicationContext) }
  }

  nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    DispatchQueue.main.async { self.apply(message) }
  }

  nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
    DispatchQueue.main.async { self.apply(userInfo) }
  }

  nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
    if file.metadata?["kind"] as? String == "remote-result" {
      if let data = try? Data(contentsOf: file.fileURL), data.count <= 2 * 1024 * 1024,
         let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        DispatchQueue.main.async { self.apply(value) }
      }
      return
    }
    guard file.metadata?["kind"] as? String == "audio",
          let id = file.metadata?["id"] as? String else { return }
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("reply-\(UUID().uuidString).\(file.fileURL.pathExtension)")
    do {
      try FileManager.default.moveItem(at: file.fileURL, to: destination)
      DispatchQueue.main.async {
        if self.relay.receive(["id": id, "stage": "complete", "audioURL": destination]) { return }
        try? FileManager.default.removeItem(at: destination)
      }
    } catch { return }
  }

  nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
    DispatchQueue.main.async {
      self.relay.finished(fileTransfer, error: error)
      if error != nil && fileTransfer.file.metadata?["id"] as? String == self.syncID { self.syncID = nil }
      if let url = self.outgoing.removeValue(forKey: fileTransfer) {
        try? FileManager.default.removeItem(at: url)
      }
    }
  }
}
