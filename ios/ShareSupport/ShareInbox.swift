import Foundation

/// Contains only incoming user files, never model credentials or chat databases.
enum ShareInbox {
  static var group: String { Bundle.main.object(forInfoDictionaryKey: "AILinkShareGroup") as? String ?? "" }
  static var root: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
      .appendingPathComponent("share_inbox", isDirectory: true)
  }

  static func first() throws -> [String: Any]? {
    guard let root = root, FileManager.default.fileExists(atPath: root.path) else { return nil }
    let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
    for directory in directories {
      let manifest = directory.appendingPathComponent("ready.json")
      guard FileManager.default.fileExists(atPath: manifest.path) else { continue }
      let data = try Data(contentsOf: manifest)
      guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let files = json["files"] as? [[String: Any]] else { continue }
      return ["id": directory.lastPathComponent, "files": files.map { item in
        ["path": directory.appendingPathComponent(item["file"] as? String ?? "").path,
         "name": item["name"] as? String ?? "Shared file", "sharedText": item["sharedText"] as? Bool ?? false] as [String: Any]
      }]
    }
    return nil
  }

  static func acknowledge(_ id: String) throws {
    guard id.range(of: "^[0-9]+-[A-Fa-f0-9-]{36}$", options: .regularExpression) != nil,
          let root = root else { return }
    let directory = root.appendingPathComponent(id, isDirectory: true)
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }
}
