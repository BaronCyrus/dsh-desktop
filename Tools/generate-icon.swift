import AppKit
import Foundation

struct IconSlot {
    let filename: String
    let pixels: Int
}

guard CommandLine.arguments.count == 3 else {
    fputs("usage: generate-icon <favicon.svg> <output.iconset>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let source = try String(contentsOf: sourceURL, encoding: .utf8)
let pathPattern = #"<path[^>]*\sd="([^"]+)""#
let pathRegex = try NSRegularExpression(pattern: pathPattern)
let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)

guard let match = pathRegex.firstMatch(in: source, range: sourceRange),
      let pathRange = Range(match.range(at: 1), in: source) else {
    fputs("could not find the SVG path\n", stderr)
    exit(1)
}

let pathData = String(source[pathRange])
let composedSVG = """
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <rect x="80" y="80" width="864" height="864" rx="192" fill="#ffffff"/>
  <g transform="translate(212 212) scale(12)">
    <path d="\(pathData)" fill="#000000"/>
  </g>
</svg>
"""

guard let vectorImage = NSImage(data: Data(composedSVG.utf8)) else {
    fputs("AppKit could not decode the composed SVG\n", stderr)
    exit(1)
}

let slots = [
    IconSlot(filename: "icon_16x16.png", pixels: 16),
    IconSlot(filename: "icon_16x16@2x.png", pixels: 32),
    IconSlot(filename: "icon_32x32.png", pixels: 32),
    IconSlot(filename: "icon_32x32@2x.png", pixels: 64),
    IconSlot(filename: "icon_128x128.png", pixels: 128),
    IconSlot(filename: "icon_128x128@2x.png", pixels: 256),
    IconSlot(filename: "icon_256x256.png", pixels: 256),
    IconSlot(filename: "icon_256x256@2x.png", pixels: 512),
    IconSlot(filename: "icon_512x512.png", pixels: 512),
    IconSlot(filename: "icon_512x512@2x.png", pixels: 1024),
]

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

for slot in slots {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: slot.pixels,
        pixelsHigh: slot.pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "DSHIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create \(slot.pixels)px bitmap"])
    }

    bitmap.size = NSSize(width: slot.pixels, height: slot.pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: slot.pixels, height: slot.pixels))
    context.imageInterpolation = .high
    vectorImage.draw(
        in: NSRect(x: 0, y: 0, width: slot.pixels, height: slot.pixels),
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "DSHIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode \(slot.filename)"])
    }
    try png.write(to: outputURL.appendingPathComponent(slot.filename), options: .atomic)
}
