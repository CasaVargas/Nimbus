#!/usr/bin/env swift
//
// Writes the Finder sidebar symbol for Nimbus's File Provider locations:
// Nimbus/FileProviderExtension/Assets.xcassets/nimbus.symbolset
//
// macOS takes a File Provider's sidebar glyph from the EXTENSION's
// Info.plist (CFBundleIcons > CFBundlePrimaryIcon > CFBundleSymbolName),
// resolved against the extension's own asset catalog. Without it Finder
// falls back to a generic icon.
//
// The glyph is the app icon's two clouds (see render-app-icon.swift, same
// silhouette) as one monochrome shape: the front cloud solid, the back
// cloud cut away around it so the two still read apart at 16 pt.
//
// Usage: swift scripts/render-sidebar-symbol.swift

import CoreGraphics
import Foundation

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let catalog = repoRoot.appendingPathComponent("Nimbus/FileProviderExtension/Assets.xcassets")
let symbolset = catalog.appendingPathComponent("nimbus.symbolset")

/// Same cumulus silhouette as the app icon, in a y-up space. Returned as
/// one merged outline so overlapping lobes don't cancel under even-odd
/// rules or show seams.
func cloud(origin: CGPoint, width w: CGFloat) -> CGPath {
    let slabHeight = w * 0.30
    var path = CGPath(
        roundedRect: CGRect(x: origin.x, y: origin.y, width: w, height: slabHeight),
        cornerWidth: slabHeight / 2, cornerHeight: slabHeight / 2, transform: nil
    )
    let lobes = [
        CGRect(x: origin.x + w * 0.08, y: origin.y + w * 0.06, width: w * 0.36, height: w * 0.36),
        CGRect(x: origin.x + w * 0.30, y: origin.y + w * 0.10, width: w * 0.48, height: w * 0.48),
        CGRect(x: origin.x + w * 0.60, y: origin.y + w * 0.04, width: w * 0.32, height: w * 0.32),
    ]
    for lobe in lobes {
        path = path.union(CGPath(ellipseIn: lobe, transform: nil))
    }
    return path
}

// Design space: y-up, in SF Symbol template units (100 pt font, cap height
// 70.459). The glyph is centred on the cap-height midline like Apple's own
// cloud symbols, and slightly taller than the caps.
let capHeight: CGFloat = 70.459
let glyphWidth: CGFloat = 122
let sideBearing: CGFloat = 8

let front = cloud(origin: CGPoint(x: 0, y: 0), width: glyphWidth * 0.80)
let back = cloud(origin: CGPoint(x: glyphWidth * 0.40, y: glyphWidth * 0.26), width: glyphWidth * 0.60)

// Cut the back cloud away around the front one, leaving a visible gap.
let gap: CGFloat = 6.5
let halo = front.union(front.copy(
    strokingWithWidth: gap * 2, lineCap: .round, lineJoin: .round, miterLimit: 1
))
let glyph = front.union(back.subtracting(halo))

/// The glyph as SVG path data in template space (y-down, baseline at
/// y = 0, left margin at x = 0), scaled about the cap-height midline the
/// way Apple's small/medium/large symbol scales are.
func master(scale: CGFloat) -> (d: String, advance: CGFloat) {
    let box = glyph.boundingBoxOfPath
    let height = box.height * scale
    let bottom = (capHeight - height) / 2          // glyph base above the baseline
    // y' = -scale * (y - box.minY) - bottom
    var toTemplate = CGAffineTransform(
        a: scale, b: 0, c: 0, d: -scale,
        tx: sideBearing - box.minX * scale,
        ty: box.minY * scale - bottom
    )
    guard let placed = glyph.copy(using: &toTemplate) else { fatalError("transform failed") }
    var d = ""
    placed.applyWithBlock { element in
        let p = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: d += "M\(f(p[0].x)) \(f(p[0].y)) "
        case .addLineToPoint: d += "L\(f(p[0].x)) \(f(p[0].y)) "
        case .addQuadCurveToPoint: d += "Q\(f(p[0].x)) \(f(p[0].y)) \(f(p[1].x)) \(f(p[1].y)) "
        case .addCurveToPoint:
            d += "C\(f(p[0].x)) \(f(p[0].y)) \(f(p[1].x)) \(f(p[1].y)) \(f(p[2].x)) \(f(p[2].y)) "
        case .closeSubpath: d += "Z "
        @unknown default: break
        }
    }
    return (d.trimmingCharacters(in: .whitespaces), box.width * scale + sideBearing * 2)
}

func f(_ v: CGFloat) -> String { String(format: "%.3f", v) }

// Static template: Regular weight at the three scales, plus the guides
// Xcode's symbol compiler requires (it rejects a template with no
// Regular-M master). Baselines match Apple's exported templates.
let originX: CGFloat = 1500
let scales: [(name: String, scale: CGFloat, baseline: CGFloat)] = [
    ("S", 1.0, 696), ("M", 1.27, 1126), ("L", 1.64, 1556),
]
var guides = ""
var masters = ""
for entry in scales {
    let m = master(scale: entry.scale)
    let b = entry.baseline
    guides += """
      <line id="Baseline-\(entry.name)" x1="263" x2="3036" y1="\(f(b))" y2="\(f(b))" style="fill:none;stroke:#27AAE1;stroke-width:0.5"/>
      <line id="Capline-\(entry.name)" x1="263" x2="3036" y1="\(f(b - capHeight))" y2="\(f(b - capHeight))" style="fill:none;stroke:#27AAE1;stroke-width:0.5"/>
      <line id="left-margin-Regular-\(entry.name)" x1="\(f(originX))" x2="\(f(originX))" y1="\(f(b - 95))" y2="\(f(b + 24))" style="fill:none;stroke:#00AEEF;stroke-width:0.5"/>
      <line id="right-margin-Regular-\(entry.name)" x1="\(f(originX + m.advance))" x2="\(f(originX + m.advance))" y1="\(f(b - 95))" y2="\(f(b + 24))" style="fill:none;stroke:#00AEEF;stroke-width:0.5"/>

    """
    masters += """
      <g id="Regular-\(entry.name)" transform="matrix(1 0 0 1 \(f(originX)) \(f(b)))">
       <path d="\(m.d)"/>
      </g>

    """
}
let svg = """
<?xml version="1.0" encoding="UTF-8"?>
<!-- Generated by scripts/render-sidebar-symbol.swift. Do not edit by hand. -->
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" width="3300" height="2200">
 <g id="Notes">
  <text id="template-version" x="3036" y="1933" text-anchor="end" style="font-family: -apple-system; font-size: 13px;">Template v.3.0</text>
 </g>
 <g id="Guides">
\(guides) </g>
 <g id="Symbols">
\(masters) </g>
</svg>

"""

let fm = FileManager.default
try fm.createDirectory(at: symbolset, withIntermediateDirectories: true)
try svg.write(to: symbolset.appendingPathComponent("nimbus.svg"), atomically: true, encoding: .utf8)
try """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "symbols" : [
    {
      "filename" : "nimbus.svg",
      "idiom" : "universal"
    }
  ]
}

""".write(to: symbolset.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

""".write(to: catalog.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

// The menu bar item draws the same glyph, so the app's catalog carries a
// copy (an app cannot read symbols from its extension's catalog).
let appSymbolset = repoRoot.appendingPathComponent("Nimbus/Nimbus/Resources/Assets.xcassets/nimbus.symbolset")
try? fm.removeItem(at: appSymbolset)
try fm.copyItem(at: symbolset, to: appSymbolset)

print("Wrote \(symbolset.path)")
print("Wrote \(appSymbolset.path)")
