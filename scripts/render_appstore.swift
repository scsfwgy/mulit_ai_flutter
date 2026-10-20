#!/usr/bin/env swift
// Compose store layouts around application captures; never redraw app content.
import AppKit
import Foundation

struct Page: Decodable { let id, title, subtitle, phone, ipad: String; let watch: String? }
struct Creative: Decodable { let title, features, note: String }
struct Listing: Decodable { let screenshots: [Page]; let creativeAssets: Creative }
let args = CommandLine.arguments
precondition(args.count == 4, "Usage: render_appstore <repo> <listing.json> <output>")
let root = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[3])
let listing = try JSONDecoder().decode(Listing.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
func ink(_ hex: UInt32) -> NSColor {
  NSColor(srgbRed: CGFloat(hex >> 16 & 255)/255, green: CGFloat(hex >> 8 & 255)/255,
          blue: CGFloat(hex & 255)/255, alpha: 1)
}
func text(_ value: String, _ rect: NSRect, _ size: CGFloat, _ weight: NSFont.Weight = .regular, _ color: UInt32 = 0x132A40) {
  let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
  let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
    .foregroundColor: ink(color), .paragraphStyle: style]
  let bounds = (value as NSString).boundingRect(with: rect.size,
    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
  precondition(bounds.height <= rect.height + 3, "Text overflow: \(value)")
  (value as NSString).draw(in: rect, withAttributes: attributes)
}
func load(_ path: String) -> NSImage {
  guard let image = NSImage(contentsOf: root.appendingPathComponent(path)) else { fatalError("Missing capture \(path)") }
  return image
}
func card(_ shot: NSImage, _ rect: NSRect, radius: CGFloat = 48) {
  NSGraphicsContext.saveGraphicsState()
  let shadow = NSShadow(); shadow.shadowColor = ink(0x0C4769).withAlphaComponent(0.16)
  shadow.shadowBlurRadius = 55; shadow.shadowOffset = NSSize(width: 0, height: 16); shadow.set()
  NSColor.white.setFill(); NSBezierPath(roundedRect: rect.insetBy(dx: -8, dy: -8), xRadius: radius, yRadius: radius).fill()
  NSGraphicsContext.restoreGraphicsState()
  NSGraphicsContext.saveGraphicsState()
  NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
  shot.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
    respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
  NSGraphicsContext.restoreGraphicsState()
}
func render(_ w: Int, _ h: Int, _ file: URL, draw: () -> Void) throws {
  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
  cg.translateBy(x: 0, y: CGFloat(h)); cg.scaleBy(x: 1, y: -1)
  NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
  ink(0xF3F8FC).setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
  ink(0xDDF5F1).setFill(); NSBezierPath(ovalIn: NSRect(x: CGFloat(w)*0.38, y: -CGFloat(w)*0.28, width: CGFloat(w)*1.2, height: CGFloat(w)*1.2)).fill()
  ink(0xE0EDFC).setFill(); NSBezierPath(ovalIn: NSRect(x: -CGFloat(w)*0.5, y: CGFloat(h)-CGFloat(w)*0.6, width: CGFloat(w)*1.2, height: CGFloat(w)*1.2)).fill()
  draw(); NSGraphicsContext.restoreGraphicsState()
  try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
  let format: NSBitmapImageRep.FileType = file.pathExtension == "png" ? .png : .jpeg
  let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.96])!
  let opaque = NSBitmapImageRep(data: jpeg)!
  precondition(!opaque.hasAlpha)
  try (format == .png ? opaque.representation(using: .png, properties: [:])! : jpeg).write(to: file)
  print(file.path)
}
for (group,w,h) in [("APP_IPHONE_61",1206,2622),("APP_IPHONE_67",1320,2868),("APP_IPAD_PRO_3GEN_129",2752,2064)] {
  for (index,page) in listing.screenshots.enumerated() {
    let tablet = group.contains("IPAD"), scale = CGFloat(w)/1206
    let shot = load(tablet ? page.ipad : page.phone)
    try render(w,h,output.appendingPathComponent("screenshots/zh-Hans/\(group)/0\(index+1)-\(page.id).jpg")) {
      let cg = NSGraphicsContext.current!.cgContext
      if !tablet { cg.scaleBy(x: scale, y: scale) }
      text("AI Link", NSRect(x: tablet ? 180 : 100, y: tablet ? 150 : 100, width: 700, height: 90), tablet ? 72 : 55, .semibold, 0x0876CE)
      let lines = page.title.components(separatedBy: "\n")
      for (i,line) in lines.enumerated() {
        text(line, NSRect(x: tablet ? 180 : 100, y: (tablet ? 440 : 210)+CGFloat(i)*(tablet ? 155 : 127), width: tablet ? 1100 : 1030, height: tablet ? 160 : 140), tablet ? 130 : 110, .bold, i == 0 ? 0x132A40 : 0x0876CE)
      }
      text(page.subtitle, NSRect(x: tablet ? 180 : 100, y: tablet ? 850 : 490, width: tablet ? 900 : 1040, height: 135), tablet ? 50 : 43, .medium, 0x456579)
      if tablet {
        let rect = NSRect(x: 1210, y: 390, width: 1400, height: 1400*shot.size.height/shot.size.width)
        card(shot, rect)
        if let path = page.watch {
          let watch = load(path); card(watch, NSRect(x: 1980, y: 1290, width: 480, height: 480*watch.size.height/watch.size.width), radius: 72)
        }
        text(page.id == "models" ? "应用服务列表 · 需自备 API Key" : "真实应用界面 · 示例对话与配置", NSRect(x: 180, y: 1900, width: 1800, height: 80), 38, .regular, 0x617989)
      } else if let path = page.watch {
        card(shot, NSRect(x: 90, y: 680, width: 735, height: 735*shot.size.height/shot.size.width))
        let watch = load(path); card(watch, NSRect(x: 535, y: 1430, width: 560, height: 560*watch.size.height/watch.size.width), radius: 80)
        text("先在 iPhone 配置模型服务", NSRect(x: 100, y: 2370, width: 1000, height: 75), 39, .medium, 0x456579)
        text("真实应用界面 · 示例对话", NSRect(x: 100, y: 2500, width: 1030, height: 70), 31, .regular, 0x617989)
      } else {
        card(shot, NSRect(x: 169, y: 625, width: 868, height: 868*shot.size.height/shot.size.width))
        text(page.id == "models" ? "应用服务列表 · 需自备 API Key" : "真实应用界面 · 示例对话与配置", NSRect(x: 100, y: 2530, width: 1030, height: 65), 31, .regular, 0x617989)
      }
    }
  }
}
let creative = listing.creativeAssets
let chat = load(listing.screenshots.first(where: { $0.id == "models" })!.phone)
let watch = load("doc/app_store/zh-Hans/watch/01-chat.jpg")
for (height,name) in [(1646,"header"),(2560,"search")] {
  let header = name == "header"
  try render(3840,height,output.appendingPathComponent("creative-assets/zh-Hans/\(name).\(header ? "png" : "jpg")")) {
    let x: CGFloat = 350, titleY: CGFloat = header ? 450 : 800
    text("AI Link", NSRect(x: x, y: header ? 220 : 500, width: 1600, height: 160), 115, .semibold, 0x0876CE)
    for (i,line) in creative.title.components(separatedBy: "\n").enumerated() {
      text(line, NSRect(x: x, y: titleY+CGFloat(i)*260, width: 1700, height: 270), 194, .bold, i == 0 ? 0x132A40 : 0x0876CE)
    }
    text(creative.features, NSRect(x: x, y: titleY+560, width: 1650, height: 220), 63, .medium, 0x456579)
    let width: CGFloat = header ? 780 : 970
    card(chat, NSRect(x: header ? 2360 : 2120, y: header ? 160 : 260, width: width, height: width*chat.size.height/chat.size.width), radius: 65)
    let watchW: CGFloat = header ? 580 : 700
    card(watch, NSRect(x: header ? 2940 : 2850, y: header ? 800 : 1550, width: watchW, height: watchW*watch.size.height/watch.size.width), radius: 95)
    text(creative.note, NSRect(x: x, y: CGFloat(height)-175, width: 1750, height: 130), 45, .regular, 0x617989)
  }
}
