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

/// The watch owns only temporary audio and a small local display history.
/// Recognition, model requests, and optional synthesis use the iPhone's configured services.
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
  private var settingsRequestID: String?
  private var statusLabels: (String, String)?

  private var recorder: AVAudioRecorder?
  private var player: AVAudioPlayer?
  private var playbackURL: URL?
  private var timer: Timer?
  private var requestTimer: Timer?
  private var recordURL: URL?
  private var recordedAt: Date?
  private var activeID: String?
  private var outgoing: [WCSessionFileTransfer: URL] = [:]
  private var pressActive = false
  private var permissionPending = false
  private let historyKey = "ai_link_watch_history_v1"

  override init() {
    super.init()
    if let data = UserDefaults.standard.data(forKey: historyKey),
       let saved = try? JSONDecoder().decode([WatchTurn].self, from: data) {
      turns = Array(saved.suffix(50))
    }
    let defaults = UserDefaults.standard
    speak = defaults.object(forKey: "ai_link_watch_speak") as? Bool
      ?? defaults.object(forKey: "ai_link_phone_speak") as? Bool ?? false
    modelSummary = defaults.string(forKey: "ai_link_phone_model_summary") ?? localized("等待手机配置", "Waiting for phone settings")
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
  }

  var phoneAvailable: Bool {
    WCSession.isSupported() && WCSession.default.activationState == .activated
      && WCSession.default.isCompanionAppInstalled && WCSession.default.isReachable
  }

  var visibleHistory: [WatchTurn] { turns.filter { $0.id != activeID } }
  var chinese: Bool { language == "zh" }

  var connectionLabel: String {
    phoneAvailable ? localized("手机已连接", "Phone connected") : localized("手机未连接", "Phone disconnected")
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

  func refreshPhoneSettings() {
    objectWillChange.send()
    guard phoneAvailable else {
      syncingSettings = false
      settingsStatus = localized("请先在 iPhone 安装并打开 AI Link", "Open AI Link on the paired iPhone")
      return
    }
    guard !syncingSettings else { return }
    let id = UUID().uuidString
    settingsRequestID = id
    syncingSettings = true
    settingsStatus = localized("正在向手机请求最新配置…", "Requesting latest phone settings…")
    WCSession.default.sendMessage(["kind": "preferences", "id": id], replyHandler: { [weak self] reply in
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
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
      guard let self, self.settingsRequestID == id, self.syncingSettings else { return }
      self.finishSettingsRequest(success: false)
    }
  }

  private func finishSettingsRequest(success: Bool) {
    syncingSettings = false
    settingsRequestID = nil
    settingsStatus = success
      ? (textReady && asrReady ? localized("配置已同步", "Settings synced") : configurationGuidance)
      : localized("配置同步失败，请在手机检查模型和语音服务", "Sync failed. Check model and voice services on phone")
    guard recordingPreflight else { return }
    recordingPreflight = false
    guard success else {
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
    guard phoneAvailable else {
      setStatus("请先在 iPhone 安装并打开 AI Link", "Open AI Link on the paired iPhone")
      return
    }
    // Recheck on each press so a deleted service or key cannot start recording.
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
    guard WCSession.default.activationState == .activated else {
      try? FileManager.default.removeItem(at: url)
      setStatus("手机连接不可用，请重试", "iPhone connection unavailable")
      return
    }
    let id = UUID().uuidString
    activeID = id
    transcript = ""
    answer = ""
    awaitingConfirmation = false
    busy = true
    phase = "transcribing"
    scrollGeneration += 1
    setStatus("正在发送录音…", "Sending recording…")
    let transfer = WCSession.default.transferFile(url, metadata: ["kind": "audio", "id": id, "autoSend": action == .send, "speak": speak])
    outgoing[transfer] = url
    armRequestTimeout(id: id)
  }

  func confirmTranscript() {
    guard awaitingConfirmation, !transcript.isEmpty,
          WCSession.default.isReachable, let id = activeID else {
      setStatus("请打开 iPhone 上的 AI Link 后重试", "Open AI Link on iPhone and retry")
      return
    }
    awaitingConfirmation = false
    busy = true
    setStatus("正在发送…", "Sending…")
    armRequestTimeout(id: id)
    WCSession.default.sendMessage(
      ["kind": "confirm", "id": id, "transcript": transcript, "speak": speak],
      replyHandler: { [weak self] reply in
        if reply["accepted"] as? Bool != true {
          DispatchQueue.main.async {
            self?.busy = false
            self?.awaitingConfirmation = true
            self?.requestTimer?.invalidate()
            self?.setStatus("发送未被手机接收，请重试", "The iPhone did not accept this turn. Try again")
          }
        }
      },
      errorHandler: { [weak self] _ in
        DispatchQueue.main.async {
          self?.busy = false
          self?.awaitingConfirmation = true
          self?.requestTimer?.invalidate()
          self?.setStatus("手机连接不可用，请重试", "iPhone connection unavailable")
        }
      }
    )
  }

  private func apply(_ update: [String: Any]) {
    if update["kind"] as? String == "preferences" {
      guard let language = update["language"] as? String, ["zh", "en"].contains(language) else { return }
      self.language = language
      UserDefaults.standard.set(language, forKey: "ai_link_phone_language")
      if let labels = statusLabels { status = localized(labels.0, labels.1) }
      if let value = update["textReady"] as? Bool { textReady = value }
      if let value = update["asrReady"] as? Bool { asrReady = value }
      let defaults = UserDefaults.standard
      if let value = update["speak"] as? Bool {
        defaults.set(value, forKey: "ai_link_phone_speak")
        if defaults.object(forKey: "ai_link_watch_speak") == nil { speak = value }
      }
      if let name = update["providerName"] as? String, let model = update["model"] as? String {
        modelSummary = name.isEmpty ? localized("等待手机配置", "Waiting for phone settings") : "\(name) · \(model)"
        defaults.set(modelSummary, forKey: "ai_link_phone_model_summary")
        if update["id"] as? String == settingsRequestID { finishSettingsRequest(success: true) }
      }
      return
    }
    guard let id = update["id"] as? String, id == activeID else { return }
    let stage = update["stage"] as? String ?? ""
    if ["complete", "error", "awaiting_confirmation"].contains(stage) {
      requestTimer?.invalidate()
      requestTimer = nil
    } else {
      armRequestTimeout(id: id)
    }
    if let value = update["transcript"] as? String { transcript = value }
    if let value = update["answer"] as? String { answer = value }
    phase = stage
    switch stage {
    case "transcribing":
      setStatus("正在识别语音…", "Transcribing…")
    case "transcribed", "thinking":
      setStatus("模型正在思考…", "Model is thinking…")
    case "awaiting_confirmation":
      awaitingConfirmation = true
      busy = false
      setStatus("确认后发送", "Confirm to send")
    case "replying":
      busy = true
      setStatus("正在回答…", "Answering…")
    case "complete":
      busy = false
      setStatus("", "")
      if !transcript.isEmpty && !answer.isEmpty {
        if let index = turns.firstIndex(where: { $0.id == id }) {
          turns[index].answer = answer
        } else {
          turns.append(WatchTurn(id: id, question: transcript, answer: answer))
        }
        turns = Array(turns.suffix(50))
        if let data = try? JSONEncoder().encode(turns) {
          UserDefaults.standard.set(data, forKey: historyKey)
        }
      }
    case "error":
      busy = false
      setStatus((update["error"] as? String) ?? "请求失败，请重试", "Request failed. Check the iPhone for details.")
    default:
      break
    }
  }

  private func armRequestTimeout(id: String) {
    requestTimer?.invalidate()
    requestTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: false) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self, self.activeID == id, self.busy else { return }
        self.busy = false
        self.phase = "error"
        self.setStatus("响应超时，请先在手机查看会话，再决定是否重试", "Response timed out. Check iPhone chat before retrying")
      }
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

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    if let url = playbackURL { try? FileManager.default.removeItem(at: url) }
    playbackURL = nil
    self.player = nil
    playing = false
    try? AVAudioSession.sharedInstance().setActive(false)
  }

  private func localized(_ chinese: String, _ english: String) -> String {
    self.chinese ? chinese : english
  }

  private func setStatus(_ chinese: String, _ english: String) {
    statusLabels = (chinese, english)
    status = localized(chinese, english)
  }

  func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
    DispatchQueue.main.async {
      self.apply(session.receivedApplicationContext)
      self.objectWillChange.send()
    }
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    DispatchQueue.main.async {
      self.objectWillChange.send()
      if session.isReachable { self.refreshPhoneSettings() }
    }
  }

  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    DispatchQueue.main.async { self.apply(applicationContext) }
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    DispatchQueue.main.async { self.apply(message) }
  }

  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
    DispatchQueue.main.async { self.apply(userInfo) }
  }

  func session(_ session: WCSession, didReceive file: WCSessionFile) {
    guard file.metadata?["kind"] as? String == "audio",
          let id = file.metadata?["id"] as? String else { return }
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("reply-\(UUID().uuidString).\(file.fileURL.pathExtension)")
    do {
      try FileManager.default.moveItem(at: file.fileURL, to: destination)
      DispatchQueue.main.async {
        if id == self.activeID { self.playAudio(at: destination) }
        else { try? FileManager.default.removeItem(at: destination) }
      }
    } catch { return }
  }

  func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
    DispatchQueue.main.async {
      if let url = self.outgoing.removeValue(forKey: fileTransfer) {
        try? FileManager.default.removeItem(at: url)
      }
      if error != nil && fileTransfer.file.metadata?["id"] as? String == self.activeID {
        self.busy = false
        self.phase = "error"
        self.requestTimer?.invalidate()
        self.setStatus("录音发送失败，请重试", "Recording transfer failed. Try again")
      }
    }
  }
}
