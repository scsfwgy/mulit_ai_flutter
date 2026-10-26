import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private let status = UILabel()
  private let done = UIButton(type: .system)
  private var task: Task<Void, Never>?
  private var completed = false
  private var started = false
  private var total = 0
  private var files = [[String: Any]]()
  private var directory: URL?

  private func text(_ en: String, _ zh: String, _ traditional: String) -> String {
    let language = UserDefaults(suiteName: ShareInbox.group)?.string(forKey: "language")
      ?? Locale.preferredLanguages.first ?? "en"
    if language.hasPrefix("zh") {
      return language == "zh-TW" || language.contains("Hant") || language.contains("HK")
        ? traditional : zh
    }
    return en
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    status.numberOfLines = 0
    status.textAlignment = .center
    status.text = text("Receiving shared content…", "正在接收分享内容…", "正在接收分享內容…")
    done.setTitle(text("Cancel", "取消", "取消"), for: .normal)
    done.addTarget(self, action: #selector(close), for: .touchUpInside)
    let stack = UIStackView(arrangedSubviews: [status, done])
    stack.axis = .vertical
    stack.spacing = 24
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !started else { return }
    started = true
    task = Task { await receive() }
  }

  private func receive() async {
    do {
      guard let root = ShareInbox.root else { throw CocoaError(.fileNoSuchFile) }
      let dir = root.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString)", isDirectory: true)
      directory = dir
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      var protectedRoot = root
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try protectedRoot.setResourceValues(values)
      let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
        .flatMap { $0.attachments ?? [] }
      guard !providers.isEmpty, providers.count <= 9 else { throw CocoaError(.fileWriteOutOfSpace) }
      for provider in providers {
        try Task.checkCancellation()
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
          let suggestedName = provider.suggestedName
          try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, error in
              do {
                if let error = error { throw error }
                guard let url = value as? URL else { throw CocoaError(.fileReadUnknown) }
                try self.copy(url, name: suggestedName ?? url.lastPathComponent)
                continuation.resume()
              } catch { continuation.resume(throwing: error) }
            }
          }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
          let value = try await loadItem(provider, type: UTType.url.identifier)
          guard let url = value as? URL else { throw CocoaError(.fileReadCorruptFile) }
          try saveText(url.absoluteString)
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
          let value = try await loadItem(provider, type: UTType.plainText.identifier)
          guard let string = value as? String else { throw CocoaError(.fileReadCorruptFile) }
          try saveText(string)
        } else if let type = provider.registeredTypeIdentifiers.first(where: {
          UTType($0)?.conforms(to: .data) == true
        }) {
          try await loadFile(provider, type: type)
        } else { throw CocoaError(.fileReadUnsupportedScheme) }
      }
      try Task.checkCancellation()
      let json = try JSONSerialization.data(withJSONObject: ["files": files])
      try json.write(to: dir.appendingPathComponent("ready.json"), options: .atomic)
      completed = true
      status.text = text("Saved. Open AI Link to ask about this content in a new conversation.",
                         "已保存。请打开 AI Link，在新对话中围绕这些内容提问。",
                         "已儲存。請開啟 AI Link，在新對話中圍繞這些內容提問。")
    } catch {
      if let directory = directory { try? FileManager.default.removeItem(at: directory) }
      status.text = text("Unable to receive this share. Use up to 9 files, 30 MB per file and 90 MB total, then share again.",
                         "接收失败。请确认不超过 9 个文件、单个 30 MB、合计 90 MB，然后重新分享。",
                         "接收失敗。請確認不超過 9 個檔案、單個 30 MB、合計 90 MB，然後重新分享。")
    }
    done.setTitle(text("Done", "完成", "完成"), for: .normal)
    completed = true
  }

  private func loadItem(_ provider: NSItemProvider, type: String) async throws -> NSSecureCoding {
    try await withCheckedThrowingContinuation { continuation in
      provider.loadItem(forTypeIdentifier: type, options: nil) { value, error in
        if let error = error { continuation.resume(throwing: error) }
        else if let value = value { continuation.resume(returning: value) }
        else { continuation.resume(throwing: CocoaError(.fileReadUnknown)) }
      }
    }
  }

  private func loadFile(_ provider: NSItemProvider, type: String) async throws {
    // Provider temporary URLs are valid only during this completion handler.
    let suggestedName = provider.suggestedName
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
        do {
          if let error = error { throw error }
          guard let url = url else { throw CocoaError(.fileReadUnknown) }
          try self.copy(url, name: suggestedName ?? url.lastPathComponent)
          continuation.resume()
        } catch { continuation.resume(throwing: error) }
      }
    }
  }

  private func saveText(_ string: String) throws {
    guard let directory = directory, let data = string.data(using: .utf8),
          !data.isEmpty, data.count <= 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
    total += data.count
    guard total <= 90 * 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
    let name = "text_\(files.count).txt"
    try data.write(to: directory.appendingPathComponent(name))
    files.append(["file": name, "name": "Shared text.txt", "sharedText": true])
  }

  private func copy(_ url: URL, name: String) throws {
    guard let directory = directory else { throw CocoaError(.fileNoSuchFile) }
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    let destination = directory.appendingPathComponent("file_\(files.count)")
    FileManager.default.createFile(atPath: destination.path, contents: nil)
    let source = try FileHandle(forReadingFrom: url)
    let target = try FileHandle(forWritingTo: destination)
    defer { try? source.close(); try? target.close() }
    var size = 0
    while let chunk = try source.read(upToCount: 64 * 1024), !chunk.isEmpty {
      size += chunk.count
      total += chunk.count
      guard size <= 64 * 1024 * 1024, total <= 90 * 1024 * 1024 else {
        throw CocoaError(.fileWriteOutOfSpace)
      }
      try target.write(contentsOf: chunk)
    }
    guard size > 0 else { throw CocoaError(.fileReadCorruptFile) }
    files.append(["file": destination.lastPathComponent, "name": (name as NSString).lastPathComponent])
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if !completed { task?.cancel() }
  }

  @objc private func close() {
    if completed { extensionContext?.completeRequest(returningItems: nil) }
    else {
      task?.cancel()
      extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }
  }
}
