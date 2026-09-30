import SwiftUI

struct WatchContentView: View {
  @ObservedObject var session: WatchChatSession

  private var chinese: Bool { Locale.current.languageCode?.hasPrefix("zh") == true }
  private func label(_ zh: String, _ en: String) -> String { chinese ? zh : en }

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        Text("AI Link").font(.headline)
        if !session.status.isEmpty {
          Text(session.status)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        if !session.transcript.isEmpty {
          Text(session.transcript)
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if !session.answer.isEmpty {
          Text(session.answer)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if session.awaitingConfirmation {
          Button(label("发送文字", "Send text")) { session.confirmTranscript() }
            .buttonStyle(.borderedProminent)
        }
        recordButton
        if !session.visibleHistory.isEmpty {
          Divider()
          Text(label("历史记录", "History"))
            .font(.caption2).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
          ForEach(session.visibleHistory.reversed()) { turn in
            VStack(alignment: .leading, spacing: 4) {
              Text(turn.question).font(.caption).foregroundStyle(.secondary)
              Text(turn.answer).font(.footnote).lineLimit(6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
      .padding(.horizontal, 6)
    }
  }

  private var recordButton: some View {
    HStack {
      Image(systemName: session.recording ? "waveform" : "mic.fill")
      Text(session.recording
           ? "\(session.elapsed)s"
           : label("按住说话", "Hold to talk"))
    }
    .font(.headline)
    .frame(maxWidth: .infinity, minHeight: 48)
    .background(session.recording ? Color.red : Color.accentColor, in: Capsule())
    .foregroundStyle(.white)
    .contentShape(Capsule())
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { _ in
          if !session.recording { session.startRecording() }
        }
        .onEnded { value in
          session.stopRecording(cancel: value.translation.height < -55)
        }
    )
    .accessibilityLabel(label("按住录音，上滑取消", "Hold to record, slide up to cancel"))
  }
}
