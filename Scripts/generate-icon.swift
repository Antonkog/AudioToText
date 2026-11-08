#!/usr/bin/env swift

import AppKit
import Foundation

let projectDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let resources = projectDirectory.appendingPathComponent("Resources", isDirectory: true)
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("AudioToText-AppIcon-\(UUID().uuidString).iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

func render(size: Int) throws -> Data {
    let dimension = CGFloat(size)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { throw CocoaError(.fileWriteUnknown) }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: dimension, height: dimension).fill()

    let inset = dimension * 0.065
    let background = NSBezierPath(
        roundedRect: NSRect(x: inset, y: inset, width: dimension - inset * 2, height: dimension - inset * 2),
        xRadius: dimension * 0.21,
        yRadius: dimension * 0.21
    )
    NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.14, alpha: 1).setFill()
    background.fill()

    let heights: [CGFloat] = [0.28, 0.50, 0.80, 0.58, 0.94, 0.64, 0.38]
    let barWidth = dimension * 0.058
    let spacing = dimension * 0.045
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * spacing
    let startX = (dimension - totalWidth) / 2
    for (index, height) in heights.enumerated() {
        let barHeight = dimension * height * 0.48
        let rect = NSRect(
            x: startX + CGFloat(index) * (barWidth + spacing),
            y: (dimension - barHeight) / 2,
            width: barWidth,
            height: barHeight
        )
        NSColor.white.setFill()
        NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

let representations: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in representations {
    try render(size: size).write(to: iconset.appendingPathComponent(name))
}
try render(size: 1024).write(to: resources.appendingPathComponent("AppIcon-1024.png"))

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "--convert", "icns",
    "--output", resources.appendingPathComponent("AppIcon.icns").path,
    iconset.path
]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
