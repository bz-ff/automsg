#!/usr/bin/env swift
// Generates AutoMsg app icon at all required macOS sizes and bundles into AppIcon.icns

import Foundation
import AppKit
import CoreGraphics

let sizes: [(size: Int, scale: Int, name: String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png"),
]

func makeIcon(pixels: Int) -> Data? {
    let size = CGFloat(pixels)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let r = size * 0.225 // macOS Big Sur+ corner radius ratio
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // Gradient background — purple to pink to orange (fun, energetic)
    let colors = [
        CGColor(red: 0.40, green: 0.20, blue: 0.95, alpha: 1.0),  // deep purple top-left
        CGColor(red: 0.95, green: 0.30, blue: 0.65, alpha: 1.0),  // pink middle
        CGColor(red: 1.00, green: 0.60, blue: 0.20, alpha: 1.0),  // orange bottom-right
    ] as CFArray
    let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: [0.0, 0.5, 1.0])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: []
    )

    // Speech bubble (chat bubble shape) — white with shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.06, color: CGColor(gray: 0, alpha: 0.25))

    let bubbleW = size * 0.62
    let bubbleH = size * 0.44
    let bubbleX = size * 0.18
    let bubbleY = size * 0.32
    let bubbleR = bubbleH * 0.32

    let bubblePath = CGMutablePath()
    bubblePath.addRoundedRect(
        in: CGRect(x: bubbleX, y: bubbleY, width: bubbleW, height: bubbleH),
        cornerWidth: bubbleR, cornerHeight: bubbleR
    )
    // Tail (lower-left of bubble)
    let tailX = bubbleX + bubbleW * 0.18
    let tailY = bubbleY
    bubblePath.move(to: CGPoint(x: tailX, y: tailY))
    bubblePath.addLine(to: CGPoint(x: tailX - size * 0.06, y: tailY - size * 0.10))
    bubblePath.addLine(to: CGPoint(x: tailX + size * 0.06, y: tailY))
    bubblePath.closeSubpath()

    ctx.addPath(bubblePath)
    ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // Three colorful dots inside the bubble (chat indicator) — using brand-style colors
    let dotR = size * 0.045
    let dotY = bubbleY + bubbleH / 2
    let centerX = bubbleX + bubbleW / 2
    let dotSpacing = size * 0.115
    let dotColors = [
        CGColor(red: 0.40, green: 0.20, blue: 0.95, alpha: 1.0), // purple
        CGColor(red: 0.95, green: 0.30, blue: 0.65, alpha: 1.0), // pink
        CGColor(red: 1.00, green: 0.55, blue: 0.20, alpha: 1.0), // orange
    ]
    for (i, color) in dotColors.enumerated() {
        let cx = centerX + CGFloat(i - 1) * dotSpacing
        let dotRect = CGRect(x: cx - dotR, y: dotY - dotR, width: dotR * 2, height: dotR * 2)
        ctx.setFillColor(color)
        ctx.fillEllipse(in: dotRect)
    }

    // Lightning bolt overlay (top-right) — symbolizes "auto"
    ctx.saveGState()
    let bolt = CGMutablePath()
    let bx = size * 0.70
    let by = size * 0.83
    let bw = size * 0.13
    let bh = size * 0.18
    bolt.move(to: CGPoint(x: bx + bw * 0.55, y: by))
    bolt.addLine(to: CGPoint(x: bx, y: by + bh * 0.55))
    bolt.addLine(to: CGPoint(x: bx + bw * 0.45, y: by + bh * 0.55))
    bolt.addLine(to: CGPoint(x: bx + bw * 0.30, y: by + bh))
    bolt.addLine(to: CGPoint(x: bx + bw, y: by + bh * 0.45))
    bolt.addLine(to: CGPoint(x: bx + bw * 0.55, y: by + bh * 0.45))
    bolt.closeSubpath()

    ctx.addPath(bolt)
    ctx.setFillColor(CGColor(red: 1.0, green: 0.95, blue: 0.0, alpha: 1.0))
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.005), blur: size * 0.02, color: CGColor(gray: 0, alpha: 0.4))
    ctx.fillPath()
    ctx.restoreGState()

    // Output PNG
    guard let cgImage = ctx.makeImage() else { return nil }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    return bitmap.representation(using: .png, properties: [:])
}

// Build iconset
let fm = FileManager.default
let projectDir = (CommandLine.arguments.count > 1) ? CommandLine.arguments[1] : fm.currentDirectoryPath
let iconset = "\(projectDir)/AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

for entry in sizes {
    let pixels = entry.size * entry.scale
    if let data = makeIcon(pixels: pixels) {
        let path = "\(iconset)/\(entry.name)"
        try data.write(to: URL(fileURLWithPath: path))
        print("Wrote \(path) (\(pixels)x\(pixels))")
    }
}

// Convert iconset to icns using iconutil
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", "\(projectDir)/AppIcon.icns"]
try task.run()
task.waitUntilExit()

if task.terminationStatus == 0 {
    print("Generated AppIcon.icns")
    try? fm.removeItem(atPath: iconset)
} else {
    print("iconutil failed with status \(task.terminationStatus)")
}
