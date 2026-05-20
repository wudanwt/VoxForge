import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift script/generate_voxforge_icon.swift <output.png>\n".utf8))
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else {
    FileHandle.standardError.write(Data("Could not create icon context\n".utf8))
    exit(1)
}

let canvas = CGRect(x: 0, y: 0, width: size, height: size)
context.clear(canvas)
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func drawRoundedRect(_ rect: CGRect, radius: CGFloat, fill: CGColor) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.addPath(path)
    context.setFillColor(fill)
    context.fillPath()
}

func drawLinearGradient(colors: [CGColor], start: CGPoint, end: CGPoint, clip: CGPath? = nil) {
    guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil) else { return }
    context.saveGState()
    if let clip {
        context.addPath(clip)
        context.clip()
    }
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
    context.restoreGState()
}

func drawGlow(path: CGPath, color glowColor: CGColor, blur: CGFloat, alpha: CGFloat) {
    context.saveGState()
    context.setShadow(offset: .zero, blur: blur, color: glowColor.copy(alpha: alpha))
    context.addPath(path)
    context.setFillColor(glowColor.copy(alpha: 0.78) ?? glowColor)
    context.fillPath()
    context.restoreGState()
}

func polygon(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    guard let first = points.first else { return path }
    path.move(to: first)
    for point in points.dropFirst() {
        path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

func roundedBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat, color: CGColor, glow: Bool = false) {
    let rect = CGRect(x: x, y: y, width: width, height: height)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    if glow {
        drawGlow(path: path, color: color, blur: 18, alpha: 0.62)
    }
    context.addPath(path)
    context.setFillColor(color)
    context.fillPath()
}

let iconRect = CGRect(x: 56, y: 56, width: 912, height: 912)
let iconPath = CGPath(roundedRect: iconRect, cornerWidth: 138, cornerHeight: 138, transform: nil)
drawLinearGradient(
    colors: [
        color(0.02, 0.04, 0.15),
        color(0.02, 0.12, 0.42),
        color(0.12, 0.03, 0.34)
    ],
    start: CGPoint(x: 130, y: 950),
    end: CGPoint(x: 880, y: 90),
    clip: iconPath
)
context.addPath(iconPath)
context.setLineWidth(12)
context.setStrokeColor(color(0.27, 0.54, 1.0, 0.55))
context.strokePath()

let innerGlow = CGPath(roundedRect: iconRect.insetBy(dx: 16, dy: 16), cornerWidth: 126, cornerHeight: 126, transform: nil)
context.saveGState()
context.addPath(innerGlow)
context.setStrokeColor(color(0.15, 0.65, 1.0, 0.18))
context.setLineWidth(6)
context.strokePath()
context.restoreGState()

context.saveGState()
context.addPath(iconPath)
context.clip()

let centerX: CGFloat = 512
let forgeY: CGFloat = 328

let anvilTop = polygon([
    CGPoint(x: 214, y: 362),
    CGPoint(x: 770, y: 362),
    CGPoint(x: 806, y: 404),
    CGPoint(x: 720, y: 436),
    CGPoint(x: 390, y: 436),
    CGPoint(x: 318, y: 406)
])
drawGlow(path: anvilTop, color: color(0.24, 0.62, 1.0), blur: 20, alpha: 0.35)
drawLinearGradient(
    colors: [color(0.50, 0.74, 1.0), color(0.05, 0.09, 0.20), color(0.02, 0.04, 0.12)],
    start: CGPoint(x: 220, y: 436),
    end: CGPoint(x: 800, y: 362),
    clip: anvilTop
)

let anvilBody = polygon([
    CGPoint(x: 332, y: 350),
    CGPoint(x: 722, y: 350),
    CGPoint(x: 660, y: 252),
    CGPoint(x: 606, y: 226),
    CGPoint(x: 422, y: 226),
    CGPoint(x: 368, y: 252)
])
drawLinearGradient(
    colors: [color(0.05, 0.09, 0.21), color(0.11, 0.23, 0.45), color(0.01, 0.03, 0.09)],
    start: CGPoint(x: 340, y: 350),
    end: CGPoint(x: 690, y: 226),
    clip: anvilBody
)
drawRoundedRect(CGRect(x: 330, y: 210, width: 156, height: 44), radius: 10, fill: color(0.08, 0.20, 0.48))
drawRoundedRect(CGRect(x: 552, y: 210, width: 156, height: 44), radius: 10, fill: color(0.08, 0.20, 0.48))

let fireCore = CGPath(ellipseIn: CGRect(x: centerX - 92, y: forgeY - 64, width: 184, height: 128), transform: nil)
drawGlow(path: fireCore, color: color(1.0, 0.42, 0.04), blur: 52, alpha: 0.92)
drawGlow(path: fireCore, color: color(1.0, 0.87, 0.22), blur: 18, alpha: 0.9)

let vPath = polygon([
    CGPoint(x: 246, y: 804),
    CGPoint(x: 380, y: 790),
    CGPoint(x: 512, y: 362),
    CGPoint(x: 468, y: 300),
    CGPoint(x: 406, y: 362)
])
drawGlow(path: vPath, color: color(0.22, 0.88, 1.0), blur: 18, alpha: 0.55)
drawLinearGradient(
    colors: [color(0.72, 1.0, 1.0), color(0.32, 0.65, 1.0), color(1.0, 0.78, 0.32)],
    start: CGPoint(x: 260, y: 806),
    end: CGPoint(x: 506, y: 316),
    clip: vPath
)

let fPath = polygon([
    CGPoint(x: 538, y: 342),
    CGPoint(x: 632, y: 792),
    CGPoint(x: 830, y: 808),
    CGPoint(x: 776, y: 728),
    CGPoint(x: 650, y: 714),
    CGPoint(x: 630, y: 620),
    CGPoint(x: 790, y: 634),
    CGPoint(x: 742, y: 548),
    CGPoint(x: 612, y: 536),
    CGPoint(x: 588, y: 418)
])
drawGlow(path: fPath, color: color(0.35, 0.86, 1.0), blur: 18, alpha: 0.55)
drawLinearGradient(
    colors: [color(0.82, 1.0, 1.0), color(0.48, 0.74, 1.0), color(1.0, 0.70, 0.28)],
    start: CGPoint(x: 792, y: 808),
    end: CGPoint(x: 546, y: 328),
    clip: fPath
)

for (x, h, a) in [(444.0, 130.0, 0.58), (482.0, 210.0, 0.70), (526.0, 260.0, 0.80), (570.0, 210.0, 0.70), (608.0, 130.0, 0.58)] {
    roundedBar(x: x, y: 565 - h / 2, width: 22, height: h, radius: 11, color: color(0.22, 0.88, 1.0, CGFloat(a)), glow: true)
}

for side in [-1.0, 1.0] {
    let baseX = centerX + CGFloat(side) * 318
    let chevron = CGMutablePath()
    chevron.move(to: CGPoint(x: baseX, y: 552))
    chevron.addLine(to: CGPoint(x: baseX + CGFloat(side) * 54, y: 596))
    chevron.addLine(to: CGPoint(x: baseX + CGFloat(side) * 54, y: 634))
    chevron.addLine(to: CGPoint(x: baseX - CGFloat(side) * 10, y: 582))
    chevron.addLine(to: CGPoint(x: baseX + CGFloat(side) * 54, y: 530))
    chevron.addLine(to: CGPoint(x: baseX + CGFloat(side) * 54, y: 568))
    chevron.closeSubpath()
    drawGlow(path: chevron, color: color(0.20, 0.88, 1.0), blur: 16, alpha: 0.55)
    context.addPath(chevron)
    context.setFillColor(color(0.45, 0.95, 1.0))
    context.fillPath()

    for (offset, h) in [(82.0, 66.0), (114.0, 110.0), (146.0, 82.0)] {
        roundedBar(
            x: baseX - CGFloat(side) * offset - (side < 0 ? 18 : 0),
            y: 582 - h / 2,
            width: 18,
            height: h,
            radius: 9,
            color: color(0.18, 0.75, 1.0, 0.78),
            glow: false
        )
    }
}

context.setLineCap(.round)
for i in 0..<22 {
    let angle = CGFloat(i) / 22.0 * .pi * 2.0
    let radius = CGFloat(58 + (i % 4) * 18)
    let length = CGFloat(12 + (i % 5) * 5)
    let start = CGPoint(x: centerX + cos(angle) * radius, y: forgeY + sin(angle) * radius * 0.58)
    let end = CGPoint(x: centerX + cos(angle) * (radius + length), y: forgeY + sin(angle) * (radius + length) * 0.58)
    context.move(to: start)
    context.addLine(to: end)
    context.setStrokeColor(i % 3 == 0 ? color(1.0, 0.87, 0.20, 0.9) : color(1.0, 0.31, 0.03, 0.82))
    context.setLineWidth(CGFloat(2 + (i % 3)))
    context.strokePath()
}

context.restoreGState()

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      ) else {
    FileHandle.standardError.write(Data("Could not prepare output image\n".utf8))
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("Could not write \(outputURL.path)\n".utf8))
    exit(1)
}
