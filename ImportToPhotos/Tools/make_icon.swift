import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct RGBA {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var cgColor: CGColor {
        CGColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
    }
}

private func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
    CGRect(x: x, y: y, width: width, height: height)
}

private func scaleRect(_ source: CGRect, by scale: CGFloat) -> CGRect {
    CGRect(
        x: source.origin.x * scale,
        y: source.origin.y * scale,
        width: source.size.width * scale,
        height: source.size.height * scale
    )
}

private func rounded(_ source: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: source, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

private func drawLinearGradient(_ context: CGContext, in area: CGRect, colors: [RGBA], start: CGPoint, end: CGPoint) {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors.map(\.cgColor) as CFArray, locations: nil)!
    context.saveGState()
    context.clip(to: area)
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
    context.restoreGState()
}

private func drawRadialGradient(_ context: CGContext, center: CGPoint, radius: CGFloat, colors: [RGBA]) {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors.map(\.cgColor) as CFArray, locations: nil)!
    context.saveGState()
    context.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: [.drawsAfterEndLocation]
    )
    context.restoreGState()
}

private func drawIcon(size: Int) throws -> CGImage {
    let scale = CGFloat(size) / 1024
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "ImportToPhotosIcon", code: 1)
    }

    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    let card = scaleRect(rect(118, 118, 788, 788), by: scale)
    let cardPath = rounded(card, 150 * scale)
    let glyphFrame = scaleRect(rect(312, 352, 400, 292), by: scale)
    let glyphPath = rounded(glyphFrame, 52 * scale)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -26 * scale), blur: 58 * scale, color: RGBA(0, 0, 0, 0.38).cgColor)
    context.setFillColor(RGBA(17, 18, 20).cgColor)
    context.addPath(cardPath)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(cardPath)
    context.clip()
    drawLinearGradient(
        context,
        in: card,
        colors: [RGBA(47, 50, 56), RGBA(24, 26, 30), RGBA(12, 13, 15)],
        start: CGPoint(x: card.minX, y: card.maxY),
        end: CGPoint(x: card.maxX, y: card.minY)
    )
    drawRadialGradient(
        context,
        center: CGPoint(x: 336 * scale, y: 742 * scale),
        radius: 460 * scale,
        colors: [RGBA(255, 255, 255, 0.12), RGBA(255, 255, 255, 0.035), RGBA(255, 255, 255, 0)]
    )
    drawRadialGradient(
        context,
        center: CGPoint(x: 742 * scale, y: 284 * scale),
        radius: 440 * scale,
        colors: [RGBA(255, 255, 255, 0.045), RGBA(255, 255, 255, 0)]
    )
    context.restoreGState()

    context.saveGState()
    context.setStrokeColor(RGBA(255, 255, 255, 0.18).cgColor)
    context.setLineWidth(3 * scale)
    context.addPath(rounded(card.insetBy(dx: 18 * scale, dy: 18 * scale), 136 * scale))
    context.strokePath()
    context.setStrokeColor(RGBA(0, 0, 0, 0.30).cgColor)
    context.setLineWidth(5 * scale)
    context.addPath(rounded(card.insetBy(dx: 4 * scale, dy: 4 * scale), 146 * scale))
    context.strokePath()
    context.restoreGState()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8 * scale), blur: 16 * scale, color: RGBA(0, 0, 0, 0.30).cgColor)
    context.setStrokeColor(RGBA(230, 234, 237, 0.94).cgColor)
    context.setLineWidth(34 * scale)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(glyphPath)
    context.strokePath()

    context.setLineWidth(28 * scale)
    let mountains = CGMutablePath()
    mountains.move(to: CGPoint(x: 354 * scale, y: 438 * scale))
    mountains.addLine(to: CGPoint(x: 452 * scale, y: 536 * scale))
    mountains.addLine(to: CGPoint(x: 512 * scale, y: 480 * scale))
    mountains.addLine(to: CGPoint(x: 572 * scale, y: 536 * scale))
    mountains.addLine(to: CGPoint(x: 670 * scale, y: 438 * scale))
    context.addPath(mountains)
    context.strokePath()

    context.setFillColor(RGBA(230, 234, 237, 0.94).cgColor)
    context.fillEllipse(in: scaleRect(rect(486, 554, 52, 52), by: scale))
    context.restoreGState()

    guard let image = context.makeImage() else {
        throw NSError(domain: "ImportToPhotosIcon", code: 2)
    }
    return image
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "ImportToPhotosIcon", code: 3)
    }
    CGImageDestinationAddImage(destination, image, nil)
    if !CGImageDestinationFinalize(destination) {
        throw NSError(domain: "ImportToPhotosIcon", code: 4)
    }
}

private extension Data {
    mutating func appendOSType(_ type: String) {
        append(type.data(using: .ascii)!)
    }

    mutating func appendBigEndianUInt32(_ value: UInt32) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }
}

private func writeICNS(chunks: [(type: String, url: URL)], to outputURL: URL) throws {
    let chunkData = try chunks.map { chunk in
        (chunk.type, try Data(contentsOf: chunk.url))
    }
    let totalLength = 8 + chunkData.reduce(0) { $0 + 8 + $1.1.count }

    var data = Data()
    data.appendOSType("icns")
    data.appendBigEndianUInt32(UInt32(totalLength))

    for (type, payload) in chunkData {
        data.appendOSType(type)
        data.appendBigEndianUInt32(UInt32(payload.count + 8))
        data.append(payload)
    }

    try data.write(to: outputURL, options: .atomic)
}

let outputRoot = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let iconset = outputRoot.appendingPathComponent("ImportToPhotos.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let iconFiles: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, size) in iconFiles {
    try writePNG(try drawIcon(size: size), to: iconset.appendingPathComponent(filename))
}

try writeICNS(
    chunks: [
        ("icp4", iconset.appendingPathComponent("icon_16x16.png")),
        ("icp5", iconset.appendingPathComponent("icon_32x32.png")),
        ("icp6", iconset.appendingPathComponent("icon_32x32@2x.png")),
        ("ic07", iconset.appendingPathComponent("icon_128x128.png")),
        ("ic08", iconset.appendingPathComponent("icon_256x256.png")),
        ("ic09", iconset.appendingPathComponent("icon_512x512.png")),
        ("ic10", iconset.appendingPathComponent("icon_512x512@2x.png")),
        ("ic11", iconset.appendingPathComponent("icon_16x16@2x.png")),
        ("ic12", iconset.appendingPathComponent("icon_32x32@2x.png")),
        ("ic13", iconset.appendingPathComponent("icon_128x128@2x.png")),
        ("ic14", iconset.appendingPathComponent("icon_256x256@2x.png"))
    ],
    to: outputRoot.appendingPathComponent("ImportToPhotos.icns")
)
