// Rebuild the code-drawn pop-art icon: swift scripts/generate-icon.swift
import Foundation
import CoreGraphics
import ImageIO

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = root.appendingPathComponent("LaneAhead/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let ink = CGColor(red: 0.08, green: 0.075, blue: 0.10, alpha: 1)
let blue = CGColor(red: 0.08, green: 0.24, blue: 0.86, alpha: 1)
context.setFillColor(CGColor(red: 1, green: 0.87, blue: 0.18, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.setFillColor(CGColor(red: 0.08, green: 0.075, blue: 0.10, alpha: 0.17))
for x in stride(from: 20, to: 1024, by: 34) {
    for y in stride(from: 20, to: 1024, by: 34) {
        context.fillEllipse(in: CGRect(x: x, y: y, width: 6, height: 6))
    }
}
context.setLineWidth(9)
context.setStrokeColor(ink)
context.setFillColor(CGColor(red: 1, green: 0.38, blue: 0.64, alpha: 1))
let pink = CGRect(x: 710, y: 710, width: 400, height: 400)
context.fillEllipse(in: pink); context.strokeEllipse(in: pink)
context.setFillColor(CGColor(red: 0.53, green: 0.88, blue: 0.95, alpha: 1))
let cyan = CGRect(x: -160, y: -160, width: 420, height: 420)
context.fillEllipse(in: cyan); context.strokeEllipse(in: cyan)
context.setLineCap(.round); context.setLineJoin(.round)
for (x, top) in [(285.0, 600.0), (512.0, 780.0), (739.0, 600.0)] {
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: x, y: 225)); arrow.addLine(to: CGPoint(x: x, y: top))
    arrow.move(to: CGPoint(x: x - 72, y: top - 80)); arrow.addLine(to: CGPoint(x: x, y: top))
    arrow.addLine(to: CGPoint(x: x + 72, y: top - 80))
    context.setStrokeColor(ink); context.setLineWidth(83); context.addPath(arrow); context.strokePath()
    context.setStrokeColor(blue); context.setLineWidth(55); context.addPath(arrow); context.strokePath()
}
let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination), "Icon export failed")
print("Generated pop-art AppIcon.png")
