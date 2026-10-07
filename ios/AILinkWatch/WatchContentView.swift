import SwiftUI

struct WatchContentView: View {
  @ObservedObject var session: WatchChatSession
  @ObservedObject private var purchases = ApplePurchaseStore.shared
  @Environment(\.scenePhase) private var scenePhase
  @State private var page = 0
  @AppStorage("watchGestureGuideSeen") private var guideSeen = false
  @AppStorage("watchSimpleRecording") private var simpleRecording = false
  @GestureState private var holdingChat = false
  @State private var recordingPressStarted = false
  @State private var confirmClear = false
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
    .safeAreaInset(edge: .top, spacing: 4) {
      if page == 0 && guideSeen && (session.processingLabel != nil || session.loadingAudio || session.playing) {
        speechIndicator.frame(height: 26).allowsHitTesting(false)
      }
    }
    .tint(accent)
    .blur(radius: session.recording ? 4 : 0)
    .overlay {
      if session.recording { recordingOverlay.allowsHitTesting(false) }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        session.refreshPhoneSettings()
        session.refreshPurchases()
        Task { await purchases.refresh() }
      }
      else { session.cancelRecording() }
    }
    .alert(label("需要配置服务", "Services required"), isPresented: $session.configurationPrompt) {
      Button(label("查看设置", "View settings")) { page = 1 }
      Button(label("知道了", "OK"), role: .cancel) {}
    } message: {
      Text(session.configurationGuidance)
    }
    .onAppear { session.refreshPhoneSettings() }
    .alert(label("清除手表数据？", "Clear watch data?"), isPresented: $confirmClear) {
      Button(label("清除", "Clear"), role: .destructive) { session.clearLocalData() }
      Button(label("取消", "Cancel"), role: .cancel) {}
    } message: {
      Text(label("将删除手表保存的密钥、问答和未同步记录，手机数据保留。重新使用需同步手机配置。",
        "Deletes watch credentials, chats and pending sync records. Phone data remains. Sync phone settings to use again."))
    }
    .onOpenURL { url in
      guard WatchChatShortcut.opensChat(url) else { return }
      page = 0
    }
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
      Text(label("双击切换聊天与设置，设置页右滑返回；上下滑动查看内容。",
        "Double-tap to switch chat and settings. Swipe right to leave settings; swipe up or down to read."))
    }.font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
  }

  private var chatPage: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          Color.clear.frame(height: 0).id("top")
          if !session.status.isEmpty && session.processingLabel == nil {
            Text(session.status).font(.system(size: 12)).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          if !session.transcript.isEmpty {
            Text("\(label("我", "Me")) · \(session.transcript)")
              .font(.system(size: 12)).foregroundStyle(.secondary)
          }
          if !session.answer.isEmpty {
            WatchMarkdownView(session.answer)
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
              WatchMarkdownView(turn.answer)
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
        VStack(spacing: 4) {
          Text(label("设置", "Settings")).font(.headline)
          Text(label("双击或右滑返回聊天", "Double-tap or swipe right to chat"))
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        Text(session.connectionLabel).font(.system(size: 12)).foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        Button(label("开启新话题", "Start new topic")) {
          session.startNewTopic()
          page = 0
        }.disabled(session.busy || session.recording)
        Text(label("清空当前聊天；历史问答同步保存到手机，离线记录将在重连后同步。",
          "Clears the current chat. History is saved to your phone; offline chats sync after reconnecting."))
          .font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        VStack(alignment: .leading, spacing: 6) {
          Text(label("录音界面", "Recording view")).font(.system(size: 12)).foregroundStyle(.secondary)
          HStack(spacing: 4) {
            recordingMode(label("新手模式", "Beginner"), simple: false)
            recordingMode(label("简洁模式", "Simple"), simple: true)
          }
          Text(label("新手：显示方向提示、波形和计时。\n简洁：仅显示语音图标和音量环。\n两种模式的录音手势相同。",
            "Beginner: hints, waveform and timer.\nSimple: voice icon and volume ring.\nBoth use the same recording gestures."))
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
        serviceDetails(label("文本模型", "Text model"),
          provider: session.configuration?.providerName, model: session.configuration?.model)
        serviceDetails(label("语音识别", "Speech recognition"),
          provider: session.configuration?.asr?.providerName, model: session.configuration?.asr?.asrModel)
        serviceDetails(label("语音朗读", "Speech synthesis"),
          provider: session.configuration?.tts?.providerName, model: session.configuration?.tts?.ttsModel,
          voice: session.configuration?.tts?.voice, showVoice: true)
        VStack(alignment: .leading, spacing: 3) {
          Text(label("联网搜索", "Web search")).font(.system(size: 13, weight: .semibold))
          serviceField(label("状态", "Status"), value: session.configuration?.searchEnabled == true
            ? label("已开启", "Enabled") : label("已关闭", "Disabled"))
          serviceField(label("提供商", "Provider"), value: session.configuration?.search?.name)
          serviceField(label("搜索服务", "Search service"), value: session.configuration?.search?.service == "bocha"
            ? label("博查", "Bocha") : session.configuration?.search?.serviceLabel)
        }.frame(maxWidth: .infinity, alignment: .leading)
        if !session.textReady || !session.asrReady {
          Text(session.configurationGuidance).font(.system(size: 11)).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        Toggle(label("自动播报回答", "Speak replies automatically"), isOn: Binding(
          get: { session.speak }, set: { session.setSpeak($0) }
        ))
        if purchases.enabled {
          Text(label(purchases.permanent ? "已永久解锁" : purchases.canUse ? "7 天试用中" : "试用与永久解锁请在 iPhone 操作",
                     purchases.permanent ? "Permanently unlocked" : purchases.canUse ? "7-day trial active" : "Start trial or unlock on iPhone"))
            .font(.system(size: 11)).foregroundStyle(.secondary)
          Button(label("刷新购买权益", "Refresh purchases")) {
            session.refreshPurchases()
          }
          .disabled(session.syncingPurchases)
          if !session.purchasesStatus.isEmpty {
            Text(session.purchasesStatus).font(.system(size: 11)).foregroundStyle(.secondary)
          }
        }
        Button(label("同步手机配置", "Sync phone settings")) { session.refreshPhoneSettings(manual: true) }
        if !session.settingsStatus.isEmpty {
          Text(session.settingsStatus).font(.system(size: 11)).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        if session.playing || session.loadingAudio {
          Button(label("停止播放", "Stop playback")) { session.stopPlayback() }
        }
        gestureInstructions
        Text(label("模型、语音与联网服务在手机端设置", "Set up text, voice and search services on phone"))
          .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        Text(label("优先由手表请求；手表网络不可用时尝试手机。密钥保存在手表钥匙串。", "Uses the watch first, then tries the phone if the watch network is unavailable. Credentials are stored in watch Keychain."))
          .font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        Button(label("清除手表配置和问答", "Clear watch settings and chats"), role: .destructive) { confirmClear = true }
          .disabled(session.busy || session.recording || session.syncingSettings)
        Button(label("返回聊天", "Back to chat")) { page = 0 }
          .buttonStyle(.plain).foregroundStyle(accent).padding(.vertical, 8)
      }.font(.system(size: 13)).padding(.horizontal, 8)
    }
    .contentShape(Rectangle())
    .highPriorityGesture(TapGesture(count: 2).onEnded { page = 0 })
    .simultaneousGesture(
      DragGesture(minimumDistance: 20).onEnded { value in
        let translation = value.translation
        if translation.width > 48 && translation.width > abs(translation.height) * 1.5 {
          page = 0
        }
      }
    )
    .accessibilityHint(label("双击或右滑返回聊天", "Double-tap or swipe right to chat"))
  }

  private var speechIndicator: some View {
    TimelineView(.animation(minimumInterval: 0.08)) { timeline in
      let time = timeline.date.timeIntervalSinceReferenceDate
      HStack(spacing: 6) {
        if session.processingLabel != nil || session.loadingAudio {
          Circle().trim(from: 0.15, to: 0.95)
            .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(time * 260))
        } else {
          HStack(spacing: 2) {
            ForEach(0..<5) { index in
              Capsule().fill(accent)
                .frame(width: 3, height: 5 + 11 * (sin(time * 7 + Double(index) * 1.3) + 1) / 2)
            }
          }.frame(width: 23, height: 18)
        }
        Text(session.processingLabel ?? (session.loadingAudio ? label("语音加载中", "Loading audio") : label("播放语音中", "Playing audio")))
          .font(.system(size: 10))
      }.frame(height: 18).fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
    }
  }

  private func serviceDetails(_ title: String, provider: String?, model: String?, voice: String? = nil, showVoice: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.system(size: 13, weight: .semibold))
      serviceField(label("提供商", "Provider"), value: provider,
        fallback: model?.isEmpty == false ? label("同步后显示", "Sync to display") : nil)
      serviceField(label("模型 ID", "Model ID"), value: model)
      if showVoice { serviceField(label("音色", "Voice"), value: voice) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
  }

  private func recordingMode(_ title: String, simple: Bool) -> some View {
    Button { simpleRecording = simple } label: {
      Text(title).font(.system(size: 12, weight: .medium))
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .foregroundStyle(simpleRecording == simple ? .white : .secondary)
        .background(simpleRecording == simple ? accent : Color.secondary.opacity(0.15),
          in: RoundedRectangle(cornerRadius: 10))
    }.buttonStyle(.plain)
      .accessibilityAddTraits(simpleRecording == simple ? .isSelected : [])
  }

  private func serviceField(_ title: String, value: String?, fallback: String? = nil) -> some View {
    let display = value.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    return VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
      Text(display ?? fallback ?? label("未配置", "Not configured"))
        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
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
        if simpleRecording {
          TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            let pulse = (sin(timeline.date.timeIntervalSinceReferenceDate * .pi * 2) + 1) / 2
            let size = diameter * 0.7
            ZStack {
              Circle().stroke(color.opacity(0.45), lineWidth: 2)
                .scaleEffect(1.04 + session.level * 0.1 + pulse * 0.02)
              Circle().fill(color.opacity(0.2))
              Image(systemName: cancelling ? "xmark" : reviewing ? "text.alignleft" : "mic.fill")
                .font(.system(size: size * 0.35, weight: .medium)).foregroundStyle(color)
            }.frame(width: size, height: size)
              .accessibilityLabel(cancelling ? label("松开取消", "Release to cancel")
                : reviewing ? label("松开转文字", "Release to transcribe") : label("正在录音", "Recording"))
          }
        } else {
          VStack(spacing: 7) {
            HStack {
              recordingTarget("arrow.up.left", label("取消", "Cancel"), selected: cancelling, color: .red)
              Spacer(minLength: 8)
              recordingTarget("arrow.up.right", label("转文字", "Text"), selected: reviewing, color: .green)
            }
            Image(systemName: cancelling ? "xmark" : reviewing ? "text.alignleft" : "mic.fill")
              .font(.system(size: 28, weight: .medium)).foregroundStyle(color)
              .frame(width: 64, height: 64).background(color.opacity(0.15), in: Circle())
            TimelineView(.animation(minimumInterval: 0.05)) { timeline in
              HStack(spacing: 3) {
                ForEach(0..<19) { index in
                  let weight = 1 - Double(abs(index - 9)) / 10
                  let pulse = abs(sin(timeline.date.timeIntervalSinceReferenceDate / 1.5 * .pi * 2 + Double(index) * 0.63)) * 0.72 + 0.28
                  Capsule().fill(color)
                    .frame(width: 2.5, height: 2 + 12 * (0.15 + session.level * 0.85) * weight * pulse)
                }
              }.frame(height: 14)
            }
            Text(time).font(.system(size: 18, weight: .medium, design: .monospaced))
            Text(cancelling ? label("松开取消", "Release to cancel") : reviewing ? label("松开转文字", "Release to transcribe") : label("松开发送", "Release to send"))
              .font(.system(size: 11)).foregroundStyle(session.releaseAction == .send ? .secondary : color)
          }
          .lineLimit(1).minimumScaleFactor(0.75)
          .frame(width: diameter * 0.72).frame(width: diameter, height: diameter)
          .background(.regularMaterial, in: Circle())
        }
      }.frame(width: geometry.size.width, height: geometry.size.height)
    }
  }
  private func recordingTarget(_ icon: String, _ title: String, selected: Bool, color: Color) -> some View {
    HStack(spacing: 3) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .medium))
      Text(title).font(.system(size: 10))
    }.foregroundStyle(selected ? color : .secondary)
      .padding(.horizontal, 5).padding(.vertical, 4)
      .background(selected ? color.opacity(0.15) : .clear, in: Capsule())
  }

}
