import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var clipboardChannel: FlutterMethodChannel?
  private var menuChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    title = "AI Link"
    minSize = NSSize(width: 600, height: 500)
    setContentSize(NSSize(width: 1100, height: 760))
    setFrameAutosaveName("AILinkMainWindow")
    if !setFrameUsingName("AILinkMainWindow") { center() }

    clipboardChannel = FlutterMethodChannel(
      name: "between_models/clipboard",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    clipboardChannel?.setMethodCallHandler { call, result in
      guard call.method == "setHtml" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let plain = arguments["plain"] as? String,
            let html = arguments["html"] as? String else {
        result(FlutterError(code: "invalid_arguments", message: "Missing clipboard content", details: nil))
        return
      }
      let item = NSPasteboardItem()
      item.setString(plain, forType: .string)
      item.setString(html, forType: .html)
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      if pasteboard.writeObjects([item]) {
        result(nil)
      } else {
        result(FlutterError(code: "clipboard_failed", message: "Could not copy content", details: nil))
      }
    }

    super.awakeFromNib()
    menuChannel = FlutterMethodChannel(
      name: "between_models/desktop_menu",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    installChatMenus()
  }

  private func installChatMenus() {
    guard let mainMenu = NSApp.mainMenu else { return }
    if let appMenu = mainMenu.items.first?.submenu {
      // Reuse the template's disabled Settings item so ⌘, has one target.
      let settings = appMenu.items.first(where: { $0.keyEquivalent == "," })
        ?? NSMenuItem(title: "Settings…", action: nil, keyEquivalent: ",")
      settings.title = "Settings…"
      settings.action = #selector(openSettings)
      settings.target = self
      if settings.menu == nil { appMenu.insertItem(settings, at: 2) }
    }
    let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
    let fileMenu = NSMenu(title: "File")
    let newChat = NSMenuItem(title: "New Conversation", action: #selector(newConversation), keyEquivalent: "n")
    newChat.target = self
    fileMenu.addItem(newChat)
    fileItem.submenu = fileMenu
    mainMenu.insertItem(fileItem, at: 1)
  }

  @objc private func newConversation() {
    menuChannel?.invokeMethod("newConversation", arguments: nil)
  }

  @objc private func openSettings() {
    menuChannel?.invokeMethod("settings", arguments: nil)
  }
}
