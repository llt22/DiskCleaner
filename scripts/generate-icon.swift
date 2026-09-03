import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("用法：generate-icon.swift <output.png>\n".utf8))
    exit(1)
}

let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("无法创建图标画布")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let tile = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 205, yRadius: 205)
let background = NSGradient(colors: [
    NSColor(red: 0.05, green: 0.56, blue: 1.0, alpha: 1),
    NSColor(red: 0.02, green: 0.31, blue: 0.88, alpha: 1),
])!
background.draw(in: tile, angle: -72)

let glow = NSBezierPath(ovalIn: NSRect(x: 132, y: 530, width: 520, height: 370))
NSColor.white.withAlphaComponent(0.10).setFill()
glow.fill()

let drive = NSBezierPath(roundedRect: NSRect(x: 218, y: 260, width: 588, height: 465), xRadius: 108, yRadius: 108)
NSColor.white.setFill()
drive.fill()

let face = NSBezierPath(roundedRect: NSRect(x: 258, y: 306, width: 508, height: 150), xRadius: 56, yRadius: 56)
NSColor(red: 0.04, green: 0.38, blue: 0.91, alpha: 1).setFill()
face.fill()

let slot = NSBezierPath(roundedRect: NSRect(x: 342, y: 532, width: 340, height: 32), xRadius: 16, yRadius: 16)
NSColor(red: 0.03, green: 0.35, blue: 0.88, alpha: 0.35).setFill()
slot.fill()

let light = NSBezierPath(ovalIn: NSRect(x: 665, y: 351, width: 34, height: 34))
NSColor(red: 0.32, green: 0.95, blue: 0.67, alpha: 1).setFill()
light.fill()

let badgeRect = NSRect(x: 582, y: 154, width: 290, height: 290)
let badge = NSBezierPath(ovalIn: badgeRect)
NSColor(red: 0.11, green: 0.76, blue: 0.46, alpha: 1).setFill()
badge.fill()
NSColor.white.withAlphaComponent(0.9).setStroke()
badge.lineWidth = 16
badge.stroke()

let check = NSBezierPath()
check.move(to: NSPoint(x: 654, y: 294))
check.line(to: NSPoint(x: 704, y: 244))
check.line(to: NSPoint(x: 804, y: 354))
check.lineCapStyle = .round
check.lineJoinStyle = .round
check.lineWidth = 34
NSColor.white.setStroke()
check.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("无法编码图标")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
