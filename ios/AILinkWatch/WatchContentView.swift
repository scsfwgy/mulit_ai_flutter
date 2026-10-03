import SwiftUI

struct WatchContentView: View {
  @ObservedObject var session: WatchChatSession
  @Environment(\.scenePhase) private var scenePhase
  @State private var page = 0
  @AppStorage("watchGestureGuideSeen") private var guideSeen = false
  @GestureState private var holdingChat = false
  @State private var recordingPressStarted = false
  private let accent = Color(red: 24 / 255, green: 126 / 255, blue: 240 / 255)

  private func label(_ zh: String, _ en: String) -> String { session.chinese ? zh : en }

  var body: some View {
    ZStack {
      chatPage
        .opacity(page == 0 && guideSeen ? 1 : 0)
        .allowsHitTesting(page == 0 && guideSeen)
        .accessibilityHidden(page != 0 || !guideSeen)
      if page == 1 { settingsPage }
      else if !guideSeen { introduction }
    }
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
    .onChange(of: holdingChat) { _, holding in
      // Release or interruption must also stop a pending recording preflight.
      if !holding && recordingPressStarted {
        session.cancelRecording()
        recordingPressStarted = false
      }
    }
  }

  private var introduction: some View {
    ScrollView {
      VStack(spacing: 12) {
        Text(label("开始聊天", "Start chatting")).font(.headline)
        gestureInstructions
        Button(label("知道了", "Got it")) { guideSeen = true }
      }.padding(.horizontal, 8).padding(.vertical, 8)
    }
  }

  private var gestureInstructions: some View {
    VStack(spacing: 10) {
      Text(label("长按屏幕说话，松手发送；左上滑取消，右上滑转文字后确认。",
        "Hold to speak, release to send. Slide up-left to cancel, up-right to review text."))
      Text(label("双击聊天进入设置，上下滑动查看聊天。",
        "Double-tap the chat for settings. Swipe up or down to read."))
    }.font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
  }

  private var chatPage: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          Color.clear.frame(height: 0).id("top")
          if !session.status.isEmpty {
            Text(session.status).font(.system(size: 12)).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          if !session.transcript.isEmpty {
            Text("\(label("我", "Me")) · \(session.transcript)")
              .font(.system(size: 12)).foregroundStyle(.secondary)
          }
          if !session.answer.isEmpty {
            Text(session.answer).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
              .padding(.bottom, 8)
          }
          if session.awaitingConfirmation {
            Button(label("确认发送", "Confirm and send")) { session.confirmTranscript() }
              .frame(maxWidth: .infinity)
            Button(label("重新录音", "Record again")) { session.resetForRecording() }
              .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
              .frame(maxWidth: .infinity)
          }
          if session.turns.isEmpty && session.transcript.isEmpty && session.answer.isEmpty {
            Text(label("还没有问答", "No chats yet")).font(.system(size: 13)).foregroundStyle(.secondary)
          }
          ForEach(session.visibleHistory.reversed()) { turn in
            VStack(alignment: .leading, spacing: 4) {
              Text("\(label("我", "Me")) · \(turn.question)")
                .font(.system(size: 12)).foregroundStyle(.secondary)
              Text(turn.answer).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
            }.padding(.bottom, 8)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.bottom, 12)
      }
      .scrollDisabled(recordingPressStarted)
      .contentShape(Rectangle())
      .onTapGesture(count: 2) { page = 1 }
      .simultaneousGesture(recordingGesture)
      .accessibilityHint(label("长按录音，双击进入设置", "Hold to record, double-tap for settings"))
      .onChange(of: session.scrollGeneration) { _, _ in proxy.scrollTo("top", anchor: .top) }
    }
  }

  private var recordingGesture: some Gesture {
    LongPressGesture(minimumDuration: 0.5, maximumDistance: 10)
      .sequenced(before: DragGesture(minimumDistance: 0))
      .updating($holdingChat) { value, state, _ in
        if case .second(true, _) = value { state = true }
      }
      .onChanged { value in
        guard case .second(true, let drag) = value, !session.busy else { return }
        if !recordingPressStarted {
          recordingPressStarted = true
          session.startRecording()
        }
        session.releaseAction = WatchReleaseAction.fromDrag(drag?.translation ?? .zero)
      }
      .onEnded { value in
        guard recordingPressStarted else { return }
        let action: WatchReleaseAction
        if case .second(true, let drag) = value {
          action = WatchReleaseAction.fromDrag(drag?.translation ?? .zero)
        } else { action = .cancel }
        session.stopRecording(action: action)
        recordingPressStarted = false
      }
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
        gestureInstructions
        Text(label("模型与语音服务在手机端设置", "Set up text and voice services on phone"))
          .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        Text(label("语音和模型请求由配对 iPhone 处理", "The paired iPhone handles voice and model requests"))
          .font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
      }.font(.system(size: 13)).padding(.horizontal, 8)
    }
  }

  private var recordingOverlay: some View {
    let cancelling = session.releaseAction == .cancel
    let reviewing = session.releaseAction == .review
    let color = cancelling ? Color.red : reviewing ? Color.green : accent
    let seconds = session.elapsedMs / 1000
    let time = String(format: "%02d:%02d.%d", seconds / 60, seconds % 60, session.elapsedMs % 1000 / 100)
    return GeometryReader { geometry in
      let diameter = min(geometry.size.width, geometry.size.height) * 0.92
      ZStack {
        Color.black.opacity(0.6).ignoresSafeArea()
        VStack(spacing: 4) {
          HStack(spacing: 14) {
            recordingTarget("arrow.up.left", label("取消", "Cancel"), selected: cancelling, color: .red)
            Image(systemName: cancelling ? "xmark" : reviewing ? "textformat" : "mic.fill")
              .font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
              .frame(width: 28, height: 28).background(color.opacity(0.15), in: Circle())
            recordingTarget("arrow.up.right", label("转文字", "Text"), selected: reviewing, color: .green)
          }
          Text(cancelling ? label("松开取消录音", "Release to cancel") : reviewing ? label("松开转文字", "Release to transcribe") : label("正在录音", "Recording"))
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
          Text(cancelling ? label("松开取消", "Release to cancel") : reviewing ? label("识别后确认发送", "Review before sending") : label("松开发送", "Release to send"))
            .font(.system(size: 11)).foregroundStyle(session.releaseAction == .send ? .secondary : color)
          Text(label("左上取消 · 右上确认", "↖ Cancel · Review ↗"))
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .lineLimit(1).minimumScaleFactor(0.75)
        .frame(width: diameter * 0.76).frame(width: diameter, height: diameter)
        .background(.regularMaterial, in: Circle())
      }.frame(width: geometry.size.width, height: geometry.size.height)
    }
  }
  private func recordingTarget(_ icon: String, _ title: String, selected: Bool, color: Color) -> some View {
    VStack(spacing: 2) {
      Image(systemName: icon)
        .font(.system(size: 13, weight: .semibold))
        .frame(width: 26, height: 26)
        .foregroundStyle(selected ? .white : .secondary)
        .background(selected ? color : .clear, in: Circle())
      Text(title).font(.system(size: 9)).foregroundStyle(selected ? color : .secondary)
    }
  }

}
