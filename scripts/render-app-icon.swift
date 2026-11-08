#!/usr/bin/env swift
// Renders the Nimbus app icon (every macOS size) into the asset catalog.
//
//   swift scripts/render-app-icon.swift
//
// The icon is drawn with CoreGraphics so the mark is reproducible from
// source. Two cumulus clouds on a sky gradient inside the standard macOS
// squircle: a small translucent cloud behind, a solid white one in front.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outputDir = repoRoot
    .appendingPathComponent("Nimbus/Nimbus/Resources/Assets.xcassets/AppIcon.appiconset")

// MARK: - Geometry helpers

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Cumulus silhouette: three lobes on a rounded base. `width` is the
/// overall width; origin is the bottom-left of the bounding box.
func cloudPath(origin: CGPoint, width w: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let base = origin.y
    let x = origin.x
    // Rounded base slab.
    let slabHeight = w * 0.30
    p.addRoundedRect(
        in: CGRect(x: x, y: base, width: w, height: slabHeight),
        cornerWidth: slabHeight / 2, cornerHeight: slabHeight / 2
    )
    // Lobes (left, big center, right).
    p.addEllipse(in: CGRect(x: x + w * 0.08, y: base + w * 0.06, width: w * 0.36, height: w * 0.36))
    p.addEllipse(in: CGRect(x: x + w * 0.30, y: base + w * 0.10, width: w * 0.48, height: w * 0.48))
    p.addEllipse(in: CGRect(x: x + w * 0.60, y: base + w * 0.04, width: w * 0.32, height: w * 0.32))
    return p
}

// MARK: - Rendering

func renderIcon(size px: Int) -> CGImage {
    let s = CGFloat(px)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // macOS icon grid: the squircle fills 824/1024 of the canvas.
    let inset = s * (100.0 / 1024.0)
    let tile = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = tile.width * 0.2237
    let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Soft drop shadow in the margin, like Apple's own icon template.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.035, color: rgb(0x000000, 0.28))
    ctx.addPath(tilePath)
    ctx.setFillColor(rgb(0x1A4FD6))
    ctx.fillPath()
    ctx.restoreGState()

    // Sky gradient.
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let sky = CGGradient(
        colorsSpace: cs,
        colors: [rgb(0x5CB0FF), rgb(0x2F7BEF), rgb(0x1A4FD6)] as CFArray,
        locations: [0, 0.55, 1]
    )!
    ctx.drawLinearGradient(
        sky, start: CGPoint(x: tile.midX, y: tile.maxY),
        end: CGPoint(x: tile.midX, y: tile.minY), options: []
    )
    // Light bloom in the upper-left so the tile isn't a flat ramp.
    let bloom = CGGradient(
        colorsSpace: cs,
        colors: [rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        bloom,
        startCenter: CGPoint(x: tile.minX + tile.width * 0.28, y: tile.maxY - tile.height * 0.18),
        startRadius: 0,
        endCenter: CGPoint(x: tile.minX + tile.width * 0.28, y: tile.maxY - tile.height * 0.18),
        endRadius: tile.width * 0.75,
        options: []
    )

    // Back cloud: smaller, translucent, up and to the right.
    let backWidth = tile.width * 0.46
    let back = cloudPath(
        origin: CGPoint(x: tile.minX + tile.width * 0.42, y: tile.minY + tile.height * 0.50),
        width: backWidth
    )
    ctx.setFillColor(rgb(0xFFFFFF, 0.45))
    ctx.addPath(back)
    ctx.fillPath()

    // Front cloud: solid, centred low, with a faint underside tint and a
    // soft shadow onto the sky.
    let frontWidth = tile.width * 0.68
    let frontOrigin = CGPoint(x: tile.minX + tile.width * 0.14, y: tile.minY + tile.height * 0.24)
    let front = cloudPath(origin: frontOrigin, width: frontWidth)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.018), blur: s * 0.05, color: rgb(0x0A2A80, 0.35))
    ctx.addPath(front)
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(front)
    ctx.clip()
    let cloudShade = CGGradient(
        colorsSpace: cs,
        colors: [rgb(0xFFFFFF), rgb(0xFFFFFF), rgb(0xDCE8FF)] as CFArray,
        locations: [0, 0.55, 1]
    )!
    ctx.drawLinearGradient(
        cloudShade,
        start: CGPoint(x: tile.midX, y: frontOrigin.y + frontWidth * 0.58),
        end: CGPoint(x: tile.midX, y: frontOrigin.y),
        options: []
    )
    ctx.restoreGState()
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("Failed to write \(url.path)") }
}

// MARK: - Asset catalog

struct Slot { let points: Int; let scale: Int }
let slots: [Slot] = [
    .init(points: 16, scale: 1), .init(points: 16, scale: 2),
    .init(points: 32, scale: 1), .init(points: 32, scale: 2),
    .init(points: 128, scale: 1), .init(points: 128, scale: 2),
    .init(points: 256, scale: 1), .init(points: 256, scale: 2),
    .init(points: 512, scale: 1), .init(points: 512, scale: 2),
]

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

// Render once at 1024 and downsample so every size shares identical geometry.
let master = renderIcon(size: 1024)
var images: [[String: String]] = []
for slot in slots {
    let px = slot.points * slot.scale
    let filename = "icon_\(slot.points)x\(slot.points)@\(slot.scale)x.png"
    let image: CGImage
    if px == 1024 {
        image = master
    } else {
        let ctx = CGContext(
            data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.interpolationQuality = .high
        ctx.draw(master, in: CGRect(x: 0, y: 0, width: px, height: px))
        image = ctx.makeImage()!
    }
    writePNG(image, to: outputDir.appendingPathComponent(filename))
    images.append([
        "filename": filename,
        "idiom": "mac",
        "scale": "\(slot.scale)x",
        "size": "\(slot.points)x\(slot.points)",
    ])
}

let contents: [String: Any] = [
    "images": images,
    "info": ["author": "xcode", "version": 1],
]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputDir.appendingPathComponent("Contents.json"))

// Parent catalog needs its own Contents.json.
let catalogContents = try JSONSerialization.data(
    withJSONObject: ["info": ["author": "xcode", "version": 1]], options: [.prettyPrinted]
)
try catalogContents.write(to: outputDir.deletingLastPathComponent().appendingPathComponent("Contents.json"))

print("Wrote \(images.count) icons to \(outputDir.path)")
