import Foundation

@main
struct WatchComplicationTests {
  static func main() throws {
    let now = Date(timeIntervalSince1970: 1000)
    func make(_ phase: String = "idle", recording: Bool = false, loading: Bool = false,
              playing: Bool = false, confirming: Bool = false, question: String = "", answer: String = "",
              last: String = "", language: String = "zh", secrets: [String] = []) -> WatchComplicationSnapshot {
      .make(phase: phase, recording: recording, loadingAudio: loading, playing: playing,
            confirming: confirming, question: question, answer: answer, lastAnswer: last, language: language,
            secrets: secrets, date: now)
    }
    precondition(make().state == .idle)
    precondition(make().preview.isEmpty)
    precondition(make(last: "saved reply").state == .complete)
    precondition(make(last: "saved reply").preview == "saved reply")
    precondition(make("thinking", last: "old reply").preview.isEmpty)
    let question = "请帮我安排今天的工作"
    precondition(make("thinking", question: question, last: "old reply").preview == question)
    let longQuestion = make("thinking", question: "问题开头" + String(repeating: "中", count: 160) + "问题结尾")
    precondition(longQuestion.preview.hasPrefix("问题开头") && longQuestion.preview.hasSuffix("…"))
    precondition(!longQuestion.preview.contains("问题结尾"))
    precondition(make("thinking", question: "secret-key", secrets: ["secret-key"]).preview == "•••")
    precondition(make("thinking", question: question, answer: "first chunk").preview == "first chunk")
    precondition(make("replying", question: question, answer: "partial").preview == "partial")
    precondition(make("complete", question: question, answer: "reply").preview == "reply")
    precondition(make(question: question).preview.isEmpty)
    precondition(make("replying", answer: "partial").state == .replying)
    precondition(make("complete", answer: "new", last: "old").preview == "new")
    precondition(make("complete", loading: true, answer: "new").state == .loadingAudio)
    precondition(make("complete", loading: true, answer: "new").preview == "new")
    precondition(make("complete", playing: true, answer: "new").state == .playing)
    precondition(make("complete", recording: true, playing: true).state == .recording)
    precondition(make("transcribing").state == .transcribing)
    precondition(make(confirming: true).state == .confirming)
    precondition(make("error", answer: "partial").preview == "partial")
    precondition(make("error").state == .failed)
    precondition(make("complete", language: "en").label == "Reply ready")
    let streaming = make("replying", answer: "begin" + String(repeating: "中", count: 160) + "latest")
    precondition(streaming.preview.hasPrefix("…") && streaming.preview.hasSuffix("latest"))
    let finished = make("complete", answer: "begin" + String(repeating: "中", count: 160) + "latest")
    precondition(finished.preview.hasPrefix("begin") && finished.preview.hasSuffix("…"))
    let redacted = make("complete", answer: "**Hello** [source](https://example.com)\nsecret-key", secrets: ["secret-key", "secret"])
    precondition(redacted.preview == "Hello source •••")
    precondition(!make("replying", answer: String(repeating: "a", count: 200) + "secret-key", secrets: ["secret-key"]).preview.contains("secret"))
    precondition(streaming.display(at: now.addingTimeInterval(179)).state == .replying)
    precondition(streaming.display(at: now.addingTimeInterval(180)).state == .unknown)
    let audio = make("complete", playing: true, answer: "new")
    precondition(audio.display(at: now.addingTimeInterval(899)).state == .playing)
    precondition(audio.display(at: now.addingTimeInterval(900)).state == .unknown)
    precondition(audio.display(at: now.addingTimeInterval(900)).preview == "new")
    precondition(finished.display(at: now.addingTimeInterval(100000)).state == .complete)
    let encoded = try JSONEncoder().encode(redacted)
    let decoded = try JSONDecoder().decode(WatchComplicationSnapshot.self, from: encoded)
    precondition(decoded == redacted)
    precondition(!String(decoding: encoded, as: UTF8.self).contains("secret-key"))
    print("Watch complication state, preview, redaction and expiry checks passed")
  }
}
