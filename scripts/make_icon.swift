#!/usr/bin/env swift
// Generates the Oxygen Flow app icon: a rounded "squircle" in a cobalt-blue gradient
// with two white chevrons (»), reading as flow / motion.
// Renders a 1024px master PNG, then builds AppIcon.icns via `sips` + `iconutil`.
//
// Usage: swift scripts/make_icon.swift  (run from the project root)

import AppKit

let S: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(red: r/255, green: g/255, blue: b/255, alpha: 1)
}

// --- Squircle background with cobalt vertical gradient ---
let margin: CGFloat = 88
let rect = CGRect(x: margin, y: margin, width: S - margin*2, height: S - margin*2)
let corner: CGFloat = (S - margin*2) * 0.235
let squircle = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let top = rgb(30, 30, 32)        // near-black (subtle gloss)
let bottom = rgb(0, 0, 0)        // black
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [top, bottom] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
// subtle top sheen
let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.16),
                                CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                       locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: S*0.55), options: [])
ctx.restoreGState()

// --- Single chevron (>), white, round joins ---
let cx = S/2, cy = S/2
let halfH: CGFloat = 230      // vertical reach of the chevron arms
let armW: CGFloat  = 175      // horizontal depth of the chevron
let lineW: CGFloat = 104

let apex = cx + armW * 0.45   // nudge the point toward center
let chevron = CGMutablePath()
chevron.move(to: CGPoint(x: apex - armW, y: cy + halfH))
chevron.addLine(to: CGPoint(x: apex,          y: cy))
chevron.addLine(to: CGPoint(x: apex - armW, y: cy - halfH))

ctx.setStrokeColor(rgb(20, 180, 200)) // Bahama teal accent
ctx.setLineWidth(lineW)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.addPath(chevron)
ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()

// --- Write master PNG ---
let outDir = "scripts/.icon-out"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let masterURL = URL(fileURLWithPath: "\(outDir)/master-1024.png")
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: masterURL)
print("wrote \(masterURL.path)")
