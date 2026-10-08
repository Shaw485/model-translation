import AppKit
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let rect = NSRect(x: 90, y: 90, width: 844, height: 844)
let shape = NSBezierPath(roundedRect: rect, xRadius: 190, yRadius: 190)
NSGradient(starting: NSColor(red: 0.22, green: 0.43, blue: 0.97, alpha: 1), ending: NSColor(red: 0.25, green: 0.20, blue: 0.76, alpha: 1))!.draw(in: shape, angle: -70)
let text = NSAttributedString(string: "译", attributes: [.font: NSFont.systemFont(ofSize: 505, weight: .medium), .foregroundColor: NSColor.white])
let measure = text.size()
text.draw(at: NSPoint(x: (1024 - measure.width) / 2, y: (1024 - measure.height) / 2 + 10))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
