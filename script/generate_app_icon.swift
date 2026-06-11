#!/usr/bin/env swift
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outputPath = CommandLine.arguments.dropFirst().first ?? "dist/AppIcon.iconset"
let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let icons: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, size) in icons {
    let image = try makeIcon(size: size)
    try writePNG(image, to: outputURL.appendingPathComponent(name))
}

func makeIcon(size: Int) throws -> CGImage {
    let width = size
    let height = size
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw IconError.context
    }

    let s = CGFloat(size)
    context.translateBy(x: 0, y: s)
    context.scaleBy(x: 1, y: -1)
    context.clear(CGRect(x: 0, y: 0, width: s, height: s))

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
    }

    func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha).cgColor
    }

    let outer = roundedPath(rect(0.06, 0.06, 0.88, 0.88), radius: 0.19 * s)
    context.saveGState()
    context.addPath(outer)
    context.clip()
    let background = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0.05, 0.09, 0.18), color(0.05, 0.42, 0.48), color(0.08, 0.72, 0.66)] as CFArray,
        locations: [0.0, 0.62, 1.0]
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: 0.08 * s, y: 0.08 * s),
        end: CGPoint(x: 0.92 * s, y: 0.95 * s),
        options: []
    )
    context.restoreGState()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 0.035 * s), blur: 0.05 * s, color: color(0, 0, 0, 0.38))
    let pageRect = rect(0.28, 0.14, 0.48, 0.68)
    context.addPath(roundedPath(pageRect, radius: 0.045 * s))
    context.setFillColor(color(0.96, 0.98, 0.98))
    context.fillPath()
    context.restoreGState()

    let fold = CGMutablePath()
    fold.move(to: CGPoint(x: 0.65 * s, y: 0.14 * s))
    fold.addLine(to: CGPoint(x: 0.76 * s, y: 0.25 * s))
    fold.addLine(to: CGPoint(x: 0.65 * s, y: 0.25 * s))
    fold.closeSubpath()
    context.addPath(fold)
    context.setFillColor(color(0.79, 0.89, 0.91))
    context.fillPath()

    context.setStrokeColor(color(0.12, 0.22, 0.29, 0.24))
    context.setLineWidth(0.018 * s)
    context.addPath(roundedPath(pageRect, radius: 0.045 * s))
    context.strokePath()

    let bars = [
        rect(0.36, 0.34, 0.30, 0.055),
        rect(0.36, 0.45, 0.25, 0.055),
        rect(0.36, 0.56, 0.31, 0.055),
    ]
    for bar in bars {
        context.addPath(roundedPath(bar, radius: 0.02 * s))
        context.setFillColor(color(0.07, 0.10, 0.16))
        context.fillPath()
    }

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 0.018 * s), blur: 0.025 * s, color: color(0, 0, 0, 0.22))
    let shield = CGMutablePath()
    shield.move(to: CGPoint(x: 0.50 * s, y: 0.37 * s))
    shield.addCurve(to: CGPoint(x: 0.70 * s, y: 0.45 * s), control1: CGPoint(x: 0.58 * s, y: 0.38 * s), control2: CGPoint(x: 0.66 * s, y: 0.41 * s))
    shield.addCurve(to: CGPoint(x: 0.61 * s, y: 0.77 * s), control1: CGPoint(x: 0.69 * s, y: 0.61 * s), control2: CGPoint(x: 0.66 * s, y: 0.71 * s))
    shield.addCurve(to: CGPoint(x: 0.50 * s, y: 0.84 * s), control1: CGPoint(x: 0.57 * s, y: 0.80 * s), control2: CGPoint(x: 0.53 * s, y: 0.83 * s))
    shield.addCurve(to: CGPoint(x: 0.39 * s, y: 0.77 * s), control1: CGPoint(x: 0.47 * s, y: 0.83 * s), control2: CGPoint(x: 0.43 * s, y: 0.80 * s))
    shield.addCurve(to: CGPoint(x: 0.30 * s, y: 0.45 * s), control1: CGPoint(x: 0.34 * s, y: 0.71 * s), control2: CGPoint(x: 0.31 * s, y: 0.61 * s))
    shield.addCurve(to: CGPoint(x: 0.50 * s, y: 0.37 * s), control1: CGPoint(x: 0.34 * s, y: 0.41 * s), control2: CGPoint(x: 0.42 * s, y: 0.38 * s))
    shield.closeSubpath()
    context.addPath(shield)
    context.setFillColor(color(0.09, 0.84, 0.78, 0.86))
    context.fillPath()
    context.restoreGState()

    context.addPath(shield)
    context.setStrokeColor(color(0.93, 1.00, 0.98, 0.75))
    context.setLineWidth(0.022 * s)
    context.strokePath()

    context.addPath(roundedPath(rect(0.40, 0.60, 0.20, 0.052), radius: 0.02 * s))
    context.setFillColor(color(0.03, 0.08, 0.12))
    context.fillPath()

    guard let image = context.makeImage() else {
        throw IconError.image
    }
    return image
}

func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw IconError.destination
    }
    CGImageDestinationAddImage(destination, image, nil)
    if !CGImageDestinationFinalize(destination) {
        throw IconError.write(url.path)
    }
}

enum IconError: Error {
    case context
    case image
    case destination
    case write(String)
}
