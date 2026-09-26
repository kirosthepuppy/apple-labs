// Draws the launcher's app icon into an .iconset folder, ready for iconutil.
//
//   swiftc -O make-icon.swift -o make-icon && ./make-icon AppIcon.iconset
//
// The artwork is drawn in code so the repository needs no image files: a
// sunset-to-blue squircle with a faint stud grid, and a tilted white brick
// with a play button cut through it.

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
    ctx.setFillColor(color(0.2, 0.2, 0.3))
    ctx.fillPath()
    ctx.restoreGState()

    let gradient = CGGradient(colorsSpace: srgb,
                              colors: [color(1.0, 0.58, 0.22), color(0.90, 0.28, 0.52), color(0.26, 0.36, 1.0)] as CFArray,
                              locations: [0, 0.48, 1])!
    func paintBody() {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 160, y: 930), end: CGPoint(x: 880, y: 90), options: [])
    }

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    paintBody()
    // Soft sheen from the top-left.
    let sheen = CGGradient(colorsSpace: srgb, colors: [color(1, 1, 1, 0.32), color(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: 280, y: 860), startRadius: 0,
                           endCenter: CGPoint(x: 280, y: 860), endRadius: 560, options: [])
    // A faint grid of studs.
    for y in stride(from: 170.0, through: 880, by: 88) {
        for x in stride(from: 170.0, through: 880, by: 88) {
            ctx.setFillColor(color(0, 0, 0, 0.08))
            ctx.fillEllipse(in: CGRect(x: x - 15, y: y - 18, width: 30, height: 30))
            ctx.setFillColor(color(1, 1, 1, 0.1))
            ctx.fillEllipse(in: CGRect(x: x - 15, y: y - 15, width: 30, height: 30))
        }
    }
    ctx.restoreGState()

    // The brick: a tilted rounded square.
    let side: CGFloat = 450
    var tilt = CGAffineTransform(translationX: 512, y: 504).rotated(by: -12 * .pi / 180)
    let brick = CGPath(roundedRect: CGRect(x: -side / 2, y: -side / 2, width: side, height: side),
                       cornerWidth: 86, cornerHeight: 86, transform: &tilt)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 44, color: color(0.12, 0.04, 0.3, 0.5))
    ctx.addPath(brick)
    ctx.setFillColor(color(1, 1, 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(brick)
    ctx.clip()
    let shade = CGGradient(colorsSpace: srgb, colors: [color(1, 1, 1), color(0.86, 0.88, 0.97)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(shade, start: CGPoint(x: 512, y: 760), end: CGPoint(x: 512, y: 250), options: [])
    ctx.restoreGState()

    // A rounded play triangle cut through the brick, showing the body behind it.
    let cx: CGFloat = 530, cy: CGFloat = 504, r: CGFloat = 132
    let p1 = CGPoint(x: cx + r, y: cy)
    let p2 = CGPoint(x: cx - r / 2, y: cy + r * 0.866)
    let p3 = CGPoint(x: cx - r / 2, y: cy - r * 0.866)
    let play = CGMutablePath()
    play.move(to: CGPoint(x: (p3.x + p1.x) / 2, y: (p3.y + p1.y) / 2))
    play.addArc(tangent1End: p1, tangent2End: p2, radius: 30)
    play.addArc(tangent1End: p2, tangent2End: p3, radius: 30)
    play.addArc(tangent1End: p3, tangent2End: p1, radius: 30)
    play.closeSubpath()

    ctx.saveGState()
    ctx.addPath(play)
    ctx.clip()
    paintBody()
    // Inner shadow along the top edge so the hole reads as a cut-out.
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 16, color: color(0, 0, 0, 0.45))
    ctx.addRect(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    ctx.addPath(play)
    ctx.setFillColor(color(0, 0, 0))
    ctx.fillPath(using: .evenOdd)
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
