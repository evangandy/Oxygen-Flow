#!/usr/bin/env swift
// Generates the Oxygen Flow app icon: a near-black rounded "squircle" with a single centered
// white circle.
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

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r/255, green: g/255, blue: b/255, alpha: a)
}

// --- Squircle background, near-black with a faint top sheen ---
let margin: CGFloat = 88
let rect = CGRect(x: margin, y: margin, width: S - margin*2, height: S - margin*2)
let corner: CGFloat = (S - margin*2) * 0.235
let squircle = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let top = rgb(30, 30, 32)
let bottom = rgb(0, 0, 0)
let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                         colors: [top, bottom] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.16),
                                 CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                        locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: S*0.55), options: [])
ctx.restoreGState()

// --- Single centered white circle ---
let cx = S/2, cy = S/2
let r: CGFloat = 250
let circle = CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r*2, height: r*2), transform: nil)

ctx.saveGState()
ctx.setFillColor(rgb(255, 255, 255))
ctx.addPath(circle)
ctx.fillPath()
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()

// --- Write master PNG ---
let outDir = "scripts/.icon-out"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let masterURL = URL(fileURLWithPath: "\(outDir)/master-1024.png")
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: masterURL)
print("wrote \(masterURL.path)")
