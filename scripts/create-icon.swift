import AppKit
import Foundation

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform(); transform.scale(by: factor); transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 210, yRadius: 210)
        let gradient = NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.19, blue: 0.42, alpha: 1),
                                  ending: NSColor(calibratedRed: 0.22, green: 0.48, blue: 0.75, alpha: 1))!
        gradient.draw(in: background, angle: 45)
        let body = NSBezierPath(roundedRect: NSRect(x: 315, y: 222, width: 394, height: 578), xRadius: 192, yRadius: 192)
        NSColor.white.setFill(); body.fill()
        let seam = NSBezierPath(); seam.move(to: NSPoint(x: 512, y: 800)); seam.line(to: NSPoint(x: 512, y: 573))
        seam.lineWidth = 16; NSColor(calibratedRed: 0.22, green: 0.48, blue: 0.75, alpha: 1).setStroke(); seam.stroke()
        let wheel = NSBezierPath(roundedRect: NSRect(x: 491, y: 656, width: 42, height: 83), xRadius: 21, yRadius: 21)
        NSColor(calibratedRed: 0.22, green: 0.48, blue: 0.75, alpha: 1).setFill(); wheel.fill()
        for row in 0..<4 {
            let dot = NSBezierPath(roundedRect: NSRect(x: 358, y: 335 + row * 58, width: 29, height: 29), xRadius: 9, yRadius: 9)
            NSColor(calibratedRed: 0.22, green: 0.48, blue: 0.75, alpha: 1).setFill(); dot.fill()
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon rendering failed") }
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: URL(fileURLWithPath: destination).appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
