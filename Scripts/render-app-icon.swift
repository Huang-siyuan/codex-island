#!/usr/bin/env swift

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("Usage: render-app-icon.swift <output-png-path>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let size = CGSize(width: 1024, height: 1024)
let rect = CGRect(origin: .zero, size: size)

guard
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
else {
    fputs("Failed to create bitmap representation\n", stderr)
    exit(1)
}

rep.size = size
NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
    fputs("Failed to create graphics context\n", stderr)
    exit(1)
}
NSGraphicsContext.current = context

func roundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func fill(_ path: NSBezierPath, colors: [NSColor], angle: CGFloat) {
    let gradient = NSGradient(colors: colors)!
    gradient.draw(in: path, angle: angle)
}

NSColor.clear.setFill()
rect.fill()

let cardRect = rect.insetBy(dx: 84, dy: 84)
let cardPath = roundedRect(cardRect, radius: 228)

context.cgContext.setShadow(
    offset: CGSize(width: 0, height: -28),
    blur: 80,
    color: NSColor(calibratedRed: 0.01, green: 0.03, blue: 0.07, alpha: 0.42).cgColor
)
fill(cardPath, colors: [
    NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.17, alpha: 1),
    NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.11, alpha: 1)
], angle: 315)
context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

NSColor(calibratedWhite: 1, alpha: 0.08).setStroke()
cardPath.lineWidth = 5
cardPath.stroke()

let haloRect = cardRect.insetBy(dx: 120, dy: 120)
let haloPath = roundedRect(haloRect, radius: 180)
fill(haloPath, colors: [
    NSColor(calibratedRed: 0.10, green: 0.20, blue: 0.33, alpha: 0.00),
    NSColor(calibratedRed: 0.16, green: 0.50, blue: 0.92, alpha: 0.12)
], angle: 90)

let islandRect = CGRect(x: 170, y: 530, width: 684, height: 198)
let islandPath = roundedRect(islandRect, radius: 99)
context.cgContext.setShadow(
    offset: CGSize(width: 0, height: -18),
    blur: 45,
    color: NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.09, alpha: 0.35).cgColor
)
fill(islandPath, colors: [
    NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.21, alpha: 1),
    NSColor(calibratedRed: 0.07, green: 0.10, blue: 0.16, alpha: 1)
], angle: 270)
context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

NSColor(calibratedWhite: 1, alpha: 0.11).setStroke()
islandPath.lineWidth = 4
islandPath.stroke()

let topShineRect = CGRect(x: islandRect.minX + 18, y: islandRect.midY + 18, width: islandRect.width - 36, height: 46)
let topShinePath = roundedRect(topShineRect, radius: 23)
fill(topShinePath, colors: [
    NSColor(calibratedWhite: 1, alpha: 0.18),
    NSColor(calibratedWhite: 1, alpha: 0.01)
], angle: 270)

let statusDotRect = CGRect(x: islandRect.minX + 66, y: islandRect.midY - 26, width: 52, height: 52)
let statusDotPath = NSBezierPath(ovalIn: statusDotRect)
context.cgContext.setShadow(
    offset: .zero,
    blur: 26,
    color: NSColor(calibratedRed: 0.31, green: 0.93, blue: 0.65, alpha: 0.85).cgColor
)
fill(statusDotPath, colors: [
    NSColor(calibratedRed: 0.62, green: 0.98, blue: 0.80, alpha: 1),
    NSColor(calibratedRed: 0.18, green: 0.80, blue: 0.50, alpha: 1)
], angle: 270)
context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

let barStartX = islandRect.minX + 158
let barYPositions: [CGFloat] = [islandRect.midY + 34, islandRect.midY, islandRect.midY - 34]
let barWidths: [CGFloat] = [356, 286, 236]
for (index, y) in barYPositions.enumerated() {
    let barRect = CGRect(x: barStartX, y: y - 11, width: barWidths[index], height: 22)
    let barPath = roundedRect(barRect, radius: 11)
    fill(barPath, colors: [
        NSColor(calibratedRed: 0.59, green: 0.77, blue: 0.99, alpha: 0.96),
        NSColor(calibratedRed: 0.28, green: 0.55, blue: 0.96, alpha: 0.88)
    ], angle: 0)
}

let badgeRect = CGRect(x: islandRect.maxX - 132, y: islandRect.midY - 36, width: 72, height: 72)
let badgePath = roundedRect(badgeRect, radius: 24)
fill(badgePath, colors: [
    NSColor(calibratedRed: 0.98, green: 0.77, blue: 0.34, alpha: 1),
    NSColor(calibratedRed: 0.94, green: 0.53, blue: 0.18, alpha: 1)
], angle: 270)

let bolt = NSBezierPath()
bolt.move(to: CGPoint(x: badgeRect.minX + 38, y: badgeRect.maxY - 14))
bolt.line(to: CGPoint(x: badgeRect.minX + 24, y: badgeRect.midY + 4))
bolt.line(to: CGPoint(x: badgeRect.midX + 2, y: badgeRect.midY + 4))
bolt.line(to: CGPoint(x: badgeRect.midX - 7, y: badgeRect.minY + 12))
bolt.line(to: CGPoint(x: badgeRect.maxX - 20, y: badgeRect.midY - 4))
bolt.line(to: CGPoint(x: badgeRect.midX + 5, y: badgeRect.midY - 4))
bolt.close()
NSColor(calibratedWhite: 1, alpha: 0.94).setFill()
bolt.fill()

let accentRect = CGRect(x: 232, y: 338, width: 560, height: 26)
let accentPath = roundedRect(accentRect, radius: 13)
fill(accentPath, colors: [
    NSColor(calibratedRed: 0.21, green: 0.96, blue: 0.77, alpha: 0.9),
    NSColor(calibratedRed: 0.17, green: 0.62, blue: 0.98, alpha: 0.85)
], angle: 0)

NSGraphicsContext.restoreGraphicsState()

guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG data\n", stderr)
    exit(1)
}

do {
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try pngData.write(to: outputURL)
} catch {
    fputs("Failed to write PNG: \(error)\n", stderr)
    exit(1)
}
