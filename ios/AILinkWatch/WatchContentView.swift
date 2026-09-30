import SwiftUI

struct WatchContentView: View {
  @ObservedObject var session: WatchChatSession

  private var chinese: Bool { session.chinese }
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
    .blur(radius: session.recording ? 4 : 0)
    .overlay {
      if session.recording { recordingOverlay.allowsHitTesting(false) }
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
        .onChanged { value in
          if !session.recording { session.startRecording() }
          session.cancelling = value.translation.height < -55
        }
        .onEnded { value in
          session.stopRecording(cancel: value.translation.height < -55)
        }
    )
    .accessibilityLabel(label("按住录音，上滑取消", "Hold to record, slide up to cancel"))
  }

  private var recordingOverlay: some View {
    let accent = session.cancelling ? Color.red : Color.accentColor
    let seconds = session.elapsedMs / 1000
    let time = String(format: "%02d:%02d.%d", seconds / 60, seconds % 60, session.elapsedMs % 1000 / 100)
    return GeometryReader { geometry in
      let diameter = min(geometry.size.width, geometry.size.height) * 0.92
      ZStack {
        Color.black.opacity(0.6).ignoresSafeArea()
        VStack(spacing: 4) {
          Image(systemName: session.cancelling ? "xmark" : "mic.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: 28, height: 28)
            .background(accent.opacity(0.15), in: Circle())
          Text(session.cancelling ? label("松开取消录音", "Release to cancel") : label("正在录音", "Recording"))
            .font(.system(size: 13, weight: .semibold))
          TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            HStack(spacing: 3) {
              ForEach(0..<19) { index in
                let weight = 1 - Double(abs(index - 9)) / 10
                let pulse = abs(sin(timeline.date.timeIntervalSinceReferenceDate / 1.5 * .pi * 2 + Double(index) * 0.63)) * 0.72 + 0.28
                Capsule().fill(accent)
                  .frame(width: 2.5, height: 3 + 23 * (0.15 + session.level * 0.85) * weight * pulse)
              }
            }.frame(height: 26)
          }
          Text(time).font(.system(size: 22, weight: .semibold, design: .monospaced))
          Text(session.cancelling ? label("松开取消", "Release to cancel") : label("松开转写", "Release to transcribe"))
            .font(.system(size: 11)).foregroundStyle(session.cancelling ? accent : .secondary)
          if !session.cancelling {
            Text(label("上滑取消", "Slide up to cancel"))
              .font(.system(size: 10)).foregroundStyle(.secondary)
          }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(width: diameter * 0.76)
        .frame(width: diameter, height: diameter)
        .background(.regularMaterial, in: Circle())
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
  }
}
