import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift generate_icon.swift <output_iconset_dir>\n", stderr)
    exit(1)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let specs: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func renderIcon(size px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }

    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    let s = CGFloat(px)
    let inset = s * 0.085
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Subtle outer shadow
    cg.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.26)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.02)
    shadow.shadowBlurRadius = s * 0.045
    shadow.set()
    NSColor.white.setFill()
    squircle.fill()
    cg.restoreGState()

    // Gradient background clipped to squircle
    cg.saveGState()
    squircle.addClip()
    let colors = [
        NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.0, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.00, green: 0.76, blue: 0.72, alpha: 1.0).cgColor,
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
        cg.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }

    // Subtle top sheen
    let sheenRect = CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height * 0.5)
    let sheenColors = [
        NSColor.white.withAlphaComponent(0.22).cgColor,
        NSColor.white.withAlphaComponent(0.0).cgColor,
    ] as CFArray
    if let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sheenColors, locations: [0.0, 1.0]) {
        cg.drawLinearGradient(
            sheen,
            start: CGPoint(x: sheenRect.midX, y: sheenRect.maxY),
            end: CGPoint(x: sheenRect.midX, y: sheenRect.minY),
            options: []
        )
    }
    cg.restoreGState()

    // Inner hairline border
    NSColor.white.withAlphaComponent(0.25).setStroke()
    squircle.lineWidth = max(1.0, s * 0.012)
    squircle.stroke()

    // White SF Symbol glyph
    let pointSize = s * 0.44
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        .applying(.init(hierarchicalColor: .white))
    if let symbol = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?
        .withSymbolConfiguration(config)
    {
        let symSize = symbol.size
        let targetMax = s * 0.56
        let scale = min(targetMax / max(symSize.width, 1), targetMax / max(symSize.height, 1))
        let drawW = symSize.width * scale
        let drawH = symSize.height * scale
        let drawRect = CGRect(
            x: (s - drawW) / 2.0,
            y: (s - drawH) / 2.0,
            width: drawW,
            height: drawH
        )

        cg.saveGState()
        let glyphShadow = NSShadow()
        glyphShadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        glyphShadow.shadowOffset = NSSize(width: 0, height: -s * 0.015)
        glyphShadow.shadowBlurRadius = s * 0.03
        glyphShadow.set()
        symbol.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        cg.restoreGState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for spec in specs {
    guard let png = renderIcon(size: spec.px) else {
        fputs("Failed to render \(spec.name)\n", stderr)
        exit(1)
    }
    let fileURL = outputDir.appendingPathComponent(spec.name)
    try png.write(to: fileURL)
}
