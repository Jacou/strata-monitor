#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Draws the Strata Monitor app icon: a radial teal glow behind a cyan pulse line.
///
/// iOS applies its own mask, so the artwork is full-bleed with no rounded corners and no
/// transparency. Regenerate with:
///
///     swift tools/make-icon.swift
///
/// The result is written to StrataMonitor/Assets.xcassets/AppIcon.appiconset/icon.png.
/// The asset catalog entry is single-size, so Xcode generates every required size from it.

let size = 1024
let side = CGFloat(size)
let path = "StrataMonitor/Assets.xcassets/AppIcon.appiconset/icon.png"

// MARK: - palette (the theme's dark values)

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

let glowCentre = rgb(0x14, 0x5F, 0x78)   // bright teal, centred behind the line
let glowMid = rgb(0x0A, 0x24, 0x34)
let edge = rgb(0x04, 0x07, 0x0D)         // near-black at the corners
let line = rgb(0x4F, 0xE3, 0xFF, 1)      // #4FE3FF

// MARK: - canvas

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("could not create bitmap context") }

// Background: a radial gradient centred on the line's height, so the glow sits behind the pulse.
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [glowCentre, glowMid, edge] as CFArray,
    locations: [0, 0.45, 1]
)!
let glowCentrePoint = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) * 0.52)
ctx.drawRadialGradient(
    gradient,
    startCenter: glowCentrePoint, startRadius: 0,
    endCenter: glowCentrePoint, endRadius: CGFloat(size) * 0.78,
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)

// MARK: - the pulse line

// A token-stream pulse: flat, a burst of spikes, flat. Drawn in unit space so it scales with
// the icon, then flipped into the bitmap's coordinate system.
let unitPoints: [(CGFloat, CGFloat)] = [
    (0.06, 0.50), (0.17, 0.50), (0.21, 0.34), (0.25, 0.66), (0.29, 0.20),
    (0.34, 0.78), (0.38, 0.44), (0.42, 0.52), (0.47, 0.28), (0.52, 0.70),
    (0.56, 0.46), (0.61, 0.50), (0.68, 0.50), (0.73, 0.36), (0.78, 0.60),
    (0.83, 0.50), (0.94, 0.50),
]

func makePath() -> CGPath {
    let p = CGMutablePath()
    for (i, point) in unitPoints.enumerated() {
        let x = point.0 * side
        let y = (1 - point.1) * side
        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    return p
}

let pulse = makePath()

// The glow: the same path drawn wide and faint under the solid stroke. Core Graphics has no
// blur, so stacked translucent strokes read as a halo.
ctx.setLineJoin(.round)
ctx.setLineCap(.round)

ctx.addPath(pulse)
ctx.setStrokeColor(rgb(0x4F, 0xE3, 0xFF, 0.10))
ctx.setLineWidth(150)
ctx.strokePath()

ctx.addPath(pulse)
ctx.setStrokeColor(rgb(0x4F, 0xE3, 0xFF, 0.18))
ctx.setLineWidth(84)
ctx.strokePath()

ctx.addPath(pulse)
ctx.setStrokeColor(rgb(0x4F, 0xE3, 0xFF, 0.35))
ctx.setLineWidth(46)
ctx.strokePath()

// The line itself: 24 pt at 1024, cyan.
ctx.addPath(pulse)
ctx.setStrokeColor(line)
ctx.setLineWidth(24)
ctx.strokePath()

// MARK: - write the PNG

guard let image = ctx.makeImage() else { fatalError("could not build image") }
FileManager.default.createFile(atPath: path, contents: nil)
guard let dest = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil
) else { fatalError("could not open \(path) for writing") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(path)") }

print("wrote \(path) (\(size)x\(size))")

// MARK: - optional home-screen mockup
//
//     swift tools/make-icon.swift --preview docs/screens/t6-icon.png
//
// Draws the icon on a dark wallpaper with iOS's rounded mask, so the icon can be reviewed
// without installing it.

func writePreview(to outPath: String) {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let art = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("could not read \(path)")
    }

    let canvas = 700
    let iconSide = 440
    let origin = (canvas - iconSide) / 2
    guard let out = CGContext(
        data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("could not create preview context") }

    // Wallpaper: the same teal glow, spread wide and dim.
    let wallpaper = CGGradient(
        colorsSpace: colorSpace,
        colors: [rgb(0x11, 0x2A, 0x3C), rgb(0x07, 0x0B, 0x14)] as CFArray,
        locations: [0, 1]
    )!
    out.drawRadialGradient(
        wallpaper,
        startCenter: CGPoint(x: CGFloat(canvas) / 2, y: CGFloat(canvas) * 0.55), startRadius: 0,
        endCenter: CGPoint(x: CGFloat(canvas) / 2, y: CGFloat(canvas) * 0.55), endRadius: CGFloat(canvas) * 0.8,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // iOS masks the artwork to a rounded square (a continuous corner; a plain radius is close).
    let corner = CGFloat(iconSide) * 0.2237
    out.saveGState()
    out.addPath(CGPath(roundedRect: CGRect(x: origin, y: origin, width: iconSide, height: iconSide),
                       cornerWidth: corner, cornerHeight: corner, transform: nil))
    out.clip()
    out.draw(art, in: CGRect(x: origin, y: origin, width: iconSide, height: iconSide))
    out.restoreGState()

    guard let image = out.makeImage() else { fatalError("could not build preview") }
    guard let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { fatalError("could not open \(outPath) for writing") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(outPath)") }
    print("wrote \(outPath)")
}

if let index = CommandLine.arguments.firstIndex(of: "--preview"), index + 1 < CommandLine.arguments.count {
    writePreview(to: CommandLine.arguments[index + 1])
}

