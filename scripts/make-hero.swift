// Composes the README's header pictures: the name, a line under it, and the jars standing on the
// bottom of a screen. Usage: swift scripts/make-hero.swift <shelf-alpha.png> <output folder>
// The shelf picture is what the test instance's `snap` writes as `<name>-alpha.png`: the jars on
// nothing, the full screen's size, standing on its bottom edge.
import AppKit

let args = CommandLine.arguments
guard args.count > 2, let shelf = NSImage(contentsOfFile: args[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("usage: make-hero.swift <shelf-alpha.png> <output folder>\n".utf8))
    exit(1)
}
let outFolder = URL(fileURLWithPath: args[2], isDirectory: true)
// The jars' handwriting, from the app's own resources.
let fontURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/Conserva/Resources/Fonts/Caveat.ttf")
CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)

let canvas = CGSize(width: 2400, height: 1280)
let title = "Conserva"
let tagline = "Things to read later, kept in jars."

/// The jars with a little air around them, down to the bottom edge they stand on.
func jarsRegion(of image: CGImage) -> CGRect {
    let w = image.width, h = image.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    // Rows in memory run from the top of the picture down, as `cropping(to:)` counts them.
    var minX = w, maxX = 0, top = h
    for row in 0..<h {
        for x in 0..<w where data[(row * w + x) * 4 + 3] > 8 {
            minX = min(minX, x); maxX = max(maxX, x); top = min(top, row)
        }
    }
    let margin = 40
    let left = max(0, minX - margin), right = min(w, maxX + margin), above = max(0, top - margin)
    return CGRect(x: left, y: above, width: right - left, height: h - above)
}

let region = jarsRegion(of: shelf)
guard let jars = shelf.cropping(to: region) else { exit(1) }

struct Theme {
    let name: String
    let background: NSColor, titleColor: NSColor, taglineColor: NSColor
    let desktop: (NSColor, NSColor)
    let shadow: Bool
}
let themes = [
    Theme(name: "light", background: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
          titleColor: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1), taglineColor: NSColor(srgbRed: 0.43, green: 0.43, blue: 0.45, alpha: 1),
          desktop: (NSColor(srgbRed: 0.87, green: 0.91, blue: 0.94, alpha: 1), NSColor(srgbRed: 0.96, green: 0.91, blue: 0.85, alpha: 1)), shadow: true),
    Theme(name: "dark", background: NSColor(srgbRed: 0.051, green: 0.067, blue: 0.090, alpha: 1),
          titleColor: NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1), taglineColor: NSColor(srgbRed: 0.63, green: 0.63, blue: 0.65, alpha: 1),
          desktop: (NSColor(srgbRed: 0.055, green: 0.078, blue: 0.125, alpha: 1), NSColor(srgbRed: 0.165, green: 0.129, blue: 0.094, alpha: 1)), shadow: false),
]

for theme in themes {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    theme.background.setFill()
    CGRect(origin: .zero, size: canvas).fill()

    // The screen: a rounded card whose bottom edge is the floor the jars stand on.
    let screen = CGRect(x: 100, y: 60, width: 2200, height: 740)
    let path = NSBezierPath(roundedRect: screen, xRadius: 36, yRadius: 36)
    if theme.shadow {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 50, color: CGColor(gray: 0, alpha: 0.16))
        theme.desktop.0.setFill()
        path.fill()
        ctx.restoreGState()
    }
    ctx.saveGState()
    path.addClip()
    NSGradient(starting: theme.desktop.0, ending: theme.desktop.1)!.draw(in: screen, angle: -90)
    ctx.restoreGState()
    if !theme.shadow {
        NSColor(white: 1, alpha: 0.08).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
    // The jars stand on the screen's bottom edge, sized by the jar itself rather than by the picture,
    // so an open lid or a slip on its way out rises past the screen's top instead of shrinking the jars.
    // A jar is the design box's height at the shelf's scale, drawn at two pixels a point.
    let jarHeight: CGFloat = 430 * 0.62 * 2
    let scale = min(560 / jarHeight, 2000 / CGFloat(jars.width))
    let size = CGSize(width: CGFloat(jars.width) * scale, height: CGFloat(jars.height) * scale)
    let at = CGRect(x: screen.midX - size.width / 2, y: screen.minY, width: size.width, height: size.height)
    ctx.interpolationQuality = .high
    ctx.draw(jars, in: at)

    func text(_ s: String, font: NSFont, color: NSColor, y: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = s.size(withAttributes: attributes)
        s.draw(at: CGPoint(x: canvas.width / 2 - size.width / 2, y: y), withAttributes: attributes)
    }
    // The name is written by hand on a paper label stuck on with two bits of tape, the way the jars
    // are labelled, not set in type.
    let hand = NSFont(name: "Caveat-Bold", size: 190) ?? NSFont(name: "Caveat", size: 190) ?? NSFont.systemFont(ofSize: 160, weight: .bold)
    let titleSize = title.size(withAttributes: [.font: hand])
    let label = CGRect(x: canvas.width / 2 - titleSize.width / 2 - 70, y: 950, width: titleSize.width + 140, height: 230)
    ctx.saveGState()
    ctx.translateBy(x: label.midX, y: label.midY)
    ctx.rotate(by: -0.012)
    ctx.translateBy(x: -label.midX, y: -label.midY)
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 22, color: CGColor(gray: 0, alpha: theme.shadow ? 0.18 : 0.5))
    NSColor(srgbRed: 0.957, green: 0.922, blue: 0.827, alpha: 1).setFill()
    let paper = NSBezierPath()
    paper.move(to: CGPoint(x: label.minX, y: label.minY + 6))
    paper.line(to: CGPoint(x: label.maxX - 4, y: label.minY))
    paper.line(to: CGPoint(x: label.maxX, y: label.maxY - 8))
    paper.line(to: CGPoint(x: label.minX + 6, y: label.maxY))
    paper.close()
    paper.fill()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    NSColor(srgbRed: 0.788, green: 0.725, blue: 0.561, alpha: 0.6).setStroke()
    paper.lineWidth = 2
    paper.stroke()
    for x in [label.minX + 40, label.maxX - 40] {
        ctx.saveGState()
        ctx.translateBy(x: x, y: label.maxY)
        ctx.rotate(by: x < canvas.width / 2 ? -0.5 : 0.5)
        NSColor(srgbRed: 0.95, green: 0.94, blue: 0.9, alpha: 0.78).setFill()
        CGRect(x: -58, y: -18, width: 116, height: 36).fill()
        ctx.restoreGState()
    }
    let ink = NSColor(srgbRed: 0.176, green: 0.290, blue: 0.541, alpha: 1)
    title.draw(at: CGPoint(x: label.midX - titleSize.width / 2, y: label.midY - titleSize.height / 2 + 4), withAttributes: [.font: hand, .foregroundColor: ink])
    ctx.restoreGState()
    text(tagline, font: NSFont.systemFont(ofSize: 54, weight: .regular), color: theme.taglineColor, y: 862)

    NSGraphicsContext.restoreGraphicsState()
    let url = outFolder.appendingPathComponent("hero-\(theme.name).png")
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.path)")
}
