import SwiftUI

struct WatchContentView: View {
  @ObservedObject var session: WatchChatSession
  @Environment(\.scenePhase) private var scenePhase
  @State private var page = 0
  @State private var expanded: Set<String> = []
  @State private var actionPressStarted = false
  @State private var confirmingPress = false
  private let accent = Color(red: 24 / 255, green: 126 / 255, blue: 240 / 255)

  private func label(_ zh: String, _ en: String) -> String { session.chinese ? zh : en }

  var body: some View {
    TabView(selection: $page) {
      chatPage.tag(0)
      settingsPage.tag(1)
    }
    .tabViewStyle(.page(indexDisplayMode: .never))
    .tint(accent)
    .blur(radius: session.recording ? 4 : 0)
    .overlay {
      if session.recording { recordingOverlay.allowsHitTesting(false) }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { session.refreshPhoneSettings() }
      else { session.cancelRecording() }
    }
    .alert(label("需要配置服务", "Services required"), isPresented: $session.configurationPrompt) {
      Button(label("查看设置", "View settings")) { page = 1 }
      Button(label("知道了", "OK"), role: .cancel) {}
    } message: {
      Text(session.configurationGuidance)
    }
    .onAppear { session.refreshPhoneSettings() }
    .onChange(of: page) { _, value in
      if value != 0 { session.cancelRecording() }
    }
  }

  private var chatPage: some View {
    VStack(spacing: 5) {
      Button { page = 1 } label: {
        Text(label("最近问答  ›", "Recent chats  ›")).font(.system(size: 15, weight: .semibold))
      }
      .buttonStyle(.plain)
      if !session.status.isEmpty {
        Text(session.status).font(.system(size: 12)).foregroundStyle(.secondary)
          .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
      }
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: 0).id("top")
            if !session.transcript.isEmpty {
              Text("\(label("我", "Me")) · \(session.transcript)")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if !session.answer.isEmpty {
              Text(session.answer).font(.system(size: 15)).padding(.bottom, 16)
            }
            if session.turns.isEmpty && session.transcript.isEmpty && session.answer.isEmpty {
              Text(label("还没有问答", "No chats yet")).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            ForEach(Array(session.visibleHistory.reversed().enumerated()), id: \.element.id) { index, turn in
              let latest = index == 0 && session.transcript.isEmpty && session.answer.isEmpty
              VStack(alignment: .leading, spacing: 4) {
                if latest {
                  Text("\(label("我", "Me")) · \(turn.question)")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                  Button {
                    if !expanded.insert(turn.id).inserted { expanded.remove(turn.id) }
                  } label: {
                    Text("\(turn.question) → \(turn.answer)")
                      .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                      .frame(maxWidth: .infinity, alignment: .leading)
                  }.buttonStyle(.plain)
                  .accessibilityHint(label("点按展开或收起回答", "Tap to expand or collapse the answer"))
                }
                if latest || expanded.contains(turn.id) {
                  Text(turn.answer).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, latest ? 16 : 4)
                }
              }
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: session.scrollGeneration) { _, _ in proxy.scrollTo("top", anchor: .top) }
      }
      if session.visibleHistory.count > 1 {
        Text(label("上滑查看更早问答", "Swipe up for older chats"))
          .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
      }
      recordButton
      if session.awaitingConfirmation {
        Button(label("重新录音", "Record again")) { session.resetForRecording() }
          .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 8)
  }

  private var settingsPage: some View {
    ScrollView {
      VStack(spacing: 10) {
        Button { page = 0 } label: {
          Text(label("‹  设置", "‹  Settings")).font(.headline)
        }.buttonStyle(.plain)
        Text(session.connectionLabel).font(.system(size: 12)).foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        Text(session.modelSummary).font(.system(size: 12)).foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        if !session.textReady || !session.asrReady {
          Text(session.configurationGuidance).font(.system(size: 11)).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        Toggle(label("识别后自动发送", "Send after transcription"), isOn: Binding(
          get: { session.autoSend }, set: { session.setAutoSend($0) }
        ))
        Toggle(label("自动播报回答", "Speak replies automatically"), isOn: Binding(
          get: { session.speak }, set: { session.setSpeak($0) }
        ))
        Button(label("同步手机配置", "Sync phone settings")) { session.refreshPhoneSettings() }
          .disabled(session.syncingSettings)
        if !session.settingsStatus.isEmpty {
          Text(session.settingsStatus).font(.system(size: 11)).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        if session.playing {
          Button(label("停止播放", "Stop playback")) { session.stopPlayback() }
        }
        Text(label("模型与语音服务在手机端设置", "Set up text and voice services on phone"))
          .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        Text(label("语音和模型请求由配对 iPhone 处理", "The paired iPhone handles voice and model requests"))
          .font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
      }.font(.system(size: 13)).padding(.horizontal, 8)
    }
  }

  private var recordButton: some View {
    Text(session.actionLabel)
      .font(.system(size: 16, weight: .semibold))
      .frame(maxWidth: .infinity, minHeight: 44)
      .background(accent.opacity(session.busy ? 0.45 : 1), in: Capsule())
      .foregroundStyle(.white)
      .contentShape(Capsule())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let beginning = !actionPressStarted
            if beginning {
              actionPressStarted = true
              confirmingPress = session.awaitingConfirmation && !session.busy
            }
            guard !session.busy, !session.awaitingConfirmation else { return }
            if beginning { session.startRecording() }
            session.cancelling = value.translation.height < -55
          }
          .onEnded { value in
            if confirmingPress && session.awaitingConfirmation { session.confirmTranscript() }
            else { session.stopRecording(cancel: value.translation.height < -55) }
            actionPressStarted = false
            confirmingPress = false
          }
      )
      .accessibilityLabel(session.awaitingConfirmation ? label("确认发送", "Confirm and send")
        : label("按住录音，上滑取消", "Hold to record, slide up to cancel"))
  }

  private var recordingOverlay: some View {
    let color = session.cancelling ? Color.red : accent
    let seconds = session.elapsedMs / 1000
    let time = String(format: "%02d:%02d.%d", seconds / 60, seconds % 60, session.elapsedMs % 1000 / 100)
    return GeometryReader { geometry in
      let diameter = min(geometry.size.width, geometry.size.height) * 0.92
      ZStack {
        Color.black.opacity(0.6).ignoresSafeArea()
        VStack(spacing: 4) {
          Image(systemName: session.cancelling ? "xmark" : "mic.fill")
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
            .frame(width: 28, height: 28).background(color.opacity(0.15), in: Circle())
          Text(session.cancelling ? label("松开取消录音", "Release to cancel") : label("正在录音", "Recording"))
            .font(.system(size: 13, weight: .semibold))
          TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            HStack(spacing: 3) {
              ForEach(0..<19) { index in
                let weight = 1 - Double(abs(index - 9)) / 10
                let pulse = abs(sin(timeline.date.timeIntervalSinceReferenceDate / 1.5 * .pi * 2 + Double(index) * 0.63)) * 0.72 + 0.28
                Capsule().fill(color)
                  .frame(width: 2.5, height: 3 + 23 * (0.15 + session.level * 0.85) * weight * pulse)
              }
            }.frame(height: 26)
          }
          Text(time).font(.system(size: 22, weight: .semibold, design: .monospaced))
          Text(session.cancelling ? label("松开取消", "Release to cancel") : label("松开转写", "Release to transcribe"))
            .font(.system(size: 11)).foregroundStyle(session.cancelling ? color : .secondary)
          if !session.cancelling {
            Text(label("上滑取消", "Slide up to cancel")).font(.system(size: 10)).foregroundStyle(.secondary)
          }
        }
        .lineLimit(1).minimumScaleFactor(0.75)
        .frame(width: diameter * 0.76).frame(width: diameter, height: diameter)
        .background(.regularMaterial, in: Circle())
      }.frame(width: geometry.size.width, height: geometry.size.height)
    }
  }
}
