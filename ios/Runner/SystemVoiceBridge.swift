import AVFoundation
import Flutter
import Speech

/// System speech stays in the foreground iPhone engine; Watch uses system text input.
final class SystemVoiceBridge: NSObject, AVSpeechSynthesizerDelegate {
  static let shared = SystemVoiceBridge()
  private let synthesizer = AVSpeechSynthesizer()
  private var utterance: AVSpeechUtterance?
  private var speechResult: FlutterResult?
  private var recognizer: SFSpeechRecognizer?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var recognitionResult: FlutterResult?
  private var recognitionURL: URL?
  private var timeout: DispatchWorkItem?
  private var recognitionID: UUID?
  private var interruptionObserver: NSObjectProtocol?

  func attach(messenger: FlutterBinaryMessenger) {
    synthesizer.delegate = self
    if interruptionObserver == nil {
      interruptionObserver = NotificationCenter.default.addObserver(
        forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
      ) { [weak self] notification in
        if (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue {
          self?.stopSpeech()
        }
      }
      // Remove recordings left by a terminated process, never user files.
      let folder = FileManager.default.temporaryDirectory
      for url in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
        if url.lastPathComponent.hasPrefix("system-voice-") && url.pathExtension == "wav" {
          try? FileManager.default.removeItem(at: url)
        }
      }
    }
    FlutterMethodChannel(name: "between_models/system_voice", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard let self else { return }
        let args = call.arguments as? [String: Any] ?? [:]
        let locale = args["locale"] as? String ?? "zh-CN"
        switch call.method {
        case "voices":
          result(AVSpeechSynthesisVoice.speechVoices().filter { voice in
            if #available(iOS 17.0, *), voice.voiceTraits.contains(.isPersonalVoice) { return false }
            return true
          }.map { voice in
            ["identifier": voice.identifier, "name": voice.name,
             "language": voice.language, "quality": voice.quality.rawValue] as [String: Any]
          })
        case "prepareRecognition":
          SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
              guard status == .authorized else {
                result(self.makeError("speech_permission")); return
              }
              guard SFSpeechRecognizer(locale: Locale(identifier: locale))?.isAvailable == true else {
                result(self.makeError("speech_unavailable")); return
              }
              result(nil)
            }
          }
        case "transcribe":
          guard let bytes = args["audio"] as? FlutterStandardTypedData,
                bytes.data.count > 44, bytes.data.count <= 4 * 1024 * 1024 else {
            result(self.makeError("invalid_audio")); return
          }
          self.transcribe(bytes.data, locale: locale, result: result)
        case "cancelRecognition":
          self.finishRecognition(self.makeError("cancelled")); result(nil)
        case "speak":
          guard let text = args["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            result(self.makeError("invalid_text")); return
          }
          self.stopSpeech()
          do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            let speech = AVSpeechUtterance(string: text)
            let voiceID = args["voiceIdentifier"] as? String ?? ""
            let selected = voiceID.isEmpty ? nil : AVSpeechSynthesisVoice(identifier: voiceID)
            guard let voice = selected ?? AVSpeechSynthesisVoice(language: locale) else {
              result(self.makeError("speech_unavailable"));
              try? AVAudioSession.sharedInstance().setActive(false)
              return
            }
            speech.voice = voice
            self.utterance = speech
            self.speechResult = result
            self.synthesizer.speak(speech)
          } catch { result(self.makeError("speech_failed")) }
        case "stop": self.stopSpeech(); result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      }
  }

  private func makeError(_ code: String) -> FlutterError {
    FlutterError(code: code, message: code, details: nil)
  }

  private func transcribe(_ data: Data, locale: String, result: @escaping FlutterResult) {
    guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
      result(makeError("speech_permission")); return
    }
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
      result(makeError("speech_unavailable")); return
    }
    finishRecognition(makeError("cancelled"))
    let id = UUID()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("system-voice-\(id).wav")
    do { try data.write(to: url, options: .atomic) }
    catch { result(makeError("speech_failed")); return }
    recognitionID = id
    recognitionURL = url
    recognitionResult = result
    self.recognizer = recognizer
    let request = SFSpeechURLRecognitionRequest(url: url)
    request.shouldReportPartialResults = false
    request.taskHint = .dictation
    request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] transcript, failure in
      DispatchQueue.main.async {
        guard let self, self.recognitionID == id else { return }
        if let transcript, transcript.isFinal {
          self.finishRecognition(transcript.bestTranscription.formattedString)
        } else if failure != nil { self.finishRecognition(self.makeError("speech_failed")) }
      }
    }
    let deadline = DispatchWorkItem { [weak self] in
      guard let self, self.recognitionID == id else { return }
      self.finishRecognition(self.makeError("speech_failed"))
    }
    timeout = deadline
    DispatchQueue.main.asyncAfter(deadline: .now() + 65, execute: deadline)
  }

  private func finishRecognition(_ value: Any?) {
    recognitionID = nil
    timeout?.cancel()
    timeout = nil
    recognitionTask?.cancel()
    recognitionTask = nil
    recognizer = nil
    if let url = recognitionURL { try? FileManager.default.removeItem(at: url) }
    recognitionURL = nil
    let result = recognitionResult
    recognitionResult = nil
    result?(value)
  }

  private func stopSpeech() {
    utterance = nil
    synthesizer.stopSpeaking(at: .immediate)
    let result = speechResult
    speechResult = nil
    result?(nil)
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    guard self.utterance === utterance else { return }
    stopSpeech()
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    guard self.utterance === utterance else { return }
    stopSpeech()
  }
}
