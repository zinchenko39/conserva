import AppKit

/// A transparent layer over the whole usable screen, over every app and
/// every Space except full screen ones. It takes the mouse only over the jars
/// (the app decides where), and becomes key without activating the app, so
/// ⌘V and the keys work while you stay in the app you were using.
final class ShelfPanel: NSPanel {
    init(content: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        contentView = content
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    static func screenUnderPointer() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// The whole usable area of the screen: jars can stand anywhere on it.
    /// Clicks still pass through everywhere except over the jars.
    func fill(_ screen: NSScreen?) {
        guard let visible = (screen ?? Self.screenUnderPointer())?.visibleFrame else { return }
        if frame != visible { setFrame(visible, display: true) }
    }
}
