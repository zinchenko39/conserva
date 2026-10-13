import AppKit
import ConservaCore
import SpriteKit

/// Draws the jar, its swing-top lid, the label and everything that goes inside, as
/// textures. All artwork is in the jar's design units, y-down, the same box
/// as `JarGeometry`.
enum JarArt {
    /// A 5-litre jar: a thick lip with a groove under it for the wire, a short neck, sloping shoulders
    /// and a heavy rounded heel.
    static let outer = "M78 16 Q74 16 74 20 L74 26 Q74 30 78 30 L80 31 L80 44 C80 68 24 76 22 122 L22 366 C22 398 38 414 68 414 L232 414 C262 414 278 398 278 366 L278 122 C276 76 220 68 220 44 L220 31 L222 30 Q226 30 226 26 L226 20 Q226 16 222 16 Z"
    static let inner = "M88 16 L88 46 C88 74 28 82 28 124 L28 364 C28 388 44 396 70 396 L230 396 C256 396 272 388 272 364 L272 124 C272 82 212 74 212 46 L212 16 Z"

    /// The label texture has room around the paper for the tape and the tilt.
    static let labelSize = CGSize(width: 192, height: 104)

    // MARK: Glass

    /// The far side of the jar, drawn behind its contents: the faint body, the back of the lip and
    /// the neck wire, a dim reflection on the far wall, and the bottom seen through the glass: the
    /// knurled ring it stands on, the seam left by the mould's base plate, the push-up and the valve mark.
    static func back() -> SKTexture {
        texture(JarGeometry.box, scale: 2) { ctx in
            let tint = Theme.glassTint, edge = Theme.glassEdge, white = NSColor.white
            ctx.saveGState()
            ctx.addPath(path(outer)); ctx.clip()
            linear(ctx, [(edge, 0.3, 0), (tint, 0.12, 0.06), (tint, 0.035, 0.25), (tint, 0, 0.5), (tint, 0.035, 0.75),
                         (tint, 0.12, 0.94), (edge, 0.3, 1)],
                   from: CGPoint(x: 22, y: 0), to: CGPoint(x: 278, y: 0))
            ctx.restoreGState()

            stroke(ctx, path("M74 18 Q150 6 226 18"), Theme.glassLine, 1.4)
            stroke(ctx, path("M76 19.5 Q150 8 224 19.5"), white.withAlphaComponent(0.45), 0.8)
            faint(ctx, 0.3) { wire(ctx, path("M74 32 Q150 20 226 32"), gauge) }
            band(ctx, CGRect(x: 236, y: 160, width: 14, height: 210), across: [(white, 0, 0), (white, 0.5, 0.5), (white, 0, 1)],
                 along: [(0, 0), (1, 0.2), (1, 0.8), (0, 1)], alpha: 0.3)
            stroke(ctx, path("M34 388 C60 394 240 394 266 388"), Theme.glassLine.withAlphaComponent(0.15), 1)

            // The bottom, an ellipse seen a little from above; `flat` is its height over its width.
            let c = CGPoint(x: 150, y: 380), flat = viewFlatness
            func oval(_ rx: CGFloat) -> CGRect { CGRect(x: c.x - rx, y: c.y - rx * flat, width: rx * 2, height: rx * 2 * flat) }
            ctx.saveGState()
            ctx.addEllipse(in: oval(120)); ctx.clip()
            ctx.drawRadialGradient(gradient([(tint, 0.35, 0), (tint, 0, 1)]),
                                   startCenter: CGPoint(x: 150, y: 396), startRadius: 0,
                                   endCenter: CGPoint(x: 150, y: 396), endRadius: 130, options: [])
            ctx.restoreGState()
            stroke(ctx, CGPath(ellipseIn: oval(120), transform: nil), Theme.glassLine, 1)

            // The knurled ring the jar stands on: short ribs all round, so the glass does not skid.
            for rx in [CGFloat(101), 114] { stroke(ctx, CGPath(ellipseIn: oval(rx), transform: nil), Theme.glassLine, 0.8) }
            let ribs = 96
            for i in 0..<ribs {
                let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(ribs)
                let rib = CGMutablePath()
                rib.move(to: CGPoint(x: c.x + 102 * cos(t), y: c.y + 102 * flat * sin(t)))
                rib.addLine(to: CGPoint(x: c.x + 113 * cos(t), y: c.y + 113 * flat * sin(t)))
                // The near ribs catch more light than the far ones.
                let near = sin(t) > 0
                stroke(ctx, rib, i % 2 == 0 ? Theme.glassLine : white.withAlphaComponent(near ? 0.6 : 0.35), near ? 1.1 : 0.8)
            }

            // The seam where the base plate of the mould met the body mould.
            stroke(ctx, CGPath(ellipseIn: oval(88).offsetBy(dx: 0, dy: 0.7), transform: nil), white.withAlphaComponent(0.4), 0.8)
            stroke(ctx, CGPath(ellipseIn: oval(88), transform: nil), Theme.glassLine, 0.8)

            // The push-up: thick glass that gathers the light into a bright crescent at its near edge,
            // and the small round mark of the mould's valve in its middle.
            let dimple = CGPoint(x: 150, y: 382.8)
            stroke(ctx, CGPath(ellipseIn: CGRect(x: dimple.x - 66, y: dimple.y - 9.4, width: 132, height: 18.8), transform: nil), Theme.glassLine, 1)
            stroke(ctx, ellipseArc(center: dimple, rx: 66, ry: 9.4, from: .pi - 0.3, to: 0.3), white.withAlphaComponent(0.75), 1.6, round: true)
            stroke(ctx, ellipseArc(center: dimple, rx: 66, ry: 9.4, from: .pi + 0.4, to: 2 * .pi - 0.4), Theme.glassThick.withAlphaComponent(0.45), 1.4, round: true)
            let valve = CGRect(x: c.x - 9, y: c.y + 0.8, width: 18, height: 3.2)
            stroke(ctx, CGPath(ellipseIn: valve.offsetBy(dx: 0, dy: 0.6), transform: nil), white.withAlphaComponent(0.5), 0.9)
            stroke(ctx, CGPath(ellipseIn: valve, transform: nil), Theme.glassLine, 0.9)
        }
    }

    /// The near side, drawn over the contents. Clear glass shows by how it handles light: paired lines
    /// along the silhouette (a dark one that reads on a light desktop, a bright one inside it that reads
    /// on a dark one), a window reflected on the left, thick glass at the heel and the lip acting as
    /// lenses, the mould's seam, the wire round the neck.
    static func front() -> SKTexture {
        texture(JarGeometry.box, scale: 2) { ctx in
            let tint = Theme.glassTint, edge = Theme.glassEdge, thick = Theme.glassThick
            let white = NSColor.white

            ctx.saveGState()
            let ring = CGMutablePath(); ring.addPath(path(outer)); ring.addPath(path(inner))
            ctx.addPath(ring); ctx.clip(using: .evenOdd)
            linear(ctx, [(thick, 0.9, 0), (edge, 0.6, 0.025), (tint, 0.35, 0.1), (tint, 0.2, 0.5), (tint, 0.35, 0.9),
                         (edge, 0.6, 0.975), (thick, 0.9, 1)],
                   from: CGPoint(x: 22, y: 0), to: CGPoint(x: 278, y: 0))
            ctx.restoreGState()

            // Through both walls near the sides: a little tint, and the sheen of glass seen at a slant.
            ctx.saveGState()
            ctx.addPath(path(inner)); ctx.clip()
            let across = (from: CGPoint(x: 28, y: 0), to: CGPoint(x: 272, y: 0))
            linear(ctx, [(edge, 0.26, 0), (tint, 0.06, 0.07), (tint, 0, 0.15), (tint, 0, 0.85), (tint, 0.06, 0.93), (edge, 0.26, 1)],
                   from: across.from, to: across.to)
            linear(ctx, [(white, 0.24, 0), (white, 0.06, 0.05), (white, 0, 0.12), (white, 0, 0.88), (white, 0.05, 0.95), (white, 0.16, 1)],
                   from: across.from, to: across.to)
            ctx.restoreGState()

            // The heel: the thickest glass, banded like a lens, with the knurling showing through it.
            fill(ctx, path("M28 364 C28 388 44 396 70 396 L230 396 C256 396 272 388 272 364 L278 366 C278 398 262 414 232 414 L68 414 C38 414 22 398 22 366 Z"),
                 [(tint, 0.08, 0), (edge, 0.3, 0.4), (thick, 0.7, 0.75), (edge, 0.55, 1)],
                 from: CGPoint(x: 0, y: 360), to: CGPoint(x: 0, y: 414))
            stroke(ctx, path("M40 398 C80 404 220 404 260 398"), white.withAlphaComponent(0.8), 1.2)
            stroke(ctx, path("M50 404.5 C90 409 210 409 250 404.5"), Theme.glassLine.withAlphaComponent(0.22), 1)
            ctx.saveGState()
            ctx.setLineDash(phase: 0, lengths: [1, 2.2])
            stroke(ctx, path("M58 410 C100 413 200 413 242 410"), white.withAlphaComponent(0.25), 1.2)
            ctx.restoreGState()

            // The silhouette: strokes of falling width, clipped to the jar, leave a bright line just inside
            // the edge and a band of wall seen edge-on behind it.
            ctx.saveGState()
            ctx.addPath(path(outer)); ctx.clip()
            stroke(ctx, path(outer), thick.withAlphaComponent(0.5), 7)
            stroke(ctx, path(outer), white.withAlphaComponent(0.8), 3)
            ctx.restoreGState()
            band(ctx, CGRect(x: 28, y: 130, width: 1, height: 236), across: [(white, 1, 0), (white, 1, 1)], along: streak, alpha: 0.45)
            band(ctx, CGRect(x: 271, y: 130, width: 1, height: 236), across: [(white, 1, 0), (white, 1, 1)], along: streak, alpha: 0.3)

            // Where the shoulder turns into the body the light softens; no line, the glass is one piece.
            softEllipse(ctx, CGRect(x: 22, y: 96, width: 80, height: 32), white, 0.16)

            // The mould's seam: clear at the neck, almost gone on the body.
            gradientStroke(ctx, path("M132 31 L132 46 C130 66 120 84 112 124 L112 405"), 0.6,
                           [(white, 0.4, 0), (white, 0.12, 0.25), (white, 0.04, 0.6), (white, 0.14, 1)],
                           from: CGPoint(x: 0, y: 30), to: CGPoint(x: 0, y: 400))


            for seed in [CGRect(x: 65.2, y: 154.4, width: 1.6, height: 3.2), CGRect(x: 242, y: 336.1, width: 2, height: 3.8)] {
                ctx.setFillColor(white.withAlphaComponent(0.35).cgColor); ctx.fillEllipse(in: seed)
                stroke(ctx, CGPath(ellipseIn: seed, transform: nil), thick.withAlphaComponent(0.6), 0.4)
            }

            // A window on the left, split by its mullion, sharp on the side towards the edge; beside it the
            // reflection from the inside of the wall; on the right the room, dim, and a rim of light.
            let fade: [(CGFloat, CGFloat)] = [(0, 0.05), (1, 0.17), (1, 0.44), (0.4, 0.49), (1, 0.54), (1, 0.86), (0, 1)]
            band(ctx, CGRect(x: 37, y: 126, width: 12, height: 250), across: [(white, 0, 0), (white, 0.95, 0.1), (white, 0.75, 0.45), (white, 0, 1)],
                 along: fade, alpha: 0.9)
            band(ctx, CGRect(x: 33, y: 140, width: 2, height: 220), across: [(white, 1, 0), (white, 1, 1)], along: fade, alpha: 0.25)
            band(ctx, CGRect(x: 54.5, y: 176, width: 1.6, height: 150), across: [(white, 1, 0), (white, 1, 1)], along: streak, alpha: 0.55)
            band(ctx, CGRect(x: 196, y: 150, width: 44, height: 224), across: [(white, 0, 0), (white, 0.5, 0.5), (white, 0, 1)],
                 along: [(0, 0), (1, 0.2), (1, 0.8), (0, 1)], alpha: 0.22)
            band(ctx, CGRect(x: 261, y: 146, width: 2.2, height: 222), across: [(white, 1, 0), (white, 1, 1)], along: streak, alpha: 0.4)
            let shoulder = path("M33 114 C38 88 66 78 84 58")
            stroke(ctx, shoulder, white.withAlphaComponent(0.08), 7, round: true)
            stroke(ctx, shoulder, white.withAlphaComponent(0.12), 4.5, round: true)
            stroke(ctx, shoulder, white.withAlphaComponent(0.85), 2.6, round: true)
            stroke(ctx, path("M267 112 C261 87 232 77 216 63"), white.withAlphaComponent(0.3), 2, round: true)
            stroke(ctx, path("M29 368 C31 384 40 393 56 399"), white.withAlphaComponent(0.75), 2.2, round: true)
            stroke(ctx, path("M271 370 C269 384 261 392 248 397"), white.withAlphaComponent(0.3), 1.4, round: true)
            stroke(ctx, path("M85 35 L85 47"), white.withAlphaComponent(0.65), 1.8, round: true)
            stroke(ctx, path("M215 36 L215 46"), white.withAlphaComponent(0.3), 1.2, round: true)

            // The mouth, and the lip: a bead of glass that works as a ring-shaped lens, bright on top, dark in
            // its core, with light gathered on its inner side; the groove under it the wire sits in.
            ctx.setFillColor(tint.withAlphaComponent(0.22).cgColor)
            ctx.fillEllipse(in: CGRect(x: 74, y: 8, width: 152, height: 16))
            stroke(ctx, CGPath(ellipseIn: CGRect(x: 88, y: 10.5, width: 124, height: 12), transform: nil), thick.withAlphaComponent(0.6), 1)
            stroke(ctx, CGPath(ellipseIn: CGRect(x: 89, y: 11.6, width: 122, height: 11.2), transform: nil), white.withAlphaComponent(0.45), 0.6)
            fill(ctx, path("M74 18 L74 28 Q150 40 226 28 L226 18 Q150 30 74 18 Z"),
                 [(white, 0.9, 0), (tint, 0.35, 0.3), (thick, 0.72, 0.52), (white, 0.55, 0.72), (thick, 0.85, 1)],
                 from: CGPoint(x: 0, y: 16), to: CGPoint(x: 0, y: 38))
            stroke(ctx, path("M75 22.5 Q150 33.5 225 22.5"), white.withAlphaComponent(0.8), 1.2)
            stroke(ctx, path("M76 26.5 Q150 37.5 224 26.5"), white.withAlphaComponent(0.35), 0.7)
            stroke(ctx, path("M80 31.5 Q150 43 220 31.5"), Theme.glassLine.withAlphaComponent(0.4), 1.1)
            stroke(ctx, path("M81 33.2 Q150 44.7 219 33.2"), white.withAlphaComponent(0.4), 0.7)
            stroke(ctx, CGPath(ellipseIn: CGRect(x: 74, y: 7, width: 152, height: 16), transform: nil), white.withAlphaComponent(0.9), 1.5)
            stroke(ctx, path("M92 9.6 Q118 7.4 140 7.1"), white, 1.4, round: true)

            // The wire round the neck. It rises on the left into the upright eye the lid's eye is
            // threaded through (its near half is `hingeFront`), and ends on the right in the eye the lever turns in.
            let hinge = JarGeometry.lidHinge, pivot = JarGeometry.leverPivot
            wire(ctx, path("M74 32 Q150 46 226 32"), gauge * 1.1)
            wire(ctx, path("M74 32 L70.6 23.8 L68.4 19.4"), gauge)
            wire(ctx, ellipseArc(center: hinge, rx: hingeEye.width, ry: hingeEye.height, from: .pi / 2, to: 1.5 * .pi), gauge * 0.9)
            wire(ctx, path("M226 32 Q230 31 232.2 29.6"), gauge)
            wire(ctx, CGPath(ellipseIn: CGRect(x: pivot.x - 4, y: pivot.y - 4, width: 8, height: 8), transform: nil), gauge * 0.9)
            // Where the wire is twisted shut.
            stroke(ctx, path("M71.6 28.6 L75.2 26.8 M72.6 31 L76.2 29.2"), Theme.wireDark, 1, round: true)

            stroke(ctx, path(outer), Theme.glassOutline, 2)

            glint(ctx, at: CGPoint(x: 97, y: 9), size: 1)
            glint(ctx, at: CGPoint(x: 33, y: 384), size: 0.8)
            glint(ctx, at: CGPoint(x: 44, y: 150), size: 0.7)
        }
    }

    /// How a long highlight fades along its length: never one even stroke, which reads as a painted stripe.
    private static let streak: [(CGFloat, CGFloat)] = [(0, 0), (0.9, 0.22), (0.45, 0.5), (0.85, 0.74), (0, 1)]

    /// The jar's outline in the accent colour, shown while something is dragged over it.
    static func dropOutline() -> SKTexture {
        texture(JarGeometry.box, scale: 2) { ctx in
            stroke(ctx, path(outer), Theme.dropTarget.withAlphaComponent(0.9), 4)
        }
    }

    /// Zinc wire, thick enough to read at the jar's size on screen.
    static let gauge: CGFloat = 4
    /// Half-width and half-height of the upright eye on the neck wire that the lid hangs from.
    static let hingeEye = CGSize(width: 3, height: 5.2)

    /// The swing-top lid as on a real jar, drawn around the hinge so the sprite can swing on it:
    /// a thick glass disc with a beaded rim on its orange rubber ring, and a wire that runs round
    /// its edge, comes out in front as a loop for the lever to catch, and ends in an eye at the hinge.
    /// Ellipses are the lid seen a little from above, like the jar's rim.
    static func lid() -> SKTexture {
        let r = JarGeometry.lidRect
        return texture(r.size, scale: 2.5) { ctx in
            ctx.translateBy(x: -r.minX, y: -r.minY)
            let tint = Theme.glassTint, white = NSColor.white
            let cx: CGFloat = 82
            func front(_ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
                ellipseArc(center: CGPoint(x: cx, y: y), rx: rx, ry: ry, from: .pi, to: 0)
            }

            // The rubber ring, squeezed out a little at the sides, with its pull tab in front.
            let ring = CGMutablePath()
            ring.move(to: CGPoint(x: 6, y: -4))
            ring.addPath(front(1, 76, 3.5))
            ring.addLine(to: CGPoint(x: 158, y: -4))
            ring.closeSubpath()
            fill(ctx, ring, [(Theme.gasketLight, 1, 0), (Theme.gasket, 1, 0.45), (Theme.gasketShade, 1, 1)],
                 from: CGPoint(x: 0, y: -4), to: CGPoint(x: 0, y: 5))
            stroke(ctx, front(-2.6, 75, 3.5), Theme.gasketSheen.withAlphaComponent(0.7), 0.6)
            ctx.setFillColor(Theme.gasket.cgColor)
            ctx.fillEllipse(in: CGRect(x: 3.4, y: -4.3, width: 5.2, height: 6.2))
            ctx.fillEllipse(in: CGRect(x: 155.4, y: -4.3, width: 5.2, height: 6.2))
            stroke(ctx, front(1.8, 75, 3.5), Theme.gasketEdge, 1)
            fill(ctx, path("M68 2.6 Q82 4.4 100 2.8 L102 8.6 Q86 10.8 66.4 9 Z"), [(Theme.gasket, 1, 0), (Theme.gasketShade, 1, 1)],
                 from: CGPoint(x: 0, y: 2), to: CGPoint(x: 0, y: 10))
            stroke(ctx, path("M69 4 Q84 5.6 100 4.2"), Theme.gasketSheen.withAlphaComponent(0.6), 0.5)
            stroke(ctx, path("M68.6 8 Q86 9.8 101.2 7.8"), Theme.gasketEdge, 0.7)

            // The far half of the wire, seen through the glass.
            faint(ctx, 0.5) { wire(ctx, ellipseArc(center: CGPoint(x: cx, y: -8.5), rx: 78.5, ry: 3.5, from: .pi, to: 2 * .pi), gauge) }

            // The lug the wire's eye goes through.
            let lug = path("M6 -11 L-1 -7.5 Q-5 -5 -3.4 -1.4 Q-1.6 2 2.6 0 L6 -3 Z")
            ctx.addPath(lug); ctx.setFillColor(tint.withAlphaComponent(0.6).cgColor); ctx.fillPath()
            stroke(ctx, lug, Theme.glassOutline, 0.9)

            // The disc: its edge, darker where the light goes through more glass, and its top.
            let edge = CGMutablePath()
            edge.move(to: CGPoint(x: 4, y: -13.5))
            edge.addPath(front(-4, 78, 3.5))
            edge.addLine(to: CGPoint(x: 160, y: -13.5))
            edge.addPath(ellipseArc(center: CGPoint(x: cx, y: -13.5), rx: 78, ry: 3.5, from: 0, to: .pi))
            edge.closeSubpath()
            fill(ctx, edge, [(Theme.glassThick, 0.85, 0), (Theme.glassEdge, 0.5, 0.12), (tint, 0.3, 0.5), (Theme.glassEdge, 0.5, 0.88), (Theme.glassThick, 0.85, 1)],
                 from: CGPoint(x: 4, y: 0), to: CGPoint(x: 160, y: 0))
            let top = CGPath(ellipseIn: CGRect(x: cx - 78, y: -17, width: 156, height: 7), transform: nil)
            fill(ctx, top, [(tint, 0.45, 0), (tint, 0.1, 0.5), (tint, 0.45, 1)], from: CGPoint(x: 4, y: 0), to: CGPoint(x: 160, y: 0))
            fill(ctx, top, [(white, 0.75, 0), (white, 0, 1)], from: CGPoint(x: 0, y: -24), to: CGPoint(x: 0, y: -10))

            // The shallow recess inside the bead, the light caught by the edge, and the knurling on the bead.
            stroke(ctx, CGPath(ellipseIn: CGRect(x: cx - 66, y: -15.9, width: 132, height: 5.4), transform: nil), Theme.glassLine, 0.8)
            stroke(ctx, front(-12.5, 66, 2.7), white.withAlphaComponent(0.6), 0.7)
            stroke(ctx, front(-5.4, 73, 3.1), white.withAlphaComponent(0.55), 0.9)
            stroke(ctx, front(-13.5, 78, 3.5), white.withAlphaComponent(0.85), 1.1)
            stroke(ctx, path("M12 -15.6 Q30 -16.8 54 -16.9"), white.withAlphaComponent(0.9), 1.3, round: true)
            let ticks = 58
            for i in 0...ticks {
                let t = CGFloat.pi * (0.06 + 0.88 * CGFloat(i) / CGFloat(ticks))
                let x = cx - 77 * cos(t), y = -13.5 + 3.4 * sin(t)
                let tick = CGMutablePath()
                tick.move(to: CGPoint(x: x, y: y)); tick.addLine(to: CGPoint(x: x, y: y - 1.3))
                stroke(ctx, tick, i % 2 == 0 ? Theme.glassLine : white.withAlphaComponent(0.55), 0.55)
            }
            let outline = CGMutablePath()
            outline.move(to: CGPoint(x: 4, y: -13.5))
            outline.addPath(ellipseArc(center: CGPoint(x: cx, y: -13.5), rx: 78, ry: 3.5, from: .pi, to: 2 * .pi))
            outline.addLine(to: CGPoint(x: 160, y: -4))
            outline.addPath(ellipseArc(center: CGPoint(x: cx, y: -4), rx: 78, ry: 3.5, from: 0, to: .pi))
            outline.closeSubpath()
            stroke(ctx, outline, Theme.glassOutline, 1.5)
            stroke(ctx, outline, white.withAlphaComponent(0.5), 0.7)

            // The near half of the wire, the loop in front, the leg down to the hinge and the eye.
            wire(ctx, ellipseArc(center: CGPoint(x: cx, y: -8.5), rx: 78.5, ry: 3.5, from: .pi, to: 0), gauge)
            wire(ctx, path("M154 -7.1 Q166 -7.6 169.6 -2.4 L172.6 5.4 Q173.8 9.6 170 9.6 Q166.4 9.6 165.8 5.6 L164.6 -1.4"), gauge * 0.9)
            wire(ctx, path("M3.5 -8.5 Q1.2 -7 0.6 -3.4"), gauge)
            wire(ctx, CGPath(ellipseIn: CGRect(x: -5.2, y: -3, width: 10.4, height: 6), transform: nil), gauge * 0.85)
            glint(ctx, at: CGPoint(x: 22, y: -16.4), size: 0.8)
        }
    }

    /// Where the hinge sits in the lid texture, as a sprite anchor point.
    static var lidAnchor: CGPoint {
        let r = JarGeometry.lidRect
        return CGPoint(x: -r.minX / r.width, y: 1 + r.minY / r.height)
    }

    static let hingeSize = CGSize(width: 16, height: 20)

    /// The near half of the neck wire's upright eye, drawn over the lid so the lid's eye looks threaded through it.
    static func hingeFront() -> SKTexture {
        texture(hingeSize, scale: 2.5) { ctx in
            ctx.translateBy(x: hingeSize.width / 2, y: hingeSize.height / 2)
            wire(ctx, ellipseArc(center: .zero, rx: hingeEye.width, ry: hingeEye.height, from: -.pi / 2, to: .pi / 2), gauge * 0.9)
        }
    }

    static let leverSize = CGSize(width: 22, height: 70)
    /// From the top of the lever texture down to its pivot: the hook stands up above it.
    private static let leverPivotDepth: CGFloat = 14

    /// The lever: a wire bail hanging from its eye on the neck wire, both sides of it showing,
    /// with a hook above the eye that holds the lid wire's loop down.
    static func lever() -> SKTexture {
        texture(leverSize, scale: 2.5) { ctx in
            ctx.translateBy(x: leverSize.width / 2, y: leverPivotDepth)
            faint(ctx, 0.55) { wire(ctx, path("M-1.6 0 L-3 46"), gauge * 0.85) }
            wire(ctx, path("M1.6 0 L3.2 46 Q2.8 51.4 -0.4 50.8 Q-3.4 50.2 -3 46"), gauge)
            wire(ctx, path("M0 0 Q-3 -4 -1.2 -8 Q1 -11 4.2 -8.4 L3.4 -6"), gauge)
            wire(ctx, CGPath(ellipseIn: CGRect(x: -3.8, y: -3.8, width: 7.6, height: 7.6), transform: nil), gauge * 0.8)
        }
    }

    /// The lever's pivot in its texture, as a sprite anchor point.
    static var leverAnchor: CGPoint { CGPoint(x: 0.5, y: 1 - leverPivotDepth / leverSize.height) }

    /// Polished steel wire drawn as a tube: a dark rim, a light body, the darker reflection along its
    /// middle a little below, and the shine a little above, towards the light.
    static func wire(_ ctx: CGContext, _ p: CGPath, _ width: CGFloat) {
        ctx.setLineJoin(.round)
        stroke(ctx, p, Theme.wireDark, width + 0.8, round: true)
        stroke(ctx, p, Theme.wire, width, round: true)
        ctx.saveGState()
        ctx.translateBy(x: 0.5, y: 0.6)
        stroke(ctx, p, Theme.wireCore, width * 0.4, round: true)
        ctx.translateBy(x: -1.1, y: -1.3)
        stroke(ctx, p, .white, max(0.6, width * 0.2), round: true)
        ctx.restoreGState()
    }

    /// A paper label written by hand, wrapped round the glass: its torn top and bottom edges and the
    /// writing follow the body's curve, and its sides turn away into shade.
    static func label(name: String, count: String) -> SKTexture {
        texture(labelSize, scale: 2.5) { ctx in
            let paper = CGRect(x: 8, y: 12, width: 176, height: 84)
            let jag: [(CGFloat, CGFloat)] = [(0, 0.02), (0.08, 0), (0.2, 0.02), (0.35, 0), (0.5, 0.015), (0.66, 0), (0.82, 0.02),
                                             (0.92, 0), (1, 0.02), (0.99, 0.34), (1, 0.66), (0.99, 0.98), (0.86, 1), (0.7, 0.98),
                                             (0.52, 1), (0.34, 0.98), (0.17, 1), (0, 0.98), (0.01, 0.64), (0, 0.32)]
            let shape = CGMutablePath()
            for (i, p) in jag.enumerated() {
                let x = paper.minX + p.0 * paper.width
                let pt = CGPoint(x: x, y: paper.minY + p.1 * paper.height + bow(x - paper.midX))
                if i == 0 { shape.move(to: pt) } else { shape.addLine(to: pt) }
            }
            shape.closeSubpath()
            ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 2, color: NSColor.black.withAlphaComponent(0.18).cgColor)
            ctx.addPath(shape); ctx.setFillColor(Theme.labelPaper.cgColor); ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.saveGState()
            ctx.addPath(shape); ctx.clip()
            linear(ctx, [(.black, 0.13, 0), (.black, 0, 0.16), (.black, 0, 0.84), (.black, 0.15, 1)],
                   from: CGPoint(x: paper.minX, y: 0), to: CGPoint(x: paper.maxX, y: 0))
            ctx.restoreGState()
            ctx.addPath(shape); ctx.setStrokeColor(Theme.labelEdge.cgColor); ctx.setLineWidth(0.8); ctx.strokePath()

            ctx.saveGState()
            ctx.translateBy(x: paper.midX, y: 12)
            ctx.rotate(by: 4 * .pi / 180)
            ctx.setFillColor(Theme.tape.cgColor)
            ctx.fill(CGRect(x: -23, y: -7, width: 46, height: 14))
            ctx.restoreGState()

            let room = paper.width - 16
            var size: CGFloat = 33
            var font = Theme.hand(size)
            func width(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: font]).width }
            while size > 17, width(name) > room {
                size -= 1; font = Theme.hand(size)
            }
            var shown = name
            if width(shown) > room {
                while shown.count > 1, width(shown + "…") > room { shown.removeLast() }
                shown += "…"
            }
            curved(ctx, shown, font: font, color: Theme.ink, center: CGPoint(x: paper.midX, y: paper.midY - 7))
            curved(ctx, count, font: Theme.hand(20, bold: false), color: Theme.ink, center: CGPoint(x: paper.midX, y: paper.midY + 22))
        }
    }

    /// The jar's round sections seen a little from above: their height over their width, as in the bottom's ellipse.
    static let viewFlatness: CGFloat = 17.0 / 120

    /// How far a point on the body `dx` from its middle rises above the middle, seen from a little above.
    private static func bow(_ dx: CGFloat) -> CGFloat {
        let r: CGFloat = 128
        return r * viewFlatness * (sqrt(max(0, 1 - (dx / r) * (dx / r))) - 1)
    }

    /// One line centred on `center.x`, its baseline through `center` and following the body's bow
    /// out to both sides, each letter turned to the curve.
    private static func curved(_ ctx: CGContext, _ text: String, font: NSFont, color: NSColor, center: CGPoint) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        ctx.saveGState()
        ctx.setFillColor(color.cgColor)
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let n = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: n)
            var positions = [CGPoint](repeating: .zero, count: n)
            var advances = [CGSize](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            CTRunGetPositions(run, CFRange(), &positions)
            CTRunGetAdvances(run, CFRange(), &advances)
            // A letter Caveat lacks comes from a fallback font, named in the run.
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName as String].map { $0 as! CTFont } ?? (font as CTFont)
            for i in 0..<n {
                let dx = positions[i].x + advances[i].width / 2 - width / 2
                let slope = (bow(dx + 1) - bow(dx - 1)) / 2
                ctx.saveGState()
                ctx.translateBy(x: center.x + dx, y: center.y + bow(dx))
                ctx.rotate(by: atan(slope))
                ctx.scaleBy(x: 1, y: -1)
                var origin = CGPoint(x: -advances[i].width / 2, y: positions[i].y)
                CTFontDrawGlyphs(runFont, &glyphs[i], &origin, 1, ctx)
                ctx.restoreGState()
            }
        }
        ctx.restoreGState()
    }

    // MARK: Contents

    struct Look {
        var kind: ItemKind
        var title: String
        var host: String?
        var fileExtension: String?
        var thumbnail: CGImage?
        var aged: Double
        /// For a link: what it leads to, the site's icon, a video's still, a repository's `owner/repo`.
        var link: LinkKind? = nil
        var icon: CGImage? = nil
        var preview: CGImage? = nil
        var repository: String? = nil
    }

    /// Everything is drawn at this many pixels per design unit: enough to stay sharp on a
    /// Retina screen while a hovered thing is shown at `ShelfScene.hoverScale`.
    private static let thingScale: CGFloat = 3.5

    static func thing(_ look: Look) -> SKTexture {
        switch look.kind {
        case .link: return link(look)
        case .text: return note(look)
        case .file: return folder(look)
        case .image: return photo(look)
        }
    }

    /// A link, drawn as what it leads to.
    private static func link(_ look: Look) -> SKTexture {
        switch look.link ?? .page {
        case .video: return video(look)
        case .post: return post(look)
        case .article: return clipping(look)
        case .code: return codeCard(look)
        case .audio: return cassette(look)
        case .place: return mapPiece(look)
        case .product: return priceTag(look)
        case .document: return document(look)
        case .page: return tag(look)
        }
    }

    /// Draws a thing laid out in `design` units, scaled to the size it has in the jar. The shapes were
    /// worked out at those sizes and are only ever shrunk a little.
    private static func designed(_ link: LinkKind, _ design: CGSize, _ body: @escaping (CGContext) -> Void) -> SKTexture {
        let size = JarGeometry.size(of: link)
        return texture(size, scale: thingScale) { ctx in
            ctx.scaleBy(x: size.width / design.width, y: size.height / design.height)
            body(ctx)
        }
    }

    /// The site's own icon, or its initial on its colour until the icon arrives.
    private static func siteIcon(_ ctx: CGContext, _ r: CGRect, _ look: Look, round: Bool = false) {
        let shape = round ? CGPath(ellipseIn: r, transform: nil)
            : CGPath(roundedRect: r, cornerWidth: r.width * 0.22, cornerHeight: r.width * 0.22, transform: nil)
        if let icon = look.icon {
            ctx.saveGState()
            ctx.addPath(shape); ctx.clip()
            ctx.setFillColor(Theme.page.cgColor); ctx.fill(r)
            drawImage(ctx, icon, aspectFill: r)
            ctx.restoreGState()
            return
        }
        ctx.addPath(shape); ctx.setFillColor(siteColor(look).cgColor); ctx.fillPath()
        let letter = String((look.host ?? "?").prefix(1)).uppercased()
        withAppKit(ctx) {
            draw(letter, in: CGRect(x: r.minX, y: r.minY + r.height * 0.1, width: r.width, height: r.height),
                 font: Theme.ui(r.height * 0.66, .bold), color: .white, align: .center)
        }
    }

    private static func siteColor(_ look: Look) -> NSColor { Theme.site(look.host ?? "?", icon: look.icon) }

    /// A video: a still in a paper frame, with a play button, and the title under it.
    static func video(_ look: Look) -> SKTexture {
        designed(.video, CGSize(width: 104, height: 74)) { ctx in
            let frame = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 104, height: 74), cornerWidth: 3, cornerHeight: 3, transform: nil)
            ctx.addPath(frame); ctx.setFillColor(Theme.videoFrame.cgColor); ctx.fillPath()
            let picture = CGRect(x: 3, y: 3, width: 98, height: 55)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: picture, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)); ctx.clip()
            if let still = look.preview {
                drawImage(ctx, still, aspectFill: picture)
            } else {
                linear(ctx, [(Theme.videoEmptyTop, 1, 0), (Theme.videoEmptyBottom, 1, 1)], from: CGPoint(x: 0, y: 3), to: CGPoint(x: 0, y: 58))
            }
            ctx.restoreGState()
            ctx.setFillColor(Theme.playDisc.cgColor); ctx.fillEllipse(in: CGRect(x: 42, y: 20.5, width: 20, height: 20))
            ctx.addPath(path("M48.6 25.2 L58 30.5 L48.6 35.8 Z")); ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
            age(ctx, frame, look.aged)
            stroke(ctx, frame, Theme.thingEdge, 0.6)
            siteIcon(ctx, CGRect(x: 6, y: 61, width: 9, height: 9), look)
            withAppKit(ctx) {
                draw(look.title, in: CGRect(x: 18, y: 60.5, width: 82, height: 11), font: Theme.ui(7.2, .semibold), color: Theme.tagText, align: .left)
            }
        }
    }

    /// A post: a card with the site's icon for an avatar and the start of the text.
    static func post(_ look: Look) -> SKTexture {
        designed(.post, CGSize(width: 112, height: 48)) { ctx in
            let card = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 112, height: 48), cornerWidth: 4, cornerHeight: 4, transform: nil)
            ctx.addPath(card); ctx.setFillColor(Theme.postCard.cgColor); ctx.fillPath()
            siteIcon(ctx, CGRect(x: 4.5, y: 4.5, width: 13, height: 13), look, round: true)
            withAppKit(ctx) {
                draw(look.host ?? "", in: CGRect(x: 21, y: 6.5, width: 86, height: 9), font: Theme.ui(6.6, .bold), color: Theme.tagText, align: .left)
                drawCentered(look.title, in: CGRect(x: 7, y: 19.5, width: 99, height: 18), font: Theme.ui(6.8), color: Theme.tagText, lines: 2, lineHeight: 8)
            }
            stroke(ctx, path("M7 42.6 L25 42.6 M30 42.6 L44 42.6"), Theme.postBar, 1.2, round: true)
            age(ctx, card, look.aged)
            stroke(ctx, card, Theme.thingEdge, 0.6)
        }
    }

    /// An article: a clipping cut from a newspaper with pinking shears, its headline in a serif.
    static func clipping(_ look: Look) -> SKTexture {
        designed(.article, CGSize(width: 116, height: 44)) { ctx in
            let w: CGFloat = 116, h: CGFloat = 44
            let shape = CGMutablePath()
            shape.move(to: CGPoint(x: 0, y: 1.4))
            for x in stride(from: CGFloat(3), through: w, by: 3) { shape.addLine(to: CGPoint(x: x, y: Int(x / 3) % 2 == 1 ? 0 : 1.4)) }
            for x in stride(from: CGFloat(3), through: w, by: 3) { shape.addLine(to: CGPoint(x: w - x, y: h - (Int(x / 3) % 2 == 1 ? 0 : 1.4))) }
            shape.closeSubpath()
            ctx.addPath(shape); ctx.setFillColor(Theme.newsprint.cgColor); ctx.fillPath()
            withAppKit(ctx) {
                let caps = NSAttributedString(string: (look.host ?? "").uppercased(), attributes: [
                    .font: Theme.ui(4.8, .bold), .foregroundColor: Theme.newsMeta, .kern: 0.8, .paragraphStyle: truncating(.left)])
                caps.draw(with: CGRect(x: 6, y: 4, width: 104, height: 7), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
                drawCentered(look.title, in: CGRect(x: 6, y: 12, width: 104, height: 19), font: Theme.serif(8.6), color: Theme.newsInk, lines: 2, lineHeight: 9)
            }
            stroke(ctx, path("M6 11.2 L110 11.2"), Theme.newsInk, 0.5)
            stroke(ctx, path("M6 34 L52 34 M6 37.4 L50 37.4 M6 40.8 L46 40.8 M58 34 L110 34 M58 37.4 L108 37.4 M58 40.8 L96 40.8"), Theme.newsColumns, 1.3)
            age(ctx, shape, look.aged)
            stroke(ctx, shape, Theme.thingEdge, 0.6)
        }
    }

    /// Code: a card of squared paper with the repository's name in a monospaced line.
    static func codeCard(_ look: Look) -> SKTexture {
        designed(.code, CGSize(width: 116, height: 40)) { ctx in
            let card = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 116, height: 40), cornerWidth: 2, cornerHeight: 2, transform: nil)
            ctx.addPath(card); ctx.setFillColor(Theme.graphPaper.cgColor); ctx.fillPath()
            let grid = CGMutablePath()
            for x in stride(from: CGFloat(4), to: 116, by: 4) { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: 40)) }
            for y in stride(from: CGFloat(4), to: 40, by: 4) { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: 116, y: y)) }
            stroke(ctx, grid, Theme.graphGrid, 0.35)
            siteIcon(ctx, CGRect(x: 6, y: 6, width: 10, height: 10), look)
            withAppKit(ctx) {
                draw(look.host ?? "", in: CGRect(x: 20, y: 7, width: 90, height: 8), font: Theme.ui(5.6), color: Theme.codeMeta, align: .left)
                draw(look.repository ?? look.title, in: CGRect(x: 6, y: 19, width: 104, height: 11), font: Theme.mono(8, .semibold), color: Theme.codeInk, align: .left)
                if look.repository != nil {
                    draw(look.title, in: CGRect(x: 6, y: 30, width: 104, height: 8), font: Theme.ui(5.4), color: Theme.codeMeta, align: .left)
                }
            }
            age(ctx, card, look.aged)
            stroke(ctx, card, Theme.thingEdge, 0.6)
        }
    }

    /// Music or a podcast: a cassette, its label in the site's colour and written on by hand.
    static func cassette(_ look: Look) -> SKTexture {
        designed(.audio, CGSize(width: 100, height: 62)) { ctx in
            let body = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 100, height: 62), cornerWidth: 4, cornerHeight: 4, transform: nil)
            ctx.addPath(body); ctx.setFillColor(Theme.cassetteBody.cgColor); ctx.fillPath()
            stroke(ctx, CGPath(roundedRect: CGRect(x: 3, y: 3, width: 94, height: 56), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil), Theme.cassetteRim, 0.8)
            let label = CGPath(roundedRect: CGRect(x: 7, y: 6, width: 86, height: 27), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            ctx.addPath(label); ctx.setFillColor(Theme.cassetteLabel.cgColor); ctx.fillPath()
            ctx.saveGState()
            ctx.addPath(label); ctx.clip()
            ctx.setFillColor(siteColor(look).cgColor); ctx.fill(CGRect(x: 7, y: 6, width: 86, height: 6))
            ctx.restoreGState()
            age(ctx, label, look.aged)
            withAppKit(ctx) {
                draw((look.host ?? "").uppercased(), in: CGRect(x: 11, y: 6.6, width: 78, height: 6), font: Theme.ui(4.4, .bold), color: .white, align: .left)
                draw(look.title, in: CGRect(x: 10, y: 14, width: 80, height: 15), font: Theme.hand(10.5), color: Theme.ink, align: .center)
            }
            ctx.addPath(path("M24 37 L76 37 L72 50 L28 50 Z")); ctx.setFillColor(Theme.cassetteWindow.cgColor); ctx.fillPath()
            for cx in [CGFloat(34), 66] {
                ctx.setFillColor(Theme.cassetteLabel.cgColor); ctx.fillEllipse(in: CGRect(x: cx - 5.4, y: 38.6, width: 10.8, height: 10.8))
                ctx.setFillColor(Theme.cassetteWindow.cgColor); ctx.fillEllipse(in: CGRect(x: cx - 2.2, y: 41.8, width: 4.4, height: 4.4))
                let teeth = CGMutablePath()
                for k in 0..<6 {
                    let a = CGFloat(k) * .pi / 3
                    teeth.move(to: CGPoint(x: cx + 2.6 * sin(a), y: 44 - 2.6 * cos(a)))
                    teeth.addLine(to: CGPoint(x: cx + 4.6 * sin(a), y: 44 - 4.6 * cos(a)))
                }
                stroke(ctx, teeth, Theme.cassetteLabel, 1.1)
            }
            ctx.setFillColor(Theme.cassetteTape.cgColor); ctx.fill(CGRect(x: 40, y: 40, width: 20, height: 8))
            ctx.addPath(path("M18 62 L22 54 L78 54 L82 62 Z")); ctx.setFillColor(Theme.cassetteFoot.cgColor); ctx.fillPath()
            stroke(ctx, body, Theme.thingEdge, 0.6)
        }
    }

    /// A place: a piece of a folded map with a pin in it, and the name on a strip below.
    static func mapPiece(_ look: Look) -> SKTexture {
        designed(.place, CGSize(width: 96, height: 58)) { ctx in
            let sheet = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 96, height: 58), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            ctx.addPath(sheet); ctx.setFillColor(Theme.mapLand.cgColor); ctx.fillPath()
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: 96, height: 44))
            ctx.addPath(path("M-2 36 Q20 30 40 38 Q60 46 98 30 L98 44 Q70 52 40 46 Q10 40 -2 50 Z")); ctx.setFillColor(Theme.mapWater.cgColor); ctx.fillPath()
            ctx.addPath(path("M58 0 Q70 14 64 26 Q58 34 74 40 L96 36 L96 0 Z")); ctx.setFillColor(Theme.mapPark.cgColor); ctx.fillPath()
            stroke(ctx, path("M0 18 L96 18 M30 0 L30 58 M0 8 L60 58 M72 0 L80 58"), Theme.mapRoad, 2.2)
            stroke(ctx, path("M0 18 L96 18 M30 0 L30 58"), Theme.mapMainRoad, 1.2)
            // The folds: one panel turned a little away from the light.
            ctx.setFillColor(Theme.thingEdge.withAlphaComponent(0.04).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 44))
            ctx.setFillColor(Theme.thingEdge.withAlphaComponent(0.07).cgColor); ctx.fill(CGRect(x: 31, y: 0, width: 1, height: 44))
            ctx.setFillColor(Theme.mapRoad.withAlphaComponent(0.6).cgColor); ctx.fill(CGRect(x: 63, y: 0, width: 1.2, height: 44))
            ctx.restoreGState()
            ctx.addPath(path("M48 26 C48 20 56 20 56 26 C56 30 52 33 52 36 C52 33 48 30 48 26 Z")); ctx.setFillColor(Theme.mapPin.cgColor); ctx.fillPath()
            ctx.setFillColor(NSColor.white.cgColor); ctx.fillEllipse(in: CGRect(x: 50.4, y: 24, width: 3.2, height: 3.2))
            ctx.setFillColor(Theme.page.cgColor); ctx.fill(CGRect(x: 0, y: 44, width: 96, height: 14))
            siteIcon(ctx, CGRect(x: 4, y: 46.5, width: 9, height: 9), look)
            withAppKit(ctx) {
                draw(look.title, in: CGRect(x: 16, y: 46, width: 77, height: 10), font: Theme.ui(6.8, .semibold), color: Theme.tagText, align: .left)
            }
            age(ctx, sheet, look.aged)
            stroke(ctx, sheet, Theme.thingEdge, 0.6)
        }
    }

    /// A product: a cardboard price tag with a barcode.
    static func priceTag(_ look: Look) -> SKTexture {
        designed(.product, CGSize(width: 92, height: 46)) { ctx in
            let shape = path("M12 0 L89 0 Q92 0 92 3 L92 43 Q92 46 89 46 L12 46 L0 23 Z")
            ctx.addPath(shape); ctx.setFillColor(Theme.kraft.cgColor); ctx.fillPath()
            age(ctx, shape, look.aged)
            stroke(ctx, shape, Theme.kraftEdge, 0.6)
            let hole = CGRect(x: 7.4, y: 20.4, width: 5.2, height: 5.2)
            ctx.setFillColor(Theme.barcodePaper.cgColor); ctx.fillEllipse(in: hole)
            stroke(ctx, CGPath(ellipseIn: hole, transform: nil), Theme.kraftEdge, 0.6)
            siteIcon(ctx, CGRect(x: 18, y: 6, width: 9, height: 9), look)
            withAppKit(ctx) {
                draw(look.host ?? "", in: CGRect(x: 30, y: 7, width: 34, height: 8), font: Theme.ui(5.6, .bold), color: Theme.kraftMeta, align: .left)
                drawCentered(look.title, in: CGRect(x: 18, y: 18, width: 46, height: 17), font: Theme.ui(7, .semibold), color: Theme.kraftInk, lines: 2, lineHeight: 8)
            }
            ctx.setFillColor(Theme.barcodePaper.cgColor); ctx.fill(CGRect(x: 66, y: 8, width: 22, height: 30))
            ctx.setFillColor(Theme.kraftInk.cgColor)
            for i in 0..<12 { ctx.fill(CGRect(x: 68 + CGFloat(i) * 1.6, y: 10, width: i % 3 == 0 ? 1 : 0.5, height: 24)) }
        }
    }

    /// A document: a page with its corner folded over, its title and a few lines of text.
    static func document(_ look: Look) -> SKTexture {
        designed(.document, CGSize(width: 56, height: 70)) { ctx in
            let sheet = path("M0 0 L44 0 L56 12 L56 70 L0 70 Z")
            ctx.addPath(sheet); ctx.setFillColor(Theme.page.cgColor); ctx.fillPath()
            let fold = path("M44 0 L44 12 L56 12 Z")
            ctx.addPath(fold); ctx.setFillColor(Theme.pageFold.cgColor); ctx.fillPath()
            siteIcon(ctx, CGRect(x: 6, y: 6, width: 9, height: 9), look)
            withAppKit(ctx) {
                drawCentered(look.title, in: CGRect(x: 6, y: 16, width: 44, height: 15), font: Theme.ui(6.6, .bold), color: Theme.codeInk, lines: 2, lineHeight: 7)
            }
            for (i, y) in stride(from: CGFloat(34), to: 66, by: 5).enumerated() {
                stroke(ctx, path("M7 \(y) L\(i % 3 == 2 ? 42 : 49) \(y)"), Theme.pageLines, 1.6, round: true)
            }
            age(ctx, sheet, look.aged)
            stroke(ctx, sheet, Theme.thingEdge, 0.6)
            stroke(ctx, fold, Theme.thingEdge, 0.6)
        }
    }

    /// Any other link: a luggage tag with the site's icon on its coloured end, a punched hole, the site above the title.
    static func tag(_ look: Look) -> SKTexture {
        let size = JarGeometry.size(of: .page)
        return texture(size, scale: thingScale) { ctx in
            let w = size.width, h = size.height
            let host = look.host ?? "?"
            let color = siteColor(look)
            let shape = path("M9 0 L\(w - 4) 0 Q\(w) 0 \(w) 4 L\(w) \(h - 4) Q\(w) \(h) \(w - 4) \(h) L9 \(h) L0 \(h - 9) L0 9 Z")
            ctx.addPath(shape); ctx.setFillColor(Theme.paper(aged: look.aged).cgColor); ctx.fillPath()
            ctx.addPath(path("M9 0 L24 0 L24 \(h) L9 \(h) L0 \(h - 9) L0 9 Z")); ctx.setFillColor(color.cgColor); ctx.fillPath()
            stroke(ctx, shape, Theme.thingEdge, 0.6)
            let hole = CGRect(x: 7.6, y: h / 2 - 3.4, width: 6.8, height: 6.8)
            ctx.addEllipse(in: hole); ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor); ctx.fillPath()
            ctx.addEllipse(in: hole); ctx.setStrokeColor(Theme.thingEdge.cgColor); ctx.setLineWidth(0.5); ctx.strokePath()
            if look.icon != nil { siteIcon(ctx, CGRect(x: 12, y: 3.5, width: 8.5, height: 8.5), look) }
            withAppKit(ctx) {
                let caps = NSAttributedString(string: host.uppercased(), attributes: [
                    .font: Theme.ui(8.5, .bold), .foregroundColor: color, .kern: 0.4, .paragraphStyle: truncating(.left)])
                caps.draw(with: CGRect(x: 30, y: 5, width: w - 34, height: 11), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
                draw(look.title, in: CGRect(x: 30, y: 17, width: w - 34, height: 16), font: Theme.ui(12, .semibold), color: Theme.tagText, align: .left)
            }
        }
    }

    /// A note: a strip torn from a ruled notebook, written by hand.
    static func note(_ look: Look) -> SKTexture {
        let size = JarGeometry.size(of: .text)
        return texture(size, scale: thingScale) { ctx in
            let w = size.width, h = size.height
            let shape = CGMutablePath()
            shape.move(to: CGPoint(x: 0, y: 2))
            var x: CGFloat = 0
            while x < w {
                shape.addLine(to: CGPoint(x: x + 3, y: Int(x) % 12 == 0 ? 0 : 2.5))
                shape.addLine(to: CGPoint(x: min(w, x + 6), y: 1.5))
                x += 6
            }
            shape.addLine(to: CGPoint(x: w, y: h)); shape.addLine(to: CGPoint(x: 0, y: h)); shape.closeSubpath()
            ctx.addPath(shape); ctx.setFillColor(Theme.paper(aged: look.aged).cgColor); ctx.fillPath()
            for y in [CGFloat(19), 33] { stroke(ctx, path("M0 \(y) L\(w) \(y)"), Theme.notebookRule, 0.7) }
            stroke(ctx, path("M12 2 L12 \(h)"), Theme.notebookMargin, 0.7)
            stroke(ctx, shape, Theme.thingEdge, 0.6)
            withAppKit(ctx) {
                drawCentered(look.title, in: CGRect(x: 16, y: 4, width: w - 22, height: h - 6), font: Theme.hand(17), color: Theme.ink, lines: 2, lineHeight: 15)
            }
        }
    }

    /// A file: a manila folder with its type stamped on it in a colour of its own.
    static func folder(_ look: Look) -> SKTexture {
        let size = JarGeometry.size(of: .file)
        return texture(size, scale: thingScale) { ctx in
            let w = size.width, h = size.height
            let ext = (look.fileExtension ?? "").uppercased()
            let shape = path("M0 6 Q0 2 4 2 L30 2 L35 6 L\(w - 3) 6 Q\(w) 6 \(w) 9 L\(w) \(h - 3) Q\(w) \(h) \(w - 3) \(h) L3 \(h) Q0 \(h) 0 \(h - 3) Z")
            ctx.addPath(shape); ctx.setFillColor(Theme.folder.cgColor); ctx.fillPath()
            age(ctx, shape, look.aged)
            stroke(ctx, shape, Theme.folderEdge, 0.6)
            let stamp = Theme.stamp(for: ext)
            ctx.saveGState()
            ctx.translateBy(x: 24, y: 25); ctx.rotate(by: -6 * .pi / 180)
            ctx.addPath(CGPath(roundedRect: CGRect(x: -18, y: -11, width: 36, height: 22), cornerWidth: 3, cornerHeight: 3, transform: nil))
            ctx.setStrokeColor(stamp.cgColor); ctx.setLineWidth(1.6); ctx.strokePath()
            withAppKit(ctx) {
                draw(String(ext.prefix(4)), in: CGRect(x: -18, y: -7, width: 36, height: 14), font: Theme.ui(ext.count > 3 ? 9.5 : 11, .heavy), color: stamp, align: .center)
            }
            ctx.restoreGState()
            let name = ext.isEmpty ? look.title : (look.title as NSString).deletingPathExtension
            withAppKit(ctx) {
                drawCentered(name, in: CGRect(x: 48, y: 8, width: w - 52, height: h - 10), font: Theme.ui(11, .semibold), color: Theme.folderText, lines: 2, lineHeight: 13)
            }
        }
    }

    /// A picture: a print with a wide white border at the bottom.
    static func photo(_ look: Look) -> SKTexture {
        let size = JarGeometry.size(of: .image)
        return texture(size, scale: thingScale) { ctx in
            let frame = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            let shape = CGPath(roundedRect: frame, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            ctx.addPath(shape); ctx.setFillColor(Theme.paper.cgColor); ctx.fillPath()
            let picture = CGRect(x: 4, y: 4, width: size.width - 8, height: size.width - 8)
            if let image = look.thumbnail {
                ctx.saveGState()
                ctx.clip(to: picture)
                drawImage(ctx, image, aspectFill: picture)
                ctx.restoreGState()
            } else {
                ctx.setFillColor(Theme.glassTint.cgColor); ctx.fill(picture)
            }
            age(ctx, shape, look.aged)
            stroke(ctx, shape, Theme.thingEdge, 0.6)
        }
    }

    /// Yellows paper and fades pictures the longer they have sat in the jar.
    private static func age(_ ctx: CGContext, _ shape: CGPath, _ amount: Double) {
        guard amount > 0 else { return }
        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        ctx.setBlendMode(.multiply)
        ctx.setFillColor(Theme.paperAged.withAlphaComponent(CGFloat(amount) * 0.55).cgColor)
        ctx.fill(shape.boundingBoxOfPath)
        ctx.restoreGState()
    }

    static func floorShadow() -> SKTexture {
        let size = CGSize(width: 290, height: 30)
        return texture(size, scale: 1) { ctx in
            ctx.saveGState()
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.scaleBy(x: 1, y: size.height / size.width)
            // The heel stops the light and the clear body lets it through, so the shadow is a ring.
            let s = Theme.floorShadow
            ctx.drawRadialGradient(gradient([(s, 0.2, 0), (s, 0.15, 0.55), (s, 0.75, 0.82), (s, 0, 1)]),
                                   startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: size.width / 2, options: [])
            ctx.restoreGState()
            // In front, the light the jar gathers like a lens.
            softEllipse(ctx, CGRect(x: size.width / 2 - 64, y: size.height / 2, width: 128, height: 7), .white, 0.55)
            softEllipse(ctx, CGRect(x: size.width / 2 - 18, y: size.height / 2 + 2.1, width: 36, height: 2.8), .white, 0.7)
        }
    }

    /// The menu bar icon: a jar's outline with a cap, as a template image.
    static func statusIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            ctx.translateBy(x: 3.4, y: 1.2)
            ctx.scaleBy(x: 11.2 / 256, y: 15.6 / 400)
            ctx.translateBy(x: -22, y: -14)
            ctx.addPath(path(outer))
            ctx.restoreGState()
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.4)
            ctx.strokePath()
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(CGPath(roundedRect: CGRect(x: 5.6, y: 0.6, width: 6.8, height: 2.6), cornerWidth: 1, cornerHeight: 1, transform: nil))
            ctx.fillPath()
            ctx.fill(CGRect(x: 6.5, y: 9.4, width: 5, height: 1.2))
            ctx.fill(CGRect(x: 6.5, y: 11.8, width: 3.4, height: 1.2))
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: Drawing helpers

    /// Draws into a bitmap `scale` times the design size, y-down, and wraps it
    /// as a texture whose point size is the design size.
    static func texture(_ size: CGSize, scale: CGFloat, _ body: (CGContext) -> Void) -> SKTexture {
        let image = cgImage(size, scale: scale, body)
        let t = SKTexture(cgImage: image)
        t.filteringMode = .linear
        return t
    }

    static func cgImage(_ size: CGSize, scale: CGFloat, _ body: (CGContext) -> Void) -> CGImage {
        let w = max(1, Int((size.width * scale).rounded(.up))), h = max(1, Int((size.height * scale).rounded(.up)))
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        body(ctx)
        return ctx.makeImage()!
    }

    static func withAppKit(_ ctx: CGContext, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    static func draw(_ text: String, in rect: CGRect, font: NSFont, color: NSColor, align: NSTextAlignment) {
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                attributes: [.font: font, .foregroundColor: color, .paragraphStyle: truncating(align)])
    }

    /// Up to `lines` lines `lineHeight` apart, wrapped at words, the last one cut with an ellipsis,
    /// centred in the rect's height.
    static func drawCentered(_ text: String, in rect: CGRect, font: NSFont, color: NSColor, lines: Int, lineHeight: CGFloat) {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        para.minimumLineHeight = lineHeight
        para.maximumLineHeight = lineHeight
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
        let box = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: lineHeight * CGFloat(lines) + 1)
        let used = (text as NSString).boundingRect(with: box.size, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
        let top = rect.minY + max(0, (rect.height - ceil(used.height)) / 2)
        (text as NSString).draw(with: CGRect(x: box.minX, y: top, width: box.width, height: box.height),
                                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }

    static func truncating(_ align: NSTextAlignment) -> NSParagraphStyle {
        let para = NSMutableParagraphStyle()
        para.alignment = align
        para.lineBreakMode = .byTruncatingTail
        return para
    }

    static func drawImage(_ ctx: CGContext, _ image: CGImage, aspectFill r: CGRect) {
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        let s = max(r.width / iw, r.height / ih)
        let dw = iw * s, dh = ih * s
        let dest = CGRect(x: r.midX - dw / 2, y: r.midY - dh / 2, width: dw, height: dh)
        // The context is flipped; flip the image back so it is upright.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: dest.maxY + dest.minY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: dest)
        ctx.restoreGState()
    }

    /// A soft highlight: `across` is its colour from left to right, `along` how strong it is from top
    /// to bottom (strength, location), so it fades in and out like a reflection instead of ending square.
    private static func band(_ ctx: CGContext, _ r: CGRect, across: [(NSColor, CGFloat, CGFloat)],
                             along: [(CGFloat, CGFloat)], alpha: CGFloat) {
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let corner = min(r.width, r.height) / 2
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: corner, cornerHeight: corner, transform: nil))
        ctx.clip()
        linear(ctx, across, from: CGPoint(x: r.minX, y: 0), to: CGPoint(x: r.maxX, y: 0))
        ctx.setBlendMode(.destinationIn)
        linear(ctx, along.map { (.white, $0.0, $0.1) }, from: CGPoint(x: 0, y: r.minY), to: CGPoint(x: 0, y: r.maxY))
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// A colour at `alpha` in the middle of the ellipse, fading to nothing at its edge.
    private static func softEllipse(_ ctx: CGContext, _ r: CGRect, _ color: NSColor, _ alpha: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: r.midX, y: r.midY)
        ctx.scaleBy(x: 1, y: r.height / r.width)
        ctx.drawRadialGradient(gradient([(color, alpha, 0), (color, 0, 1)]),
                               startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r.width / 2, options: [])
        ctx.restoreGState()
    }

    private static func gradientStroke(_ ctx: CGContext, _ p: CGPath, _ width: CGFloat, _ stops: [(NSColor, CGFloat, CGFloat)],
                                       from: CGPoint, to: CGPoint) {
        ctx.saveGState()
        ctx.addPath(p)
        ctx.setLineWidth(width)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        linear(ctx, stops, from: from, to: to)
        ctx.restoreGState()
    }

    /// A pinpoint of light where a curve of glass faces the light exactly.
    private static func glint(_ ctx: CGContext, at p: CGPoint, size: CGFloat) {
        softEllipse(ctx, CGRect(x: p.x - 2.4 * size, y: p.y - 2.4 * size, width: 4.8 * size, height: 4.8 * size), .white, 1)
        let cross = CGMutablePath()
        cross.move(to: CGPoint(x: p.x - 4.5 * size, y: p.y)); cross.addLine(to: CGPoint(x: p.x + 4.5 * size, y: p.y))
        cross.move(to: CGPoint(x: p.x, y: p.y - 3.5 * size)); cross.addLine(to: CGPoint(x: p.x, y: p.y + 3.5 * size))
        stroke(ctx, cross, NSColor.white.withAlphaComponent(0.8), 0.5 * size, round: true)
    }

    static func stroke(_ ctx: CGContext, _ p: CGPath, _ color: NSColor, _ width: CGFloat, round: Bool = false) {
        ctx.addPath(p)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(round ? .round : .butt)
        ctx.strokePath()
    }

    static func fill(_ ctx: CGContext, _ p: CGPath, _ stops: [(NSColor, CGFloat, CGFloat)], from: CGPoint, to: CGPoint) {
        ctx.saveGState()
        ctx.addPath(p); ctx.clip()
        linear(ctx, stops, from: from, to: to)
        ctx.restoreGState()
    }

    /// Draws `body` as one layer at `alpha`, so overlapping strokes (a wire's shade and shine) do not show through each other.
    static func faint(_ ctx: CGContext, _ alpha: CGFloat, _ body: () -> Void) {
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// Part of an ellipse, y-down, from one angle to the other: from .pi to 0 runs left to right along the near side.
    static func ellipseArc(center: CGPoint, rx: CGFloat, ry: CGFloat, from a: CGFloat, to b: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let steps = 64
        for i in 0...steps {
            let t = a + (b - a) * CGFloat(i) / CGFloat(steps)
            let q = CGPoint(x: center.x + rx * cos(t), y: center.y + ry * sin(t))
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        return p
    }

    static func gradient(_ stops: [(NSColor, CGFloat, CGFloat)]) -> CGGradient {
        let colors = stops.map { $0.0.withAlphaComponent($0.0.alphaComponent * $0.1).cgColor }
        return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: stops.map(\.2))!
    }

    static func linear(_ ctx: CGContext, _ stops: [(NSColor, CGFloat, CGFloat)], from: CGPoint, to: CGPoint) {
        ctx.drawLinearGradient(gradient(stops), start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// Absolute SVG path commands M, L, C, Q and Z: enough for the jar's artwork.
    static func path(_ d: String) -> CGPath {
        let p = CGMutablePath()
        var tokens: [String] = []
        var current = ""
        for ch in d {
            if ch.isLetter {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            } else if ch == " " || ch == "," {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        var i = 0
        var command = "M"
        func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        func pt() -> CGPoint { CGPoint(x: num(), y: num()) }
        while i < tokens.count {
            if tokens[i].first?.isLetter == true { command = tokens[i]; i += 1 }
            switch command {
            case "M": p.move(to: pt()); command = "L"
            case "L": p.addLine(to: pt())
            case "C": let a = pt(), b = pt(), c = pt(); p.addCurve(to: c, control1: a, control2: b)
            case "Q": let a = pt(), b = pt(); p.addQuadCurve(to: b, control: a)
            case "Z": p.closeSubpath(); command = ""  // numbers after a Z belong to nothing: skipped below
            default: i += 1
            }
        }
        return p
    }
}
