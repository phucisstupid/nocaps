import AppKit

func drawIcon(in context: CGContext, size: CGFloat, monochrome: Bool) {
    context.saveGState()
    defer { context.restoreGState() }
    context.scaleBy(x: size / 100, y: size / 100)
    if !monochrome {
        context.setFillColor(CGColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    let keycap = CGPath(
        roundedRect: CGRect(x: 9, y: 9, width: 82, height: 82),
        cornerWidth: 16, cornerHeight: 16, transform: nil
    )
    if !monochrome {
        context.addPath(keycap)
        context.setFillColor(CGColor(red: 0.15, green: 0.17, blue: 0.20, alpha: 1))
        context.fillPath()
    }
    context.addPath(keycap)
    context.setStrokeColor(
        monochrome
            ? CGColor(gray: 0, alpha: 1)
            : CGColor(red: 0.45, green: 0.48, blue: 0.53, alpha: 1)
    )
    context.setLineWidth(5.5)
    context.strokePath()

    context.move(to: CGPoint(x: 32, y: 43))
    context.addLine(to: CGPoint(x: 50, y: 61))
    context.addLine(to: CGPoint(x: 68, y: 43))
    context.setStrokeColor(monochrome ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 0.95, alpha: 1))
    context.setLineWidth(10)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
}

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: render-icons <iconset-directory> <menu-icon.pdf>")
}
let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        drawIcon(in: context, size: CGFloat(pixels), monochrome: false)
        let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
        let png = bitmap.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}

let menuURL = URL(fileURLWithPath: CommandLine.arguments[2])
var bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
let consumer = CGDataConsumer(url: menuURL as CFURL)!
let context = CGContext(consumer: consumer, mediaBox: &bounds, nil)!
context.beginPDFPage(nil)
drawIcon(in: context, size: 18, monochrome: true)
context.endPDFPage()
context.closePDF()
