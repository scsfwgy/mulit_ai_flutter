import AVFoundation
import Combine
import Foundation
import WatchConnectivity

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
      turns = Array(saved.suffix(20))
    }
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

  func startRecording() {
    pressActive = true
    guard !recording && !busy && !permissionPending else { return }
    guard phoneAvailable else {
      status = localized("请先在 iPhone 安装并打开 AI Link", "Open AI Link on the paired iPhone")
      return
    }
    permissionPending = true
    AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
      DispatchQueue.main.async {
        guard let self else { return }
        self.permissionPending = false
        if granted && self.pressActive { self.beginRecording() }
        if !granted {
          self.status = self.localized("请允许手表使用麦克风", "Allow microphone access on your watch")
        }
      }
    }
  }

  private func beginRecording() {
    guard !recording && !busy else { return }
    do {
      try AVAudioSession.sharedInstance().setCategory(.playAndRecord)
      try AVAudioSession.sharedInstance().setActive(true)
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).wav")
      recorder = try AVAudioRecorder(url: url, settings: [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
      ])
      recorder?.delegate = self
      guard recorder?.record() == true else { throw NSError(domain: "AILinkWatch", code: 1) }
      recordURL = url
      recordedAt = Date()
      elapsed = 0
      recording = true
      status = localized("正在录音，上滑取消", "Recording · slide up to cancel")
      timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
        DispatchQueue.main.async {
          guard let self, self.recording else { return }
          self.elapsed += 1
          if self.elapsed >= 90 { self.stopRecording(cancel: false) }
        }
      }
    } catch {
      status = localized("无法开始录音", "Could not start recording")
      try? AVAudioSession.sharedInstance().setActive(false)
    }
  }

  func stopRecording(cancel: Bool) {
    pressActive = false
    guard recording else { return }
    recorder?.stop()
    recorder = nil
    timer?.invalidate()
    timer = nil
    recording = false
    defer { recordURL = nil }
    guard let url = recordURL else { return }
    if cancel || Date().timeIntervalSince(recordedAt ?? Date()) < 0.4 {
      try? FileManager.default.removeItem(at: url)
      status = localized("已取消", "Canceled")
      return
    }
    guard WCSession.default.activationState == .activated else {
      try? FileManager.default.removeItem(at: url)
      status = localized("手机连接不可用，请重试", "iPhone connection unavailable")
      return
    }
    let id = UUID().uuidString
    activeID = id
    transcript = ""
    answer = ""
    awaitingConfirmation = false
    busy = true
    status = localized("正在发送录音…", "Sending recording…")
    let transfer = WCSession.default.transferFile(url, metadata: ["kind": "audio", "id": id])
    outgoing[transfer] = url
    armRequestTimeout(id: id)
  }

  func confirmTranscript() {
    guard awaitingConfirmation, !transcript.isEmpty,
          WCSession.default.isReachable, let id = activeID else {
      status = localized("请打开 iPhone 上的 AI Link 后重试", "Open AI Link on iPhone and retry")
      return
    }
    awaitingConfirmation = false
    busy = true
    status = localized("正在发送…", "Sending…")
    armRequestTimeout(id: id)
    WCSession.default.sendMessage(
      ["kind": "confirm", "id": id, "transcript": transcript],
      replyHandler: { [weak self] reply in
        if reply["accepted"] as? Bool != true {
          DispatchQueue.main.async {
            self?.busy = false
            self?.awaitingConfirmation = true
            self?.requestTimer?.invalidate()
            self?.status = self?.localized("发送未被手机接收，请重试", "The iPhone did not accept this turn. Try again") ?? ""
          }
        }
      },
      errorHandler: { [weak self] _ in
        DispatchQueue.main.async {
          self?.busy = false
          self?.awaitingConfirmation = true
          self?.requestTimer?.invalidate()
          self?.status = self?.localized("手机连接不可用，请重试", "iPhone connection unavailable") ?? ""
        }
      }
    )
  }

  private func apply(_ update: [String: Any]) {
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
    switch stage {
    case "transcribed":
      status = localized("识别完成", "Transcribed")
    case "awaiting_confirmation":
      awaitingConfirmation = true
      busy = false
      status = localized("确认后发送", "Confirm to send")
    case "thinking", "replying":
      busy = true
      status = localized("正在回复…", "Replying…")
    case "complete":
      busy = false
      status = localized("回答完成", "Reply complete")
      if !transcript.isEmpty && !answer.isEmpty {
        if let index = turns.firstIndex(where: { $0.id == id }) {
          turns[index].answer = answer
        } else {
          turns.append(WatchTurn(id: id, question: transcript, answer: answer))
        }
        turns = Array(turns.suffix(20))
        if let data = try? JSONEncoder().encode(turns) {
          UserDefaults.standard.set(data, forKey: historyKey)
        }
      }
    case "error":
      busy = false
      status = Locale.current.languageCode?.hasPrefix("zh") == true
        ? ((update["error"] as? String) ?? "请求失败，请重试")
        : "Request failed. Check the iPhone for details."
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
        self.status = self.localized("响应超时，请先在手机查看会话，再决定是否重试", "Response timed out. Check iPhone chat before retrying")
      }
    }
  }

  private func playAudio(at url: URL) {
    do {
      if let previous = playbackURL { try? FileManager.default.removeItem(at: previous) }
      try AVAudioSession.sharedInstance().setCategory(.playback)
      try AVAudioSession.sharedInstance().setActive(true)
      player = try AVAudioPlayer(contentsOf: url)
      player?.delegate = self
      playbackURL = url
      if player?.play() != true { throw NSError(domain: "AILinkWatch", code: 2) }
    } catch {
      try? FileManager.default.removeItem(at: url)
      playbackURL = nil
      status = localized("文字已保存，语音播放失败", "Text saved; audio playback failed")
    }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    if let url = playbackURL { try? FileManager.default.removeItem(at: url) }
    playbackURL = nil
    self.player = nil
    try? AVAudioSession.sharedInstance().setActive(false)
  }

  private func localized(_ chinese: String, _ english: String) -> String {
    Locale.current.languageCode?.hasPrefix("zh") == true ? chinese : english
  }

  func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
    DispatchQueue.main.async { self.objectWillChange.send() }
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
      if error != nil {
        self.busy = false
        self.requestTimer?.invalidate()
        self.status = self.localized("录音发送失败，请重试", "Recording transfer failed. Try again")
      }
    }
  }
}
