// Generate icon sets from one document image and a shared recolorable background.
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset")
let variant = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "default"
let original = NSImage(contentsOfFile: "tool/icons/IconArtwork.png")!
let background = NSImage(contentsOfFile: "tool/icons/IconBackdrop.png")!
let colors: [String: (CGFloat, CGFloat, CGFloat)] = [
    "stone": (0.55, 0.50, 0.44), "blue": (0.09, 0.19, 0.32),
    "green": (0.15, 0.27, 0.19), "lavender": (0.38, 0.33, 0.45),
    "terracotta": (0.44, 0.19, 0.12)
]
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

// Reuse the original paper, folded corner, letters and strokes in every variant.
func artwork() -> NSImage {
    let side: CGFloat = 1254
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: side, height: side)
    background.draw(in: rect)
    if let (red, green, blue) = colors[variant] {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1).setFill()
        rect.fill(using: .screen)
    }
    let sheet = NSBezierPath()
    sheet.move(to: NSPoint(x: 376, y: 994))
    sheet.line(to: NSPoint(x: 795, y: 994))
    sheet.line(to: NSPoint(x: 951, y: 838))
    sheet.line(to: NSPoint(x: 951, y: 291))
    sheet.curve(to: NSPoint(x: 903, y: 242), controlPoint1: NSPoint(x: 951, y: 264), controlPoint2: NSPoint(x: 930, y: 242))
    sheet.line(to: NSPoint(x: 376, y: 242))
    sheet.curve(to: NSPoint(x: 328, y: 291), controlPoint1: NSPoint(x: 349, y: 242), controlPoint2: NSPoint(x: 328, y: 264))
    sheet.line(to: NSPoint(x: 328, y: 945))
    sheet.curve(to: NSPoint(x: 376, y: 994), controlPoint1: NSPoint(x: 328, y: 972), controlPoint2: NSPoint(x: 349, y: 994))
    sheet.close()
    NSGraphicsContext.saveGraphicsState()
    // Center the same sheet within the visible crop for every background.
    let context = NSGraphicsContext.current!.cgContext
    context.translateBy(x: side * 0.49, y: side * 0.51)
    context.scaleBy(x: 0.91, y: 0.91)
    context.translateBy(x: -639.5, y: -618)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.black.setFill()
    sheet.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    sheet.addClip()
    original.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    image.unlockFocus()
    return image
}

let sourceImage = artwork()
func render(_ pixels: Int) -> Data {
    let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
    NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    shape.addClip()
    let side = sourceImage.size.width
    let source = NSRect(x: side * 0.094, y: side * 0.114, width: side * 0.792, height: side * 0.792)
    sourceImage.draw(in: tile, from: source, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return image.representation(using: .png, properties: [:])!
}

for (name, pixels) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try render(pixels).write(to: output.appendingPathComponent("icon_\(name).png"))
}
