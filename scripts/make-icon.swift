// Draws the app icon, the "Jar" design: a Soviet 5-litre glass jar with a blue
// plastic cap, holding paper slips and a photo. Usage: swift scripts/make-icon.swift <output.png> [size]
import AppKit

let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "icon.png"
let size = args.count > 2 ? CGFloat(Double(args[2]) ?? 1024) : 1024

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.scaleBy(x: size / 1024, y: size / 1024)

// Drawn in a 1024 grid with the origin at the top left, like the design file.
ctx.translateBy(x: 0, y: 1024)
ctx.scaleBy(x: 1, y: -1)

func gray(_ v: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(gray: v, alpha: a) }
func hex(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}
func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    let locs = locations ?? colors.indices.map { CGFloat($0) / CGFloat(colors.count - 1) }
    return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locs)!
}
func vertical(_ g: CGGradient, _ y0: CGFloat, _ y1: CGFloat) {
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: y0), end: CGPoint(x: 0, y: y1), options: [])
}
func horizontal(_ g: CGGradient, _ x0: CGFloat, _ x1: CGFloat) {
    ctx.drawLinearGradient(g, start: CGPoint(x: x0, y: 0), end: CGPoint(x: x1, y: 0), options: [])
}
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
/// Runs `body` in a frame centred on `c` and rotated by `degrees`.
func rotated(at c: CGPoint, _ degrees: CGFloat, _ body: () -> Void) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: degrees * .pi / 180)
    body()
    ctx.restoreGState()
}

// The macOS icon shape: 824 points square inside the 1024 canvas, soft shadow below.
let shape = rounded(CGRect(x: 100, y: 100, width: 824, height: 824), 186)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 32, color: gray(0, 0.28))
ctx.addPath(shape)
ctx.setFillColor(hex(0xF3E7D3))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
vertical(gradient([hex(0xF3E7D3), hex(0xE2CFAE)]), 100, 924)
ctx.restoreGState()

ctx.addPath(rounded(CGRect(x: 102, y: 102, width: 820, height: 820), 184))
ctx.setStrokeColor(gray(1, 0.5))
ctx.setLineWidth(4)
ctx.strokePath()

// Contact shadow under the jar.
ctx.saveGState()
ctx.translateBy(x: 512, y: 780)
ctx.scaleBy(x: 1, y: 0.14)
ctx.drawRadialGradient(gradient([gray(0, 0.42), gray(0, 0.18), gray(0, 0)], [0, 0.55, 1]),
                       startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 250, options: [])
ctx.restoreGState()

// Jar outline: neck, round shoulders, straight body, thick rounded heel.
let jar = CGMutablePath()
jar.move(to: CGPoint(x: 412, y: 314))
jar.addLine(to: CGPoint(x: 412, y: 356))
jar.addCurve(to: CGPoint(x: 332, y: 444), control1: CGPoint(x: 412, y: 400), control2: CGPoint(x: 332, y: 392))
jar.addLine(to: CGPoint(x: 332, y: 730))
jar.addCurve(to: CGPoint(x: 366, y: 772), control1: CGPoint(x: 332, y: 758), control2: CGPoint(x: 346, y: 772))
jar.addLine(to: CGPoint(x: 658, y: 772))
jar.addCurve(to: CGPoint(x: 692, y: 730), control1: CGPoint(x: 678, y: 772), control2: CGPoint(x: 692, y: 758))
jar.addLine(to: CGPoint(x: 692, y: 444))
jar.addCurve(to: CGPoint(x: 612, y: 356), control1: CGPoint(x: 692, y: 392), control2: CGPoint(x: 612, y: 400))
jar.addLine(to: CGPoint(x: 612, y: 314))
jar.closeSubpath()

// Faint glass body: the middle stays transparent.
ctx.saveGState()
ctx.addPath(jar)
ctx.setFillColor(hex(0x86CFC3, 0.16))
ctx.fillPath()
ctx.restoreGState()

// Contents, clipped to the jar.
ctx.saveGState()
ctx.addPath(jar)
ctx.clip()

func slip(_ c: CGPoint, _ angle: CGFloat, _ paper: UInt32, _ mark: UInt32) {
    rotated(at: c, angle) {
        let r = CGRect(x: -62, y: -30, width: 124, height: 60)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 6, color: gray(0, 0.3))
        ctx.addPath(rounded(r, 6))
        ctx.setFillColor(hex(paper))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(rounded(r, 6))
        ctx.setStrokeColor(gray(0, 0.14))
        ctx.setLineWidth(2)
        ctx.strokePath()
        ctx.addPath(rounded(CGRect(x: -50, y: -14, width: 28, height: 28), 7))
        ctx.setFillColor(hex(mark))
        ctx.fillPath()
        ctx.addPath(rounded(CGRect(x: -12, y: -9, width: 58, height: 8), 4))
        ctx.setFillColor(gray(0.55, 0.55))
        ctx.fillPath()
        ctx.addPath(rounded(CGRect(x: -12, y: 6, width: 38, height: 8), 4))
        ctx.fillPath()
    }
}

func photo(_ c: CGPoint, _ angle: CGFloat) {
    rotated(at: c, angle) {
        let frame = CGRect(x: -44, y: -52, width: 88, height: 104)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 7, color: gray(0, 0.35))
        ctx.addPath(rounded(frame, 5))
        ctx.setFillColor(gray(1))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(rounded(frame, 5))
        ctx.setStrokeColor(gray(0, 0.14))
        ctx.setLineWidth(2)
        ctx.strokePath()
        ctx.saveGState()
        let picture = CGRect(x: -35, y: -43, width: 70, height: 70)
        ctx.addPath(rounded(picture, 3))
        ctx.clip()
        vertical(gradient([hex(0x4DA3E8), hex(0x3CC9A4)]), picture.minY, picture.maxY)
        ctx.setFillColor(hex(0xFFFFFF, 0.85))
        ctx.fillEllipse(in: CGRect(x: 8, y: -34, width: 16, height: 16))
        ctx.setFillColor(hex(0x1F8F6E, 0.9))
        ctx.move(to: CGPoint(x: -40, y: 28))
        ctx.addLine(to: CGPoint(x: -12, y: -6))
        ctx.addLine(to: CGPoint(x: 8, y: 16))
        ctx.addLine(to: CGPoint(x: 22, y: 2))
        ctx.addLine(to: CGPoint(x: 40, y: 28))
        ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()
    }
}

// Bottom row, then the second layer, then the photo leaning on top.
slip(CGPoint(x: 415, y: 726), -4, 0xFDFCF9, 0x3478F6)
slip(CGPoint(x: 595, y: 724), 5, 0xFDFCF9, 0xE8743B)
slip(CGPoint(x: 505, y: 704), -9, 0xEAD39A, 0x34A853)
slip(CGPoint(x: 430, y: 668), 6, 0xFDFCF9, 0xE8743B)
photo(CGPoint(x: 590, y: 656), 9)

ctx.restoreGState()

// Paper label on the body, with ink strokes in place of letters.
rotated(at: CGPoint(x: 512, y: 530), -3) {
    let r = CGRect(x: -100, y: -62, width: 200, height: 124)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 7, color: gray(0, 0.3))
    ctx.addPath(rounded(r, 8))
    ctx.setFillColor(hex(0xF4EBD3))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(rounded(r, 8))
    ctx.setStrokeColor(hex(0x8A7A55, 0.5))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.setStrokeColor(hex(0x2D4A8A))
    ctx.setLineWidth(9)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let strokes = CGMutablePath()
    strokes.move(to: CGPoint(x: -70, y: -22))
    strokes.addCurve(to: CGPoint(x: 60, y: -26), control1: CGPoint(x: -40, y: -46), control2: CGPoint(x: 10, y: 4))
    strokes.move(to: CGPoint(x: -70, y: 18))
    strokes.addCurve(to: CGPoint(x: 20, y: 14), control1: CGPoint(x: -40, y: -2), control2: CGPoint(x: -10, y: 36))
    ctx.addPath(strokes)
    ctx.strokePath()
}

// Glass thickness: stronger tint toward the left and right edges, and at the heel.
ctx.saveGState()
ctx.addPath(jar)
ctx.clip()
horizontal(gradient([hex(0x86CFC3, 0.85), hex(0x86CFC3, 0.30), hex(0x86CFC3, 0.04), hex(0x86CFC3, 0.04),
                     hex(0x86CFC3, 0.30), hex(0x86CFC3, 0.85)], [0, 0.08, 0.2, 0.8, 0.92, 1]), 332, 692)
vertical(gradient([hex(0x86CFC3, 0), hex(0x86CFC3, 0.7)], [0, 1]), 728, 772)
ctx.restoreGState()

// Highlights: a bright narrow band left, a softer one right of centre, a curve on the left shoulder.
ctx.saveGState()
ctx.addPath(jar)
ctx.clip()
ctx.setFillColor(gray(1, 0.8))
ctx.addPath(rounded(CGRect(x: 350, y: 470, width: 15, height: 250), 7.5))
ctx.fillPath()
ctx.setFillColor(gray(1, 0.32))
ctx.addPath(rounded(CGRect(x: 568, y: 450, width: 30, height: 250), 15))
ctx.fillPath()
ctx.setStrokeColor(gray(1, 0.7))
ctx.setLineWidth(11)
ctx.setLineCap(.round)
let shoulder = CGMutablePath()
shoulder.move(to: CGPoint(x: 427, y: 376))
shoulder.addCurve(to: CGPoint(x: 354, y: 446), control1: CGPoint(x: 410, y: 408), control2: CGPoint(x: 362, y: 408))
ctx.addPath(shoulder)
ctx.strokePath()
ctx.restoreGState()

// Silhouette stroke keeps the jar readable at small sizes.
ctx.addPath(jar)
ctx.setStrokeColor(hex(0x4FAFA0, 0.9))
ctx.setLineWidth(7)
ctx.setLineJoin(.round)
ctx.strokePath()

// Rim bead and three thread lines on the neck.
ctx.saveGState()
let bead = rounded(CGRect(x: 402, y: 312, width: 220, height: 20), 10)
ctx.addPath(bead)
ctx.setFillColor(hex(0xBFE6DF))
ctx.fillPath()
ctx.addPath(bead)
ctx.setStrokeColor(hex(0x4FAFA0, 0.9))
ctx.setLineWidth(5)
ctx.strokePath()
ctx.setStrokeColor(hex(0x4FAFA0, 0.8))
ctx.setLineWidth(4)
ctx.setLineCap(.round)
for y in [341, 349, 357] as [CGFloat] {
    ctx.move(to: CGPoint(x: 416, y: y))
    ctx.addLine(to: CGPoint(x: 608, y: y))
}
ctx.strokePath()
ctx.restoreGState()

// Soft blue polyethylene cap with fine ribs and a lighter top band.
let cap = rounded(CGRect(x: 396, y: 248, width: 232, height: 72), 18)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 8, color: gray(0, 0.3))
ctx.addPath(cap)
ctx.setFillColor(hex(0x76A8CE))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(cap)
ctx.clip()
vertical(gradient([hex(0xE4F2FC), hex(0x76A8CE)]), 248, 320)
ctx.setStrokeColor(hex(0x3F76A3, 0.35))
ctx.setLineWidth(3)
var x: CGFloat = 410
while x < 626 {
    ctx.move(to: CGPoint(x: x, y: 276))
    ctx.addLine(to: CGPoint(x: x, y: 320))
    x += 12
}
ctx.strokePath()
ctx.setFillColor(gray(1, 0.5))
ctx.fill(CGRect(x: 396, y: 248, width: 232, height: 26))
ctx.setFillColor(gray(1, 0.35))
ctx.addPath(rounded(CGRect(x: 408, y: 282, width: 10, height: 30), 5))
ctx.fillPath()
ctx.restoreGState()
ctx.addPath(cap)
ctx.setStrokeColor(hex(0x4F86B0, 0.9))
ctx.setLineWidth(4)
ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
