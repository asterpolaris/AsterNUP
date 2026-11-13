// Renders AsterNUP's app icon (an original four-point star on a deep blue tile) to Resources/App/AppIcon.icns,
// on Apple's macOS icon grid: an 824 pt rounded-square body centred on a 1024 pt canvas, with a soft drop shadow.
// Usage: swift scripts/make_icon.swift
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

/// A rounded square with continuous ("squircle") corners, built from cubic curves like Apple's icon shape.
func squircle(_ r: NSRect, radius: CGFloat) -> NSBezierPath {
    let p = NSBezierPath(), k: CGFloat = 1.28195, c: CGFloat = 0.5 // smoothing beyond a circular arc
    let rr = min(radius * k, min(r.width, r.height) / 2)
    let (x0, y0, x1, y1) = (r.minX, r.minY, r.maxX, r.maxY)
    p.move(to: NSPoint(x: x0 + rr, y: y0))
    p.line(to: NSPoint(x: x1 - rr, y: y0))
    p.curve(to: NSPoint(x: x1, y: y0 + rr), controlPoint1: NSPoint(x: x1 - rr * c * 0.5, y: y0), controlPoint2: NSPoint(x: x1, y: y0 + rr * c * 0.5))
    p.line(to: NSPoint(x: x1, y: y1 - rr))
    p.curve(to: NSPoint(x: x1 - rr, y: y1), controlPoint1: NSPoint(x: x1, y: y1 - rr * c * 0.5), controlPoint2: NSPoint(x: x1 - rr * c * 0.5, y: y1))
    p.line(to: NSPoint(x: x0 + rr, y: y1))
    p.curve(to: NSPoint(x: x0, y: y1 - rr), controlPoint1: NSPoint(x: x0 + rr * c * 0.5, y: y1), controlPoint2: NSPoint(x: x0, y: y1 - rr * c * 0.5))
    p.line(to: NSPoint(x: x0, y: y0 + rr))
    p.curve(to: NSPoint(x: x0 + rr, y: y0), controlPoint1: NSPoint(x: x0, y: y0 + rr * c * 0.5), controlPoint2: NSPoint(x: x0 + rr * c * 0.5, y: y0))
    p.close()
    return p
}

func star(center c: NSPoint, outer R: CGFloat, inner r: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4 + .pi / 2, rad = i % 2 == 0 ? R : r
        let pt = NSPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad)
        i == 0 ? p.move(to: pt) : p.line(to: pt)
    }
    p.close()
    return p
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    let body = NSRect(x: 100 * s, y: 100 * s + 8 * s, width: 824 * s, height: 824 * s)
    let tile = squircle(body, radius: 185 * s)

    // Drop shadow, as on Apple's template.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s); shadow.shadowBlurRadius = 24 * s; shadow.set()
    NSColor.black.setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Body: deep night-blue gradient with a glow behind the star and a soft top highlight.
    NSGradient(colors: [NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.16, alpha: 1),
                        NSColor(calibratedRed: 0.09, green: 0.20, blue: 0.38, alpha: 1)])!.draw(in: tile, angle: 90)
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    let c = NSPoint(x: body.midX, y: body.midY)
    NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.75, blue: 1.0, alpha: 0.55), NSColor(calibratedRed: 0.10, green: 0.75, blue: 1.0, alpha: 0)])!
        .draw(fromCenter: c, radius: 0, toCenter: c, radius: 380 * s, options: [])
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: 90 + 180)
    NSGraphicsContext.restoreGraphicsState()

    // The star, lit from above, and a small companion star.
    let main = star(center: c, outer: 270 * s, inner: 64 * s)
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow(); glow.shadowColor = NSColor(calibratedRed: 0.3, green: 0.85, blue: 1, alpha: 0.9); glow.shadowBlurRadius = 36 * s; glow.set()
    NSColor.white.setFill(); main.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(calibratedRed: 0.55, green: 0.93, blue: 1.0, alpha: 1), NSColor.white])!.draw(in: main, angle: 90)
    NSColor.white.withAlphaComponent(0.92).setFill()
    star(center: NSPoint(x: c.x + 190 * s, y: c.y + 190 * s), outer: 60 * s, inner: 15 * s).fill()

    // Hairline edge.
    NSColor.white.withAlphaComponent(0.12).setStroke(); tile.lineWidth = max(1, 2 * s); tile.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for px in sizes {
    if px <= 512 { try! render(px).write(to: set.appendingPathComponent("icon_\(px)x\(px).png")) }
    if px >= 32 { try! render(px).write(to: set.appendingPathComponent("icon_\(px / 2)x\(px / 2)@2x.png")) }
}
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", "Resources/App/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Resources/App/AppIcon.icns" : "iconutil failed")
