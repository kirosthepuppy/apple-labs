// Draws the launcher's app icon into an .iconset folder, ready for iconutil.
//
//   swiftc -O make-icon.swift -o make-icon && ./make-icon AppIcon.iconset
//
// The artwork is drawn in code so the repository needs no image files: a
// deep violet squircle with a glass flask of bubbling pink liquid.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: srgb, components: [r, g, b, a])!
}

func drawIcon(_ ctx: CGContext, pixels: Int) {
    let scale = CGFloat(pixels) / 1024
    ctx.scaleBy(x: scale, y: scale)

    // Body on the standard macOS icon grid.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: color(0, 0, 0, 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0.1, 0.08, 0.22))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let backdrop = CGGradient(colorsSpace: srgb,
                              colors: [color(0.27, 0.17, 0.62), color(0.10, 0.07, 0.28), color(0.04, 0.05, 0.14)] as CFArray,
                              locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(backdrop, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    // The flask: a straight neck flaring into a wide, round-cornered base.
    let neckL: CGFloat = 446, neckR: CGFloat = 578, neckTop: CGFloat = 770, shoulder: CGFloat = 590
    let baseL: CGFloat = 238, baseR: CGFloat = 786, bottom: CGFloat = 232
    let flask = CGMutablePath()
    flask.move(to: CGPoint(x: neckL, y: neckTop))
    flask.addArc(tangent1End: CGPoint(x: neckL, y: shoulder), tangent2End: CGPoint(x: baseL, y: bottom), radius: 40)
    flask.addArc(tangent1End: CGPoint(x: baseL, y: bottom), tangent2End: CGPoint(x: 512, y: bottom), radius: 70)
    flask.addArc(tangent1End: CGPoint(x: baseR, y: bottom), tangent2End: CGPoint(x: neckR, y: shoulder), radius: 70)
    flask.addArc(tangent1End: CGPoint(x: neckR, y: shoulder), tangent2End: CGPoint(x: neckR, y: neckTop), radius: 40)
    flask.addLine(to: CGPoint(x: neckR, y: neckTop))
    flask.closeSubpath()

    // Glass.
    ctx.saveGState()
    ctx.addPath(flask)
    ctx.setFillColor(color(1, 1, 1, 0.12))
    ctx.fillPath()
    ctx.restoreGState()

    // Liquid with a gentle wave on top, clipped to the glass.
    ctx.saveGState()
    ctx.addPath(flask)
    ctx.clip()
    let level: CGFloat = 420
    let liquid = CGMutablePath()
    liquid.move(to: CGPoint(x: 150, y: level))
    liquid.addCurve(to: CGPoint(x: 512, y: level + 6), control1: CGPoint(x: 280, y: level + 44), control2: CGPoint(x: 400, y: level - 34))
    liquid.addCurve(to: CGPoint(x: 874, y: level), control1: CGPoint(x: 624, y: level + 46), control2: CGPoint(x: 760, y: level - 30))
    liquid.addLine(to: CGPoint(x: 874, y: 150))
    liquid.addLine(to: CGPoint(x: 150, y: 150))
    liquid.closeSubpath()
    ctx.addPath(liquid)
    ctx.clip()
    let juice = CGGradient(colorsSpace: srgb, colors: [color(1.0, 0.42, 0.66), color(1.0, 0.56, 0.30)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(juice, start: CGPoint(x: 512, y: level + 20), end: CGPoint(x: 512, y: bottom), options: [])
    // Bubbles in the liquid.
    for (x, y, r) in [(420.0, 300.0, 26.0), (560.0, 350.0, 18.0), (620.0, 272.0, 32.0), (360.0, 372.0, 12.0)] {
        ctx.setFillColor(color(1, 1, 1, 0.45))
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
    ctx.restoreGState()

    // Bubbles rising out of the liquid.
    for (x, y, r) in [(496.0, 500.0, 20.0), (540.0, 600.0, 14.0), (500.0, 690.0, 10.0)] {
        ctx.setFillColor(color(1, 0.8, 0.9, 0.85))
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    // Glass outline and rim.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: color(0.05, 0.02, 0.15, 0.6))
    ctx.addPath(flask)
    ctx.setStrokeColor(color(1, 1, 1))
    ctx.setLineWidth(34)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    let rim = CGPath(roundedRect: CGRect(x: 410, y: neckTop - 14, width: 204, height: 56), cornerWidth: 28, cornerHeight: 28, transform: nil)
    ctx.addPath(rim)
    ctx.setFillColor(color(1, 1, 1))
    ctx.fillPath()
    ctx.restoreGState()

    // A highlight down the left side of the glass.
    ctx.saveGState()
    let shine = CGMutablePath()
    shine.move(to: CGPoint(x: 476, y: 730))
    shine.addLine(to: CGPoint(x: 476, y: 610))
    shine.addLine(to: CGPoint(x: 330, y: 360))
    ctx.addPath(shine)
    ctx.setStrokeColor(color(1, 1, 1, 0.5))
    ctx.setLineWidth(16)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()
}

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, pixels) in sizes {
    guard let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                              space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("could not create a \(pixels)px canvas")
    }
    drawIcon(ctx, pixels: pixels)
    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(out.appendingPathComponent("\(name).png") as CFURL,
                                                     UTType.png.identifier as CFString, 1, nil) else {
        fatalError("could not write \(name)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}
