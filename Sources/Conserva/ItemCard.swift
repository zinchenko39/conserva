import AppKit
import ConservaCore

/// The card over a thing taken out of a jar: what it is, and what to do with it.
/// A small panel of its own so it can sit above the shelf and follow the system appearance.
@MainActor
final class ItemCard {
    enum Action { case open, copy, reveal, delete, putBack }

    /// Wide enough for a file's four buttons in one row, in Russian.
    private static let width: CGFloat = 344
    private static let inner: CGFloat = width - 28

    /// What can be done with a thing taken out: use it, find it if it is a file, throw it away, or put
    /// it back. The first is the default. Leaving it alone puts it back too, when the jars hide.
    static func actions(for kind: ItemKind) -> [(title: String, action: Action)] {
        let use: [(String, Action)]
        switch kind {
        case .link, .image: use = [(L("card.open"), .open)]
        // A note is already there to read on the card; copying it is how it gets used.
        case .text: use = [(L("card.copy"), .copy)]
        case .file: use = [(L("card.open"), .open), (L("card.reveal"), .reveal)]
        }
        return use + [(L("card.delete"), .delete), (L("card.putBack"), .putBack)]
    }

    private let panel: NSPanel
    /// The card's own window, for telling its events from the shelf's.
    var window: NSWindow { panel }
    private let effect = NSVisualEffectView()
    private var stack = NSStackView()
    private(set) var itemID: UUID?
    var onAction: ((Action, UUID) -> Void)?

    var isShown: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        panel.contentView = effect
    }

    func show(_ item: Item, jarName: String, image: NSImage?, at anchor: NSPoint) {
        // Shown again for another thing without being hidden in between: the old buttons' handlers go with them.
        ActionTarget.shared.handlers.removeAll()
        itemID = item.id
        stack.removeFromSuperview()
        stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: Self.width),
        ])

        let title = label(item.title, font: Theme.ui(14, .semibold), color: Theme.cardText, lines: 3)
        let meta = label(metaLine(item, jarName: jarName), font: Theme.ui(11.5), color: Theme.cardSecondary, lines: 2)
        let words = NSStackView(views: [title, meta])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 3
        stack.addArrangedSubview(words)
        words.widthAnchor.constraint(equalToConstant: Self.inner).isActive = true

        if item.kind == .image || item.kind == .link, let image {
            let view = NSImageView(image: image)
            view.imageScaling = .scaleProportionallyUpOrDown
            view.wantsLayer = true
            view.layer?.cornerRadius = 8
            view.layer?.masksToBounds = true
            let aspect = image.size.height / max(1, image.size.width)
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalToConstant: Self.inner).isActive = true
            view.heightAnchor.constraint(equalToConstant: min(190, Self.inner * aspect)).isActive = true
            stack.addArrangedSubview(view)
        }
        if item.kind == .text, let text = item.text, text != item.title {
            let body = label(text, font: Theme.ui(13), color: Theme.cardText, lines: 9)
            body.isSelectable = true
            body.widthAnchor.constraint(equalToConstant: Self.inner).isActive = true
            stack.addArrangedSubview(body)
        }

        var buttons: [NSButton] = []
        func add(_ title: String, _ action: Action, primary: Bool = false) {
            let b = NSButton(title: title, target: nil, action: nil)
            b.bezelStyle = .rounded
            b.controlSize = .regular
            if primary { b.keyEquivalent = "\r"; b.bezelColor = .controlAccentColor }
            let id = item.id
            b.target = ActionTarget.shared
            b.action = #selector(ActionTarget.fire(_:))
            ActionTarget.shared.handlers[ObjectIdentifier(b)] = { [weak self] in self?.onAction?(action, id) }
            buttons.append(b)
        }
        for (i, choice) in Self.actions(for: item.kind).enumerated() {
            add(choice.title, choice.action, primary: i == 0)
        }
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.spacing = 6
        stack.addArrangedSubview(row)

        effect.layoutSubtreeIfNeeded()
        let size = stack.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var origin = NSPoint(x: anchor.x - size.width / 2, y: anchor.y + 24)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(origin.y, visible.maxY - size.height - 8)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        itemID = nil
        panel.orderOut(nil)
        ActionTarget.shared.handlers.removeAll()
    }

    /// For debug snapshots: the card drawn into a bitmap.
    func snapshot() -> NSBitmapImageRep? {
        guard panel.isVisible, let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private func metaLine(_ item: Item, jarName: String) -> String {
        let kind: String
        switch item.kind {
        case .link: kind = item.url.flatMap(URL.init(string:)).map(Intake.displayHost) ?? L("kind.link")
        case .text: kind = L("kind.text")
        case .image: kind = L("kind.image")
        case .file: kind = item.byteSize.map { L("kind.fileSized", ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)) } ?? L("kind.file")
        }
        let days = Aging.days(since: item.addedAt)
        let age = days == 0 ? L("age.today") : L("age.days", days)
        return L("card.meta", kind, jarName, age)
    }

    private func label(_ text: String, font: NSFont, color: NSColor, lines: Int) -> NSTextField {
        let f = NSTextField(wrappingLabelWithString: text)
        f.font = font
        f.textColor = color
        f.maximumNumberOfLines = lines
        // Truncating in the line break mode would make it one line; wrap, and cut only the last line.
        f.lineBreakMode = .byWordWrapping
        f.cell?.truncatesLastVisibleLine = true
        f.preferredMaxLayoutWidth = Self.inner
        return f
    }
}

/// Buttons built in code need a target that outlives them.
/// One target for every control that runs a closure: the card's buttons and the menus' items.
/// Each control is looked up by identity when it fires.
final class ActionTarget: NSObject {
    static let shared = ActionTarget()
    var handlers: [ObjectIdentifier: () -> Void] = [:]
    @objc func fire(_ sender: NSObject) { handlers[ObjectIdentifier(sender)]?() }
}

/// A menu item that runs a closure. Menus are rebuilt each time they open, so the closure is
/// dropped again when the item goes.
final class MenuItem: NSMenuItem {
    convenience init(_ title: String, key: String = "", perform: @escaping () -> Void) {
        self.init(title: title, action: #selector(ActionTarget.fire(_:)), keyEquivalent: key)
        target = ActionTarget.shared
        ActionTarget.shared.handlers[ObjectIdentifier(self)] = perform
    }

    deinit { ActionTarget.shared.handlers[ObjectIdentifier(self)] = nil }
}
