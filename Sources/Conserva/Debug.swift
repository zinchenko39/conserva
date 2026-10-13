import AppKit
import ConservaCore
import SpriteKit

/// Nothing on the shelf can be clicked or seen from a terminal, so a test
/// instance is driven by environment variables:
///
/// - `CONSERVA_DEBUG_SEQ`: actions separated by `;`, run in order, e.g.
///   `reveal; wait 1.5; snap shelf; pull 0; wait 3; snap pulled; state; quit`.
///   Actions: `reveal`, `hide`, `wait <s>`, `snap <name>`, `state`, `pull <jar>`,
///   `add <jar> <text>`, `addfile <jar> <path>`, `name <jar> <text>` (renames the jar), `hop <jar>`, `tilt <jar> <radians>`,
///   `release <jar>`, `carry <jar> <x> <y>`, `carryto <jar> <other jar>`, `lid <jar>`, `collect`,
///   `hover <jar> <n>` (the pointer rests on the jar's n-th thing, oldest first; -1 for none),
///   `lidgrab <jar>`, `liddrag <jar> <radians>`, `lidlet <jar>` (a hand swings the open lid and lets go),
///   `pointer <x> <y>` / `pointer jar <n>` / `pointer peek <n>` / `pointer edge` / `pointer away` / `pointer off` (a pointer of the
///   test's own, in screen points, so the jars' coming and going can be checked), `mousedown on|off`,
///   `extdrag on|off` (something picked up in another app, or let go),
///   `under <jar> <dx>` (logs which jar a drop would go into that many points right of the jar's middle),
///   `deactivate` (another app comes to the front), `clickjar <n>` (a click on a jar's middle; logs whether the shelf then takes the keys),
///   `keyv cmd|ctrl [ru]` (⌘V or ⌃V sent to the app, with a Russian layout if `ru`), `clip <text>` (a clipboard of the test's own holding the text),
///   `wiggle <jar> <n>` (for two seconds the pointer trembles at a corner of the jar's n-th thing, hovering
///   whatever is under it the way moving the mouse does; logs how often the hovered thing changed),
///   `clickthing <jar> <n>` (a click on the jar's n-th thing, oldest first; logs where it was, in scene points),
///   `clicklid <jar>` (a click on the jar's lid; logs where, in scene points),
///   `film <name> <s> [<fps>]` (that many seconds of film, 50 frames a second unless told: the shelf moves on in
///   fixed steps, three to a frame, and every frame writes the bottom left 680 × 380 points of the jars and what
///   is out of them, transparent and in pixels, as `<name>_<frame>_<seconds>_<x>_<y>_<width>_<height>.png`;
///   the steps after it run alongside and wait in film time),
///   `probe <jar> <s>` (watches the jar's contents for that long and logs kicks, bounces and when they last moved),
///   `lang <code>` (switches the interface language as the menu does and logs a sample; it stays in the defaults),
///   `card <action>`, `sounds` (writes every sound as a WAV file to the snapshot folder), `quit`.
/// - `CONSERVA_DEBUG_SNAPSHOT`: the folder snapshots go to. Each snapshot is the
///   shelf drawn over a light and a dark desktop, plus the card when one is shown.
/// - `CONSERVA_HOME`: a separate shelf, so the real one is never touched.
/// - `CONSERVA_TRASH`: a folder that stands in for the Trash, so nothing lands in the real one.
@MainActor
final class Debug {
    private unowned let app: AppDelegate
    private var steps: [String]
    private let folder: URL
    /// Film time while filming: the steps that follow wait in it instead of on the clock.
    private var filmClock: Double?
    private var filmResume: Double?

    static func fromEnvironment(app: AppDelegate) -> Debug? {
        // Only a debug build can be driven from outside: a release one ignores the variables, so
        // nothing launched with a doctored environment can read the clipboard or move files through it.
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard let seq = env["CONSERVA_DEBUG_SEQ"], !seq.isEmpty else { return nil }
        let folder = URL(fileURLWithPath: env["CONSERVA_DEBUG_SNAPSHOT"] ?? NSTemporaryDirectory())
        return Debug(app: app, sequence: seq, folder: folder)
        #else
        return nil
        #endif
    }

    private init(app: AppDelegate, sequence: String, folder: URL) {
        self.app = app
        self.folder = folder
        steps = sequence.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func start() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.next() } }

    private func next() {
        guard !steps.isEmpty else { return }
        let step = steps.removeFirst()
        let parts = step.split(separator: " ", maxSplits: 2).map(String.init)
        let scene = app.debugScene
        func rig(_ i: Int) -> JarRig? { i < scene.rigs.count ? scene.rigs[i] : nil }
        let n = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        log("step: \(step)")
        var delay: TimeInterval = 0.05
        switch parts[0] {
        case "reveal": app.reveal(pinned: true)
        case "hide": app.hide()
        case "wait": delay = Double(parts.count > 1 ? parts[1] : "1") ?? 1
        case "snap": snap(parts.count > 1 ? parts[1] : "shot")
        case "state": writeState()
        case "pull": if let r = rig(n) { log("pulled: \(scene.pullRandom(from: r))") }
        case "add": if let r = rig(n), parts.count > 2 { app.debugModel.add([.text(parts[2])], to: r.id) }
        case "name": if let r = rig(n), parts.count > 2 { app.debugModel.rename(r.id, to: parts[2]) }
        case "addfile": if let r = rig(n), parts.count > 2 { app.debugModel.add([.fileURL(URL(fileURLWithPath: parts[2]))], to: r.id) }
        case "hop": if let r = rig(n) { scene.hop(r) }
        case "tilt":
            if let r = rig(n), parts.count > 2, let a = Double(parts[2]) { scene.debugTilt(r, by: CGFloat(a)) }
        case "carry":
            // carry <jar> <x> <y>: hold the jar and pull it towards a point, through anything in the way.
            let xy = parts.count > 2 ? parts[2].split(separator: " ").compactMap { Double($0) } : []
            if let r = rig(n), xy.count == 2 { scene.debugCarry(r, to: CGPoint(x: xy[0], y: xy[1])) }
        case "carryto":
            // carryto <jar> <other>: pull the jar towards where another jar stands.
            if let r = rig(n), parts.count > 2, let o = Int(parts[2]), let other = rig(o) { scene.debugCarry(r, to: other.position) }
        case "release": if let r = rig(n) { scene.release(r) }
        case "lid": if let r = rig(n) { scene.toggleLid(r) }
        case "lidgrab": if let r = rig(n) { log("lid held: \(scene.grabLid(r, at: scene.debugLidPoint(r, angle: r.lidSprite.zRotation)))") }
        case "liddrag": if let r = rig(n), parts.count > 2, let a = Double(parts[2]) { scene.dragLid(r, to: scene.debugLidPoint(r, angle: CGFloat(a))) }
        case "lidlet": if let r = rig(n) { scene.releaseLid(r) }
        case "wiggle":
            if let r = rig(n), let p = scene.debugEdgePoint(r, Int(parts.count > 2 ? parts[2] : "0") ?? 0) {
                wiggle(at: p, frames: 120, last: scene.debugHoveredID, changes: 0)
                delay = 2.3
            }
        case "pointer":
            let rest = parts.dropFirst().joined(separator: " ").split(separator: " ").map(String.init)
            switch rest.first {
            case "off": app.debugPointer = nil
            case "jar": app.debugPointer = app.debugJarCenter(Int(rest.count > 1 ? rest[1] : "0") ?? 0)
            case "edge": app.debugPointer = app.debugLeftEdge
            case "peek": app.debugPointer = app.debugPeekCenter(Int(rest.count > 1 ? rest[1] : "0") ?? 0)
            case "away":
                let f = NSScreen.main!.frame
                app.debugPointer = NSPoint(x: f.maxX - 200, y: f.maxY - 200)
            default:
                if rest.count == 2, let x = Double(rest[0]), let y = Double(rest[1]) { app.debugPointer = NSPoint(x: x, y: y) }
            }
            log("pointer: \(app.debugPointer.map { "\(Int($0.x)), \(Int($0.y))" } ?? "real")")
        case "under": if parts.count > 2, let dx = Double(parts[2]) { log("drop goes into: \(scene.debugJarUnder(n, dx: CGFloat(dx)))") }
        case "clickjar": log("clicked: \(app.debugClickJar(n))")
        case "deactivate":
            NSApp.deactivate()
            log("app active: \(NSApp.isActive)")
        case "keyv":
            // `keyv cmd ru`: the same key with a Russian layout on, where it types the Cyrillic letter em.
            let args = parts.dropFirst().joined(separator: " ").split(separator: " ").map(String.init)
            app.debugKey(args.contains("ru") ? "\u{043C}" : "v", keyCode: 9, modifiers: args.contains("ctrl") ? .control : .command)
        case "clip":
            let pb = NSPasteboard(name: NSPasteboard.Name("ConservaDebugClipboard"))
            pb.clearContents()
            pb.setString(parts.dropFirst().joined(separator: " "), forType: .string)
            app.debugPasteboard = pb
        case "mousedown": app.debugMouseDown = parts.count > 1 && parts[1] == "on"
        case "extdrag": app.debugExternalDrag(parts.count > 1 && parts[1] == "on")
        case "clickthing":
            if let r = rig(n), let at = scene.debugPull(r, Int(parts.count > 2 ? parts[2] : "0") ?? 0) {
                log("clicked thing at \(Int(at.x)), \(Int(at.y)) of \(Int(scene.size.width))x\(Int(scene.size.height))")
            }
        case "film":
            let args = parts.dropFirst().joined(separator: " ").split(separator: " ").map(String.init)
            film(args.first ?? "film", seconds: args.count > 1 ? Double(args[1]) ?? 5 : 5, fps: args.count > 2 ? Double(args[2]) ?? 50 : 50)
        case "clicklid":
            if let r = rig(n) {
                let at = scene.debugLidTop(r)
                scene.toggleLid(r)
                log("clicked lid at \(Int(at.x)), \(Int(at.y))")
            }
        case "hover": if let r = rig(n) { scene.debugHover(r, Int(parts.count > 2 ? parts[2] : "-1") ?? -1) }
        case "probe": if let r = rig(n) { probe(r, seconds: Double(parts.count > 2 ? parts[2] : "5") ?? 5) }
        case "collect": scene.collectAll()
        case "lang":
            // Written to the real defaults, like the menu does: `defaults delete app.conserva.Conserva language` undoes it.
            Localization.set(parts.count > 1 ? parts[1] : "en")
            log("language: \(Localization.code) label.empty=\(L("label.empty")) menu.quit=\(L("menu.quit"))")
        case "card":
            if let id = app.debugCard.itemID {
                let action: ItemCard.Action = ["delete": .delete, "back": .putBack, "copy": .copy][parts.count > 1 ? parts[1] : ""] ?? .putBack
                app.debugCard.onAction?(action, id)
            }
        case "sounds":
            do { try SoundBoard.writeSamples(to: folder); log("wrote sound samples to \(folder.path)") } catch { log("sounds: \(error)") }
        case "quit": NSApp.terminate(nil)
        default: log("unknown step: \(step)")
        }
        if let clock = filmClock {
            filmResume = clock + (parts[0] == "wait" ? delay : 0)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.next() }
    }

    /// Watches a jar's contents for a while and logs how restless they are: kicks (a thing at rest in a
    /// still jar suddenly moving), bounces (falling, then going up again), the last moment anything moved,
    /// how far what the contents feel strays from plain gravity while the jar stands, and the top speed.
    private func probe(_ rig: JarRig, seconds: Double) {
        let scene = app.debugScene
        let g = scene.debugGravity
        var frames = 0, kicks = 0, bounces = 0, restless = 0
        var lastMotion = 0.0, maxSpeed = 0.0, maxStray = 0.0
        // Frames with something moving, second by second, so settling can be told from fidgeting.
        var timeline = [Int](repeating: 0, count: Int(seconds.rounded(.up)))
        var previous: [UUID: CGVector] = [:]
        let started = Date()
        scene.debugProbe = { [weak self] in
            let (felt, velocities) = scene.debugMotion(rig)
            let t = Date().timeIntervalSince(started)
            frames += 1
            if velocities.values.contains(where: { hypot($0.dx, $0.dy) > 5 }), Int(t) < timeline.count { timeline[Int(t)] += 1 }
            let stray = hypot(felt.dx, felt.dy + g) / g
            let still = stray < 0.05
            if still { maxStray = max(maxStray, Double(stray)) }
            for (id, v) in velocities {
                let speed = hypot(v.dx, v.dy)
                maxSpeed = max(maxSpeed, Double(speed))
                if speed > 5 { lastMotion = t; restless += 1 }
                guard let p = previous[id] else { continue }
                if still, hypot(p.dx, p.dy) < 8, speed > 40 { kicks += 1 }
                if p.dy < -60, v.dy > 25 { bounces += 1 }
            }
            previous = velocities
            guard t >= seconds else { return }
            scene.debugProbe = nil
            self?.log(String(format: "probe: %d frames, kicks %d, bounces %d, moving-frames %d, last motion at %.2fs, top speed %.0f, felt stray at rest %.3f, moving per second %@",
                             frames, kicks, bounces, restless, lastMotion, maxSpeed, maxStray, timeline.map(String.init).joined(separator: " ")))
        }
    }

    private func wiggle(at p: CGPoint, frames: Int, last: UUID?, changes: Int) {
        let scene = app.debugScene
        let q = CGPoint(x: p.x + CGFloat.random(in: -1...1), y: p.y + CGFloat.random(in: -1...1))
        switch scene.target(at: q) {
        case .thing(let thing), .out(let thing): scene.setHover(thing)
        default: scene.setHover(nil)
        }
        let now = scene.debugHoveredID
        let changes = changes + (now != last ? 1 : 0)
        guard frames > 1 else { log("hover changes: \(changes), hovering at the end: \(now != nil)"); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [weak self] in
            self?.wiggle(at: p, frames: frames - 1, last: now, changes: changes)
        }
    }

    private func snap(_ name: String) {
        let view = app.debugView
        guard let scene = view.scene, let texture = view.texture(from: scene) else { log("snap \(name): no texture"); return }
        let shelf = texture.cgImage()
        for (suffix, colors) in [("light", (NSColor(hex: 0xDFE8F0), NSColor(hex: 0xF4E7DA))), ("dark", (NSColor(hex: 0x0E1420), NSColor(hex: 0x2A2118)))] {
            let size = CGSize(width: shelf.width, height: shelf.height)
            let image = JarArt.cgImage(size, scale: 1) { ctx in
                JarArt.linear(ctx, [(colors.0, 1, 0), (colors.1, 1, 1)], from: .zero, to: CGPoint(x: 0, y: size.height))
                ctx.saveGState()
                ctx.translateBy(x: 0, y: size.height)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(shelf, in: CGRect(origin: .zero, size: size))
                ctx.restoreGState()
            }
            write(NSBitmapImageRep(cgImage: image), to: "\(name)-\(suffix).png")
        }
        // The shelf alone on nothing, for pictures that put it on a background of their own.
        let size = CGSize(width: shelf.width, height: shelf.height)
        let alone = JarArt.cgImage(size, scale: 1) { ctx in
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(shelf, in: CGRect(origin: .zero, size: size))
        }
        write(NSBitmapImageRep(cgImage: alone), to: "\(name)-alpha.png")
        if let card = app.debugCard.snapshot() { write(card, to: "\(name)-card.png") }
    }

    /// Films on a beat of the scene's own: each frame moves the shelf on by exactly one step, and the
    /// steps that follow wait in film time, so a run of slow captures shows as nothing at all.
    private func film(_ name: String, seconds: Double, fps: Double) {
        // The shelf moves on in steps as fine as a fast display's, as it does on screen, and every third
        // one is filmed.
        let substeps = 3, rate = fps * Double(substeps)
        let view = app.debugView, scene = app.debugScene
        // Encoding a PNG takes longer than a frame; spread over the cores it keeps up.
        let encoder = DispatchQueue(label: "film", qos: .userInitiated, attributes: .concurrent)
        var index = 0, step = 0
        filmClock = 0
        scene.debugStep = CGFloat(1 / rate)
        scene.debugFilm = { [weak self] in
            guard let self else { return }
            let t = Double(step) / rate
            step += 1
            // A fixed rectangle, the bottom left of the screen: one that follows what the jars cover moves
            // by fractions of a pixel from frame to frame, and a film put together from those trembles.
            let r = CGRect(x: 0, y: 0, width: 680, height: 380)
            if (step - 1) % substeps == 0, let texture = view.texture(from: scene.world, crop: r) {
                let image = texture.cgImage()
                let url = self.folder.appendingPathComponent(String(format: "%@_%04d_%.3f_%.1f_%.1f_%.1f_%.1f.png", name, index, t,
                                                                    r.minX, r.minY, r.width, r.height))
                encoder.async { try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url) }
                index += 1
            }
            let clock = Double(step) / rate
            self.filmClock = clock
            if clock >= seconds {
                scene.debugFilm = nil
                scene.debugStep = nil
                self.filmClock = nil
                self.log("film \(name): \(index) frames")
            }
            // Once the film is over, whatever waits on it goes on by the clock.
            if let due = self.filmResume, clock >= due || self.filmClock == nil {
                self.filmResume = nil
                self.next()
            }
        }
        log("film \(name): started")
    }

    private func write(_ rep: NSBitmapImageRep, to file: String) {
        let url = folder.appendingPathComponent(file)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
            log("wrote \(url.path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
        }
    }

    private func writeState() {
        let state: [String: Any] = ["jars": app.debugScene.debugState(),
                                    "revealed": app.debugRevealed, "peeking": app.debugPeeking,
                                    "shown": app.debugScene.debugShown, "peeked": app.debugScene.debugPeeked,
                                    "panelShown": app.debugPanelShown, "panelTakesMouse": app.debugPanelTakesMouse,
                                    "cardShown": app.debugCard.isShown,
                                    "items": app.debugModel.shelf.jars.map { ["name": $0.name, "count": $0.items.count] }]
        let url = AppPaths.home.appendingPathComponent("debug-state.json")
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
            log("state: \(String(decoding: data, as: UTF8.self))")
        }
    }

    /// Every sound the shelf makes is logged, so a run shows which ones fired and when.
    func heard(_ sound: Sound, volume: Float, pan: Float) {
        log("sound: \(sound) volume \(String(format: "%.2f", volume)) pan \(String(format: "%.2f", pan))")
    }

    private func log(_ s: String) {
        FileHandle.standardError.write(Data("[debug] \(s)\n".utf8))
    }
}
