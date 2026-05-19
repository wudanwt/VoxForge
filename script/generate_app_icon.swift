import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct IconSize {
    let points: Int
    let scale: Int

    var pixels: Int { points * scale }
    var filename: String {
        if scale == 1 {
            return "icon_\(points)x\(points).png"
        }
        return "icon_\(points)x\(points)@\(scale)x.png"
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: swift script/generate_app_icon.swift <source.png> <iconset-dir> <icns-path>\n".utf8))
    exit(2)
}

let sourceURL = URL(fileURLWithPath: arguments[1])
let iconsetURL = URL(fileURLWithPath: arguments[2])
let icnsURL = URL(fileURLWithPath: arguments[3])

guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let sourceImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
    FileHandle.standardError.write(Data("Could not load source image: \(sourceURL.path)\n".utf8))
    exit(1)
}

let sizes = [
    IconSize(points: 16, scale: 1),
    IconSize(points: 16, scale: 2),
    IconSize(points: 32, scale: 1),
    IconSize(points: 32, scale: 2),
    IconSize(points: 128, scale: 1),
    IconSize(points: 128, scale: 2),
    IconSize(points: 256, scale: 1),
    IconSize(points: 256, scale: 2),
    IconSize(points: 512, scale: 1),
    IconSize(points: 512, scale: 2)
]

let icnsTypesByPixelSize: [Int: String] = [
    16: "icp4",
    32: "icp5",
    64: "icp6",
    128: "ic07",
    256: "ic08",
    512: "ic09",
    1024: "ic10"
]

let fileManager = FileManager.default
try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

var pngFilesByPixelSize: [Int: URL] = [:]

for size in sizes {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil,
            width: size.pixels,
            height: size.pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        FileHandle.standardError.write(Data("Could not create graphics context for \(size.filename)\n".utf8))
        exit(1)
    }

    context.clear(CGRect(x: 0, y: 0, width: size.pixels, height: size.pixels))
    context.interpolationQuality = .high
    context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: size.pixels, height: size.pixels))

    let pngURL = iconsetURL.appendingPathComponent(size.filename)
    guard let destination = CGImageDestinationCreateWithURL(
        pngURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ), let image = context.makeImage() else {
        FileHandle.standardError.write(Data("Could not prepare \(size.filename)\n".utf8))
        exit(1)
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        FileHandle.standardError.write(Data("Could not encode \(size.filename)\n".utf8))
        exit(1)
    }

    pngFilesByPixelSize[size.pixels] = pngURL
}

try? fileManager.removeItem(at: icnsURL)

func appendASCII(_ string: String, to data: inout Data) {
    data.append(Data(string.utf8))
}

func appendBigEndianUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
}

var chunks = Data()
for pixelSize in [16, 32, 64, 128, 256, 512, 1024] {
    guard let chunkType = icnsTypesByPixelSize[pixelSize],
          let pngURL = pngFilesByPixelSize[pixelSize] else {
        continue
    }

    let pngData = try Data(contentsOf: pngURL)
    appendASCII(chunkType, to: &chunks)
    appendBigEndianUInt32(UInt32(pngData.count + 8), to: &chunks)
    chunks.append(pngData)
}

var icnsData = Data()
appendASCII("icns", to: &icnsData)
appendBigEndianUInt32(UInt32(chunks.count + 8), to: &icnsData)
icnsData.append(chunks)
try icnsData.write(to: icnsURL, options: .atomic)
