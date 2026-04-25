#!/usr/bin/env swift
//
// Generates CoFrame's app icon (light / dark / tinted variants) as 1024×1024 PNGs.
//
// Visual concept:
//   - Two overlapping rounded rectangles: a 16:9 landscape frame + a 9:16 portrait
//     frame (the app's core: "one shoot, two formats"), forming a "+".
//   - A red record dot at the intersection.
//   - Deep blue gradient background.
//
// Usage: swift generate_icon.swift <output-directory>
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum Variant: String {
    case light, dark, tinted
}

func renderIcon(variant: Variant, size: CGFloat = 1024) -> CGImage? {
    let cs = CGColorSpaceCreateDeviceRGB()
    let info = CGImageAlphaInfo.premultipliedLast.rawValue

    guard let ctx = CGContext(
        data: nil,
        width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs, bitmapInfo: info
    ) else { return nil }

    let imgSize = CGSize(width: size, height: size)

    // ---------------- Background ----------------
    switch variant {
    case .light:
        let colors: [CGColor] = [
            CGColor(red: 0.20, green: 0.36, blue: 0.55, alpha: 1.0),  // top-left
            CGColor(red: 0.06, green: 0.10, blue: 0.18, alpha: 1.0)   // bottom-right
        ]
        let gradient = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: size),
                               end:   CGPoint(x: size, y: 0),
                               options: [])
    case .dark:
        let colors: [CGColor] = [
            CGColor(red: 0.12, green: 0.20, blue: 0.32, alpha: 1.0),
            CGColor(red: 0.02, green: 0.04, blue: 0.08, alpha: 1.0)
        ]
        let gradient = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: size),
                               end:   CGPoint(x: size, y: 0),
                               options: [])
    case .tinted:
        // Tinted icons: leave background transparent so the system can apply its tint.
        break
    }

    // ---------------- Foreground geometry ----------------
    let cx = size / 2
    let cy = size / 2

    // 16:9 landscape frame, sized so its width takes up ~71% of the icon.
    let landW = size * 0.71
    let landH = landW * 9.0 / 16.0
    let landRect = CGRect(x: cx - landW / 2, y: cy - landH / 2, width: landW, height: landH)

    // 9:16 portrait frame, same proportional bulk (height takes up ~71%).
    let portH = size * 0.71
    let portW = portH * 9.0 / 16.0
    let portRect = CGRect(x: cx - portW / 2, y: cy - portH / 2, width: portW, height: portH)

    let radius: CGFloat = 56

    // ---------------- Variant palettes ----------------
    let strokeColor: CGColor
    let landFill: CGColor
    let portFill: CGColor
    let dotColor: CGColor

    switch variant {
    case .light:
        strokeColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.95)
        landFill    = CGColor(red: 0.42, green: 0.70, blue: 0.98, alpha: 0.22)  // cool blue
        portFill    = CGColor(red: 0.98, green: 0.70, blue: 0.42, alpha: 0.22)  // warm orange
        dotColor    = CGColor(red: 0.95, green: 0.22, blue: 0.22, alpha: 1.0)
    case .dark:
        strokeColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.92)
        landFill    = CGColor(red: 0.42, green: 0.70, blue: 0.98, alpha: 0.18)
        portFill    = CGColor(red: 0.98, green: 0.70, blue: 0.42, alpha: 0.18)
        dotColor    = CGColor(red: 0.96, green: 0.28, blue: 0.28, alpha: 1.0)
    case .tinted:
        strokeColor = CGColor(gray: 1.0, alpha: 1.0)
        landFill    = CGColor(gray: 0.65, alpha: 0.45)
        portFill    = CGColor(gray: 0.85, alpha: 0.55)
        dotColor    = CGColor(gray: 1.0, alpha: 1.0)
    }

    // ---------------- Draw the two frames ----------------
    // Landscape: fill + stroke
    ctx.setFillColor(landFill)
    ctx.addPath(CGPath(roundedRect: landRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()

    // Portrait: fill + stroke (drawn on top so its overlap region with landscape is visible)
    ctx.setFillColor(portFill)
    ctx.addPath(CGPath(roundedRect: portRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()

    // White stroke on both
    ctx.setLineWidth(26)
    ctx.setStrokeColor(strokeColor)
    ctx.addPath(CGPath(roundedRect: landRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.strokePath()
    ctx.addPath(CGPath(roundedRect: portRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.strokePath()

    // ---------------- Record dot in the center ----------------
    let dotR: CGFloat = size * 0.075
    let dotRect = CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)

    // Subtle white halo behind the dot for separation against the colored fills
    if variant != .tinted {
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
        let halo = dotRect.insetBy(dx: -10, dy: -10)
        ctx.fillEllipse(in: halo)
    }

    ctx.setFillColor(dotColor)
    ctx.fillEllipse(in: dotRect)

    _ = imgSize  // keep referenced for future use
    return ctx.makeImage()
}

// ---------------- Save ----------------

func savePNG(_ image: CGImage, to url: URL) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL,
                                                     UTType.png.identifier as CFString,
                                                     1, nil) else { return false }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

// ---------------- Main ----------------

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("Usage: generate_icon.swift <output-directory>\n".data(using: .utf8)!)
    exit(1)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let outputs: [(Variant, String)] = [
    (.light,  "AppIcon.png"),
    (.dark,   "AppIcon-Dark.png"),
    (.tinted, "AppIcon-Tinted.png")
]

for (variant, filename) in outputs {
    guard let image = renderIcon(variant: variant) else {
        print("✗ failed to render \(variant.rawValue)")
        continue
    }
    let url = outDir.appendingPathComponent(filename)
    if savePNG(image, to: url) {
        print("✓ wrote \(filename)  (\(image.width)×\(image.height))")
    } else {
        print("✗ failed to write \(filename)")
    }
}
