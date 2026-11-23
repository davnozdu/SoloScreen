import AppKit

// Иконка рисуется кодом: две линзы очков на градиенте. Никаких системных
// символов — SF Symbols использовать в иконках приложений нельзя по лицензии.
func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let corner = size * 0.2237  // пропорция скругления иконок macOS
    let background = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.24, alpha: 1),
                        NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.11, alpha: 1)])?
        .draw(in: background, angle: -90)

    let lensWidth = size * 0.30
    let lensHeight = size * 0.22
    let lensY = size * 0.39
    let gap = size * 0.06
    let totalWidth = lensWidth * 2 + gap
    let startX = (size - totalWidth) / 2

    let accent = NSGradient(colors: [NSColor(calibratedRed: 0.36, green: 0.78, blue: 1.0, alpha: 1),
                                     NSColor(calibratedRed: 0.20, green: 0.48, blue: 0.95, alpha: 1)])
    for index in 0..<2 {
        let lens = NSRect(x: startX + CGFloat(index) * (lensWidth + gap),
                          y: lensY, width: lensWidth, height: lensHeight)
        let path = NSBezierPath(roundedRect: lens, xRadius: lensHeight * 0.38, yRadius: lensHeight * 0.38)
        accent?.draw(in: path, angle: -90)
    }

    // Перемычка между линзами.
    let bridge = NSRect(x: startX + lensWidth, y: lensY + lensHeight * 0.38,
                        width: gap, height: lensHeight * 0.24)
    NSColor(calibratedRed: 0.28, green: 0.62, blue: 0.98, alpha: 1).setFill()
    NSBezierPath(rect: bridge).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let variants: [(name: String, type: String, size: CGFloat)] = [
    ("icon_16x16", "icp4", 16), ("icon_16x16@2x", "ic11", 32),
    ("icon_32x32", "icp5", 32), ("icon_32x32@2x", "ic12", 64),
    ("icon_128x128", "ic07", 128), ("icon_128x128@2x", "ic13", 256),
    ("icon_256x256", "ic08", 256), ("icon_256x256@2x", "ic14", 512),
    ("icon_512x512", "ic09", 512), ("icon_512x512@2x", "ic10", 1024),
]

if output.hasSuffix(".icns") {
    // Напрямую собираем контейнер .icns, если iconutil недоступен или отвергает iconset.
    var body = Data()
    for variant in variants {
        let rep = drawIcon(size: variant.size)
        guard let png = rep.representation(using: .png, properties: [:]) else { continue }
        var chunkLength = UInt32(8 + png.count).bigEndian
        body.append(Data(variant.type.utf8))
        withUnsafeBytes(of: &chunkLength) { body.append(contentsOf: $0) }
        body.append(png)
    }
    var file = Data("icns".utf8)
    var totalLength = UInt32(8 + body.count).bigEndian
    withUnsafeBytes(of: &totalLength) { file.append(contentsOf: $0) }
    file.append(body)
    try file.write(to: URL(fileURLWithPath: output))
} else {
    try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
    for variant in variants {
        let rep = drawIcon(size: variant.size)
        guard let data = rep.representation(using: .png, properties: [:]) else { continue }
        try? data.write(to: URL(fileURLWithPath: "\(output)/\(variant.name).png"))
    }
}
print("иконка собрана: \(output)")
