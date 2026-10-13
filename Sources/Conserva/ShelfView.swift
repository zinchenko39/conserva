import AppKit
import ConservaCore
import SpriteKit

/// What the shelf view asks of the app around it.
@MainActor
protocol ShelfViewDelegate: AnyObject {
    func shelfView(_ view: ShelfView, showCardFor thing: Thing)
    func shelfView(_ view: ShelfView, rename rig: JarRig)
    func shelfView(_ view: ShelfView, menuFor target: ShelfScene.Target) -> NSMenu?
    func shelfViewPaste(_ view: ShelfView)
    /// A plain click on a jar's glass or label, with nothing dragged.
    func shelfView(_ view: ShelfView, clicked rig: JarRig)
    func shelfViewDismiss(_ view: ShelfView)
    func shelfViewInteractionChanged(_ view: ShelfView)
}

/// The shelf's mouse, keyboard and drag and drop. A press only becomes a drag
/// after the pointer travels a few points, so a plain click on a slip, the
/// label or the lid stays a click.
///
/// - Click a slip in a jar: it comes out through the neck.
/// - Drag a jar by its body: carry it; by its neck or shoulders: tilt it.
/// - Click the lid: open it or close it.
/// - Double-click the label: rename the jar.
/// - Drag something from the floor into another app: it gets a copy.
/// - Drop anything on a jar: it goes in.
final class ShelfView: SKView, NSDraggingSource {
    weak var shelfDelegate: ShelfViewDelegate?

    private struct Press {
        var target: ShelfScene.Target
        var start: CGPoint
        var clickCount: Int
        var grabbed: JarRig?
        /// The jar whose open lid is being swung by hand.
        var lidHeld: JarRig?
        var draggedOut = false
    }

    private var press: Press?
    private(set) var dropping = false
    var isInteracting: Bool { press != nil || dropping }

    var shelfScene: ShelfScene? { scene as? ShelfScene }

    override init(frame: NSRect) {
        super.init(frame: frame)
        allowsTransparency = true
        ignoresSiblingOrder = true
        // Tried at 60: the jars and their contents never quite settle at the larger step and keep twitching.
        preferredFramesPerSecond = 120
        registerForDraggedTypes(Pasteboard.readTypes)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                                       owner: self, userInfo: nil))
    }

    private func scenePoint(_ event: NSEvent) -> CGPoint? {
        guard let scene = shelfScene else { return nil }
        return scene.convertPoint(fromView: convert(event.locationInWindow, from: nil))
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        guard let scene = shelfScene, let p = scenePoint(event), let target = scene.target(at: p) else { return }
        // The panel takes the keys without activating the app where it can; where the system will not
        // give an inactive app's panel the keys, the app is brought forward, as a click on it would.
        window?.makeKey()
        if !(window?.isKeyWindow ?? false) {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
        press = Press(target: target, start: p, clickCount: event.clickCount)
        if case .jar(let rig, _) = target { scene.setActive(rig) }
        shelfDelegate?.shelfViewInteractionChanged(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var current = press, let scene = shelfScene, let p = scenePoint(event) else { return }
        if let rig = current.grabbed {
            scene.drag(rig, to: p)
            return
        }
        if let rig = current.lidHeld {
            scene.dragLid(rig, to: p)
            return
        }
        guard !current.draggedOut, hypot(p.x - current.start.x, p.y - current.start.y) > 5 else { return }
        switch current.target {
        case .thing(let thing):
            if let rig = thing.rig { current.grabbed = rig; scene.grab(rig, at: current.start, tilt: isGrip(rig, current.start, scene)) }
        case .label(let rig), .jar(let rig, _):
            current.grabbed = rig
            scene.grab(rig, at: current.start, tilt: isGrip(rig, current.start, scene))
        case .lid(let rig):
            // An open lid swings on its hinge after the pointer; dragging the shut one tilts the jar,
            // like grabbing it by the top.
            if scene.grabLid(rig, at: current.start) {
                current.lidHeld = rig
            } else {
                current.grabbed = rig
                scene.grab(rig, at: current.start, tilt: true)
            }
        case .out(let thing):
            current.draggedOut = true
            beginDragOut(thing, event: event)
        }
        press = current
        if let rig = current.grabbed { scene.drag(rig, to: p) }
        if let rig = current.lidHeld { scene.dragLid(rig, to: p) }
    }

    private func isGrip(_ rig: JarRig, _ scenePoint: CGPoint, _ scene: ShelfScene) -> Bool {
        let local = rig.toLocal(scene.world.convert(scenePoint, from: scene))
        return JarGeometry.design(local).y < JarGeometry.tiltGripY
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            press = nil
            shelfDelegate?.shelfViewInteractionChanged(self)
        }
        guard let current = press, let scene = shelfScene else { return }
        if let rig = current.lidHeld {
            scene.releaseLid(rig)
            return
        }
        if let rig = current.grabbed {
            scene.release(rig)
            return
        }
        guard !current.draggedOut else { return }
        switch current.target {
        case .thing(let thing):
            scene.pull(thing)
        case .label(let rig):
            scene.setActive(rig)
            if event.clickCount >= 2 { shelfDelegate?.shelfView(self, rename: rig) } else { shelfDelegate?.shelfView(self, clicked: rig) }
        case .jar(let rig, _):
            scene.setActive(rig)
            shelfDelegate?.shelfView(self, clicked: rig)
        case .lid(let rig):
            scene.toggleLid(rig)
        case .out(let thing):
            shelfDelegate?.shelfView(self, showCardFor: thing)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let scene = shelfScene, let p = scenePoint(event), let target = scene.target(at: p),
              let menu = shelfDelegate?.shelfView(self, menuFor: target) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func mouseMoved(with event: NSEvent) {
        guard press == nil, let scene = shelfScene, let p = scenePoint(event) else { return }
        switch scene.target(at: p) {
        case .thing(let thing), .out(let thing):
            scene.setHover(thing)
            NSCursor.pointingHand.set()
        case .lid:
            scene.setHover(nil)
            NSCursor.pointingHand.set()
        case .jar, .label:
            scene.setHover(nil)
            NSCursor.openHand.set()
        case nil:
            scene.setHover(nil)
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        shelfScene?.setHover(nil)
        NSCursor.arrow.set()
    }

    // MARK: Keyboard

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isPaste(event) {
            shelfDelegate?.shelfViewPaste(self)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// ⌘V, or ⌃V for hands used to other systems. By key position, so it works in any layout.
    private func isPaste(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        return (mods == .command || mods == .control) && event.keyCode == 9
    }

    override func keyDown(with event: NSEvent) {
        if isPaste(event) { shelfDelegate?.shelfViewPaste(self); return }
        guard let scene = shelfScene, let rig = scene.activeRig else { return super.keyDown(with: event) }
        switch Int(event.keyCode) {
        case 36, 76: _ = scene.pullRandom(from: rig)                 // Return
        case 49: scene.hop(rig)                                      // Space
        case 123: scene.nudge(rig, by: 1.4)                          // Left
        case 124: scene.nudge(rig, by: -1.4)                         // Right
        case 120: shelfDelegate?.shelfView(self, rename: rig)        // F2
        case 53: shelfDelegate?.shelfViewDismiss(self)               // Escape
        case 48:                                                     // Tab: next jar
            if let i = scene.rigs.firstIndex(where: { $0 === rig }) { scene.setActive(scene.rigs[(i + 1) % scene.rigs.count]) }
        default: super.keyDown(with: event)
        }
    }

    // MARK: Dropping things in

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropping = true
        shelfDelegate?.shelfViewInteractionChanged(self)
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let scene = shelfScene, Pasteboard.canRead(sender.draggingPasteboard) else { return [] }
        if sender.draggingSource as? ShelfView === self { return [] }
        let p = scene.convertPoint(fromView: convert(sender.draggingLocation, from: nil))
        let rig = scene.rig(under: p)
        scene.setHot(rig)
        return rig == nil ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        shelfScene?.setHot(nil)
        dropping = false
        shelfDelegate?.shelfViewInteractionChanged(self)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let scene = shelfScene else { return false }
        let p = scene.convertPoint(fromView: convert(sender.draggingLocation, from: nil))
        guard let rig = scene.rig(under: p) else { return false }
        let incoming = Pasteboard.incoming(from: sender.draggingPasteboard)
        guard !incoming.isEmpty else { return false }
        scene.model.add(incoming, to: rig.id, from: p)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        shelfScene?.setHot(nil)
        dropping = false
        shelfDelegate?.shelfViewInteractionChanged(self)
    }

    // MARK: Dragging things out

    private func beginDragOut(_ thing: Thing, event: NSEvent) {
        guard let scene = shelfScene else { return }
        let item = thing.item
        let writer: NSPasteboardWriting
        switch item.kind {
        case .link: writer = (ShelfModel.webURL(of: item) ?? URL(string: "about:blank")!) as NSURL
        case .text: writer = (item.text ?? item.title) as NSString
        case .image, .file:
            guard let url = scene.model.fileURL(of: item) else { return }
            writer = url as NSURL
        }
        let dragItem = NSDraggingItem(pasteboardWriter: writer)
        let size = CGSize(width: thing.size.width * ShelfScene.jarScale * 1.4, height: thing.size.height * ShelfScene.jarScale * 1.4)
        let center = convert(scene.convertPoint(toView: scene.convert(thing.position, from: scene.world)), to: self)
        let image = thing.sprite.texture.map { NSImage(cgImage: $0.cgImage(), size: size) }
        dragItem.setDraggingFrame(CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                         width: size.width, height: size.height), contents: image)
        let session = beginDraggingSession(with: [dragItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
