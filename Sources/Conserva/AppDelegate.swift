import AppKit
import Carbon
import ConservaCore
import ServiceManagement
import SpriteKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, ShelfViewDelegate {
    private var model: ShelfModel!
    private var scene: ShelfScene!
    private var view: ShelfView!
    private var panel: ShelfPanel!
    private let card = ItemCard()
    private let sounds = SoundBoard()
    private var statusItem: NSStatusItem!
    private var hotKey: GlobalShortcut?
    private var mouseTimer: Timer?
    private var monitors: [Any] = []
    private var debug: Debug?

    private var revealed = false
    /// Opened on purpose (shortcut, menu, a drop): stays out until the pointer has visited and left.
    private var pinned = false
    private var hotZoneSince: Date?
    private var awaySince: Date?
    /// Something is being dragged in another app: the shelf may be wanted as a drop target.
    private var externalDrag = false
    /// Hidden jars put their tops out from their edge while that drag lasts, so it can be brought to them.
    private var peeking = false
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    /// A link was just copied: until this moment the jars look out from their edges, and one click on
    /// a jar puts the link in. Pushed far back once the pointer has brought the jars out.
    private var linkOffer: Date?
    private var clipboardCount = NSPasteboard.general.changeCount
    private static let offerLasts: TimeInterval = 4

    var soundsOn: Bool {
        get { UserDefaults.standard.object(forKey: "sounds") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sounds") }
    }

    /// The jars peek out when a link is copied anywhere. Only the clipboard's change count and
    /// whether it looks like an address are looked at; the address itself is read on the click.
    var peeksForLinks: Bool {
        get { UserDefaults.standard.object(forKey: "peeksForLinks") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "peeksForLinks") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Two copies on one shelf would both write shelf.json, last one wins, and only one could hold
        // the shortcut: the shelf's folder is claimed first, and if another copy holds it, that one is
        // brought forward instead. A scripted test instance has a folder of its own, so it runs beside.
        let store = ShelfStore()
        guard store.claim() else {
            if let bundleID = Bundle.main.bundleIdentifier {
                NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { $0 != .current }?.activate()
            }
            NSApp.terminate(nil)
            return
        }
        model = ShelfModel(store: store)
        model.onSaveFailed = { [weak self] error in self?.warnSaveFailed(error) }
        let size = ShelfPanel.screenUnderPointer()?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        view = ShelfView(frame: NSRect(origin: .zero, size: size))
        view.shelfDelegate = self
        scene = ShelfScene(model: model, size: size)
        view.presentScene(scene)
        panel = ShelfPanel(content: view)
        panel.fill(nil)
        view.isPaused = true

        scene.onSettled = { [weak self] thing in self?.showCard(for: thing) }
        scene.onSound = { [weak self] sound, volume, pan in
            self?.debug?.heard(sound, volume: volume, pan: pan)
            guard let self, self.soundsOn else { return }
            self.sounds.play(sound, volume: volume, pan: pan)
        }
        scene.onHidden = { [weak self] in
            guard let self, !self.revealed, !self.peeking else { return }
            Trace.log("panel out")
            self.panel.orderOut(nil)
            self.view.isPaused = true
            self.setTracking(fast: false)
        }
        card.onAction = { [weak self] action, id in self?.cardAction(action, id) }

        hotKey = GlobalShortcut(keyCode: kVK_ANSI_J, modifiers: controlKey | optionKey) { [weak self] in self?.toggle() }
        setUpStatusItem()
        watchDrags()
        startMouseTracking()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.placePanel() }
        }
        // The menu is rebuilt each time it opens and the card each time it is shown; the labels are
        // drawn once and redrawn here. The welcome note and the starter jars' names are stored data.
        NotificationCenter.default.addObserver(forName: Localization.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.card.hide()
                self?.scene.relabelJars()
            }
        }

        debug = Debug.fromEnvironment(app: self)
        if let debug {
            debug.start()
        } else if !UserDefaults.standard.bool(forKey: "welcomed") {
            UserDefaults.standard.set(true, forKey: "welcomed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.reveal(pinned: true) }
        }
        if let error = model.loadError { warnLoadFailed(error) }
    }

    // MARK: Showing and hiding

    private func placePanel() {
        panel.fill(revealed ? panel.screen : ShelfPanel.screenUnderPointer())
    }

    func reveal(pinned: Bool) {
        if pinned { self.pinned = true }
        awaySince = nil
        guard !revealed else { return }
        Trace.log("reveal pinned=\(pinned) peeking=\(peeking) panelVisible=\(panel.isVisible) viewPaused=\(view.isPaused) appActive=\(NSApp.isActive)")
        revealed = true
        peeking = false
        scene.setPeeking(false)
        setTracking(fast: true)
        placePanel()
        view.isPaused = false
        panel.orderFrontRegardless()
        scene.setRevealed(true)
    }

    func hide() {
        guard revealed else { return }
        Trace.log("hide shown=\(scene.debugShown)")
        revealed = false
        linkOffer = nil
        pinned = false
        card.hide()
        scene.setRevealed(false)
        panel.ignoresMouseEvents = true
        // The panel goes once every jar has slid off (`onHidden`).
    }

    @objc func toggle() {
        if revealed { hide() } else { reveal(pinned: true) }
    }

    /// The pointer is watched all day. While the jars are away it is looked at ten times a second,
    /// which is all the quarter-second edge delay needs and lets the process sleep between looks;
    /// while they are out, thirty, so passing the mouse through to what is under them keeps up.
    private func startMouseTracking() { setTracking(fast: false) }

    private func setTracking(fast: Bool) {
        let interval: TimeInterval = fast ? 1.0 / 30 : 1.0 / 10
        guard mouseTimer?.timeInterval != interval else { return }
        mouseTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval / 4
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    /// How long the pointer rests against the left edge before the jars come out.
    private static let revealDelay: TimeInterval = 0.25
    private static let retractDelay: TimeInterval = 2.0
    /// How close a dragged thing comes to a peeking jar before the jars come all the way out.
    private static let peekReach: CGFloat = 70

    /// The left edge of a screen: resting the pointer there brings the jars out.
    private func edgeZone(of screen: NSScreen) -> NSRect {
        let v = screen.visibleFrame
        return NSRect(x: screen.frame.minX, y: v.minY, width: 2, height: v.height)
    }

    private func tick() {
        let mouse = debugPointer ?? NSEvent.mouseLocation
        let now = Date()
        let mouseDown = NSEvent.pressedMouseButtons & 1 != 0 || debugMouseDown
        if externalDrag, !mouseDown { externalDrag = false }
        watchClipboard(now)

        guard revealed else {
            // Something picked up in another app: the jars look out from their edges, and come all the
            // way out when it is brought near. Let go anywhere else and they go back. A link just
            // copied does the same for a few seconds, and the pointer resting on a jar brings them out.
            let offering = linkOffer.map { now < $0 } ?? false
            if externalDrag || offering, !peeking { startPeeking() }
            if peeking, !externalDrag, !offering { stopPeeking(); linkOffer = nil }
            let reach = externalDrag ? Self.peekReach : 0
            if peeking, toScreen(scene.peekRects()).contains(where: { NSMouseInRect(mouse, $0.insetBy(dx: -reach, dy: -reach), false) }) {
                if offering { linkOffer = .distantFuture }
                reveal(pinned: false)
                return
            }
            // The panel is meant to go once the jars have slid off (`onHidden`), which needs a frame to
            // run; if none did, it would stay on screen, taking the mouse over nothing. Not left to chance.
            if !peeking, panel.isVisible, scene.debugShown == 0, scene.debugPeeked == 0 {
                Trace.log("panel left on screen while hidden: taken out")
                panel.orderOut(nil)
                view.isPaused = true
            }
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            if let screen, edgeZone(of: screen).insetBy(dx: -1, dy: 0).contains(mouse) {
                let since = hotZoneSince ?? now
                hotZoneSince = since
                if now.timeIntervalSince(since) >= Self.revealDelay {
                    hotZoneSince = nil
                    // Asked only now, not every tick: finding out costs a trip to the window server.
                    let fullScreen = FullScreen.isActive(on: screen)
                    Trace.log("edge held fullScreen=\(fullScreen) mouse=\(Int(mouse.x)),\(Int(mouse.y))")
                    if !fullScreen { reveal(pinned: false) }
                }
            } else {
                hotZoneSince = nil
            }
            return
        }

        updateMousePassThrough(mouse)
        // Its thing went back into a jar or away: the card goes too.
        if card.isShown, let id = card.itemID, scene.things[id]?.state != .out { card.hide() }

        // Near any jar, or over the card: the jars stay out.
        let nearJar = jarRectsOnScreen().contains { NSMouseInRect(mouse, $0.insetBy(dx: -50, dy: -50), false) }
        let inside = nearJar || (card.isShown && NSMouseInRect(mouse, card.frame.insetBy(dx: -20, dy: -20), false))
        if inside && pinned { pinned = false }
        // A scripted test run keeps the jars out, as the real pointer is somewhere else entirely,
        // unless it moves a pointer of its own.
        if debug != nil, debugPointer == nil { return }
        // A button held anywhere: something is about to be picked up, maybe for a jar.
        let busy = pinned || card.isShown || view.isInteracting || externalDrag || mouseDown
            || scene.thingsNotInAJar.contains { $0.state != .out }
        if inside || busy {
            awaySince = nil
        } else {
            let since = awaySince ?? now
            awaySince = since
            if now.timeIntervalSince(since) >= Self.retractDelay {
                awaySince = nil
                hide()
            }
        }
    }

    private func startPeeking() {
        Trace.log("peek start")
        peeking = true
        setTracking(fast: true)
        placePanel()
        view.isPaused = false
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        scene.setPeeking(true)
    }

    private func stopPeeking() {
        Trace.log("peek stop")
        peeking = false
        scene.setPeeking(false)
        // The panel goes once the jars are back past their edges (`onHidden`).
    }

    private func jarRectsOnScreen() -> [NSRect] { toScreen(scene.interactiveRects()) }

    /// Scene rects as screen rects.
    private func toScreen(_ rects: [CGRect]) -> [NSRect] {
        rects.map { r in
            let a = view.convert(scene.convertPoint(toView: r.origin), to: nil)
            let b = view.convert(scene.convertPoint(toView: CGPoint(x: r.maxX, y: r.maxY)), to: nil)
            let sa = panel.convertPoint(toScreen: a), sb = panel.convertPoint(toScreen: b)
            return NSRect(x: min(sa.x, sb.x), y: min(sa.y, sb.y), width: abs(sb.x - sa.x), height: abs(sb.y - sa.y))
        }
    }

    /// The panel only takes the mouse over the jars and what lies around them;
    /// everywhere else clicks go to whatever is underneath. Something carried in from another app
    /// is taken the same way: over a jar it can go in, anywhere else it lands on what is below.
    private func updateMousePassThrough(_ mouse: NSPoint) {
        if view.isInteracting, !view.dropping { panel.ignoresMouseEvents = false; return }
        let local = panel.convertPoint(fromScreen: mouse)
        let scenePoint = scene.convertPoint(fromView: view.convert(local, from: nil))
        let over = scene.interactiveRects().contains { $0.insetBy(dx: -6, dy: -6).contains(scenePoint) }
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
        // Carried off the jars: no jar stays lit, whether or not the drag says it left.
        if view.dropping, !over { scene.setHot(nil) }
    }

    /// A drag that started in another app: watched so the shelf can come out
    /// when it is carried to the left edge, and take the drop.
    private func watchDrags() {
        if let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.dragChangeCount = NSPasteboard(name: .drag).changeCount
                if self.card.isShown, !NSMouseInRect(NSEvent.mouseLocation, self.card.frame, false) { self.card.hide() }
            }
        }) { monitors.append(down) }
        if let dragged = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.externalDrag else { return }
                if NSPasteboard(name: .drag).changeCount != self.dragChangeCount { self.externalDrag = true }
            }
        }) { monitors.append(dragged) }
        if let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.externalDrag = false }
        }) { monitors.append(up) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.card.isShown, event.window !== self.card.window else { return }
                let p = self.view.convert(event.locationInWindow, from: nil)
                if case .out = self.scene.target(at: self.scene.convertPoint(fromView: p)) {} else { self.card.hide() }
            }
            return event
        }) { monitors.append(local) }
    }


    // MARK: The card

    private func showCard(for thing: Thing) {
        guard revealed, let jarID = model.jarID(holding: thing.id), let jar = model.jar(jarID) else { return }
        let scenePoint = scene.convert(thing.position, from: scene.world)
        let viewPoint = view.convert(scene.convertPoint(toView: scenePoint), to: nil)
        let screenPoint = panel.convertPoint(toScreen: viewPoint)
        let image: NSImage?
        switch thing.item.kind {
        case .image: image = model.fileURL(of: thing.item).flatMap(NSImage.init(contentsOf:))
        // A video shows its still on the card.
        case .link where thing.item.linkKind == .video: image = NSImage(contentsOf: model.store.previewURL(of: thing.item.id))
        default: image = nil
        }
        card.show(thing.item, jarName: jar.name, image: image, at: screenPoint)
    }

    private func cardAction(_ action: ItemCard.Action, _ id: UUID) {
        guard let thing = scene.things[id], let item = model.item(id) else { card.hide(); return }
        switch action {
        case .open:
            model.open(item)
        case .copy:
            model.copy(item)
            // Its own copy is no reason to peek.
            clipboardCount = NSPasteboard.general.changeCount
            card.hide()
        case .reveal:
            model.revealInFinder(item)
        case .delete:
            card.hide()
            scene.discard(thing)
        case .putBack:
            card.hide()
            scene.putBack(thing)
        }
    }

    // MARK: ShelfViewDelegate

    func shelfView(_ view: ShelfView, showCardFor thing: Thing) { showCard(for: thing) }

    func shelfView(_ view: ShelfView, rename rig: JarRig) { rename(rig.id) }

    func shelfViewPaste(_ view: ShelfView) { pasteClipboard(into: scene.activeRig?.id) }

    func shelfViewDismiss(_ view: ShelfView) { hide() }

    func shelfViewInteractionChanged(_ view: ShelfView) {
        if view.isInteracting { panel.ignoresMouseEvents = false }
    }

    func shelfView(_ view: ShelfView, menuFor target: ShelfScene.Target) -> NSMenu? {
        let menu = NSMenu()
        switch target {
        case .thing(let thing):
            menu.addItem(MenuItem(L("menu.takeOut")) { [weak self] in self?.scene.pull(thing) })
            if let rig = thing.rig { addJarItems(to: menu, rig: rig) }
        case .label(let rig), .jar(let rig, _), .lid(let rig):
            addJarItems(to: menu, rig: rig)
        case .out(let thing):
            for choice in ItemCard.actions(for: thing.item.kind) {
                menu.addItem(MenuItem(choice.title) { [weak self] in self?.cardAction(choice.action, thing.id) })
            }
        }
        return menu
    }

    private func addJarItems(to menu: NSMenu, rig: JarRig) {
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(MenuItem(L("menu.takeOutRandom")) { [weak self] in _ = self?.scene.pullRandom(from: rig) })
        menu.addItem(MenuItem(L("menu.pasteHere")) { [weak self] in self?.pasteClipboard(into: rig.id) })
        menu.addItem(MenuItem(rig.lid.isClosed ? L("menu.lidOpen") : L("menu.lidClose")) { [weak self] in self?.scene.toggleLid(rig) })
        menu.addItem(.separator())
        menu.addItem(MenuItem(L("menu.rename")) { [weak self] in self?.rename(rig.id) })
        let empty = MenuItem(L("menu.empty")) { [weak self] in self?.confirmEmpty(rig.id) }
        empty.isEnabled = !(model.jar(rig.id)?.items.isEmpty ?? true)
        menu.addItem(empty)
        let remove = MenuItem(L("menu.removeJar")) { [weak self] in self?.confirmRemove(rig.id) }
        remove.isEnabled = model.shelf.jars.count > 1
        menu.addItem(remove)
    }

    // MARK: Actions

    /// Notices a fresh copy and, if it looks like a link, offers the jars for it. The clipboard's
    /// contents are not read here: that would count as a paste the user never asked for.
    private func watchClipboard(_ now: Date) {
        let pasteboard = debugPasteboard ?? NSPasteboard.general
        let count = pasteboard.changeCount
        guard count != clipboardCount else { return }
        clipboardCount = count
        guard peeksForLinks, !revealed, !externalDrag else { return }
        Pasteboard.holdsLink(pasteboard) { [weak self] holds in
            guard let self, holds, self.clipboardCount == count, !self.revealed else { return }
            Trace.log("link copied: offering the jars")
            self.linkOffer = Date().addingTimeInterval(Self.offerLasts)
        }
    }

    /// A click on a jar brought out for a copied link puts the link in it.
    func shelfView(_ view: ShelfView, clicked rig: JarRig) {
        guard linkOffer != nil else { return }
        linkOffer = nil
        pasteClipboard(into: rig.id)
    }

    func pasteClipboard(into jarID: UUID?) {
        guard let jarID = jarID ?? scene.activeRig?.id else { return }
        let incoming = Pasteboard.incoming(from: debugPasteboard ?? .general)
        if incoming.isEmpty { NSSound.beep(); return }
        if !revealed { reveal(pinned: true) }
        if model.add(incoming, to: jarID) == 0 { NSSound.beep() }
    }

    func newJar() {
        guard model.shelf.jars.count < Shelf.maxJars else { NSSound.beep(); return }
        if !revealed { reveal(pinned: true) }
        guard let name = ask(L("newJar.title"), message: L("newJar.message"), value: L("newJar.default"), button: L("newJar.button")),
              let jar = model.addJar(named: name) else { return }
        scene.setActive(scene.rig(jar.id))
    }

    func rename(_ jarID: UUID) {
        guard let jar = model.jar(jarID),
              let name = ask(L("rename.title"), message: L("rename.message"), value: jar.name, button: L("rename.button")) else { return }
        model.rename(jarID, to: name)
    }

    private func confirmEmpty(_ jarID: UUID) {
        guard let jar = model.jar(jarID), confirm(L("empty.title", jar.name), L("empty.message", jar.items.count), button: L("empty.button")) else { return }
        model.emptyJar(jarID)
    }

    private func confirmRemove(_ jarID: UUID) {
        guard let jar = model.jar(jarID) else { return }
        if !jar.items.isEmpty, !confirm(L("remove.title", jar.name), L("remove.message", jar.items.count), button: L("remove.button")) { return }
        model.removeJar(jarID)
    }

    private func ask(_ title: String, message: String, value: String, button: String) -> String? {
        pinned = true
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: L("cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.icon = NSApp.applicationIconImage
        NSApp.activate(ignoringOtherApps: true)
        defer { pinned = true }
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return Shelf.cleanName(field.stringValue)
    }

    /// The shelf on disk could not be read: say so, as this run shows a stand-in and saves nothing.
    private func warnLoadFailed(_ error: Error) {
        let message = L("load.failed.message", model.store.home.path, error.localizedDescription)
        if debug != nil { NSLog("Conserva: would warn: \(message)"); return }
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = L("load.failed.title")
            alert.informativeText = message
            alert.alertStyle = .critical
            alert.addButton(withTitle: L("load.failed.button"))
            alert.runModal()
        }
    }

    /// The shelf could not be written: say so, as things put in now may be gone after a restart.
    private func warnSaveFailed(_ error: Error) {
        let message = L("save.failed.message", model.store.home.path, error.localizedDescription)
        // A scripted test run must not stop at a dialog.
        if debug != nil { NSLog("Conserva: would warn: \(message)"); return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pinned = true
            let alert = NSAlert()
            alert.messageText = L("save.failed.title")
            alert.informativeText = message
            alert.alertStyle = .critical
            alert.addButton(withTitle: L("save.failed.button"))
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func confirm(_ title: String, _ message: String, button: String) -> Bool {
        pinned = true
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: L("cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = JarArt.statusIcon()
        statusItem.button?.setAccessibilityLabel("Conserva")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let show = MenuItem(revealed ? L("menu.hide") : L("menu.show")) { [weak self] in self?.toggle() }
        show.keyEquivalent = "j"
        show.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(show)

        let paste = NSMenuItem(title: L("menu.pasteInto"), action: nil, keyEquivalent: "")
        let jars = NSMenu()
        for jar in model.shelf.jars {
            jars.addItem(MenuItem(jar.name) { [weak self] in self?.pasteClipboard(into: jar.id) })
        }
        paste.submenu = jars
        // Only the types on offer are looked at: reading the clipboard itself here would count as a
        // paste the user did not ask for, and newer systems say so on screen.
        paste.isEnabled = Pasteboard.canRead(.general)
        menu.addItem(paste)

        let new = MenuItem(L("menu.newJar")) { [weak self] in self?.newJar() }
        new.isEnabled = model.shelf.jars.count < Shelf.maxJars
        menu.addItem(new)
        menu.addItem(.separator())

        let titles = MenuItem(L("menu.fetchTitles")) { [weak self] in self?.model.fetchesTitles.toggle() }
        titles.state = model.fetchesTitles ? .on : .off
        titles.toolTip = L("menu.fetchTitles.help")
        menu.addItem(titles)
        let sounds = MenuItem(L("menu.sounds")) { [weak self] in self?.soundsOn.toggle() }
        sounds.state = soundsOn ? .on : .off
        menu.addItem(sounds)
        let peeks = MenuItem(L("menu.peekLinks")) { [weak self] in self?.peeksForLinks.toggle() }
        peeks.state = peeksForLinks ? .on : .off
        peeks.toolTip = L("menu.peekLinks.help")
        menu.addItem(peeks)
        menu.addItem(dustMenuItem())
        menu.addItem(languageMenuItem())
        let login = MenuItem(L("menu.login")) { AppDelegate.toggleLaunchAtLogin() }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(MenuItem(L("menu.openFolder")) { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.model.store.home)
        })
        menu.addItem(.separator())
        menu.addItem(MenuItem(L("menu.quit"), key: "q") { NSApp.terminate(nil) })
    }

    /// How soon jars gather dust: a few usual spans, any number of days, or never.
    private func dustMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: L("menu.dust"), action: nil, keyEquivalent: "")
        item.toolTip = L("menu.dust.help")
        let days = model.dustAfterDays
        let spans = NSMenu()
        var shown = false
        for (title, value) in [(L("menu.dust.days3"), 3), (L("menu.dust.week"), 7), (L("menu.dust.twoWeeks"), 14), (L("menu.dust.month"), 30)] {
            let choice = MenuItem(title) { [weak self] in self?.model.dustAfterDays = value }
            choice.state = days == value ? .on : .off
            shown = shown || days == value
            spans.addItem(choice)
        }
        if !shown, days > 0 {
            let own = MenuItem(L("menu.dust.custom", days)) {}
            own.state = .on
            spans.addItem(own)
        }
        spans.addItem(MenuItem(L("menu.dust.other")) { [weak self] in self?.askDustDays() })
        spans.addItem(.separator())
        let never = MenuItem(L("menu.dust.never")) { [weak self] in self?.model.dustAfterDays = 0 }
        never.state = days <= 0 ? .on : .off
        spans.addItem(never)
        item.submenu = spans
        return item
    }

    private func languageMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: L("menu.language"), action: nil, keyEquivalent: "")
        let languages = NSMenu()
        for language in Localization.supported {
            let choice = MenuItem(language.name) { Localization.set(language.code) }
            choice.state = language.code == Localization.code ? .on : .off
            languages.addItem(choice)
        }
        item.submenu = languages
        return item
    }

    private func askDustDays() {
        let current = model.dustAfterDays > 0 ? model.dustAfterDays : Dust.defaultDays
        guard let answer = ask(L("dust.ask.title"), message: L("dust.ask.message"), value: String(current), button: L("dust.ask.ok")),
              let days = Int(answer), (1...365).contains(days) else { return }
        model.dustAfterDays = days
    }

    private static func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = L("login.error.title")
            alert.informativeText = L("login.error.message")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: For Debug

    var debugScene: ShelfScene { scene }
    /// A pointer of the test's own, in screen points, used instead of the real one while set.
    var debugPointer: NSPoint?
    /// The left button held, as far as the shelf can tell.
    var debugMouseDown = false
    /// A clipboard of the test's own, read instead of the real one while set.
    var debugPasteboard: NSPasteboard?

    /// A click on a jar's middle as the window server would deliver it, then where keys would go.
    func debugClickJar(_ index: Int) -> String {
        guard let screenPoint = debugJarCenter(index) else { return "no such jar" }
        let p = panel.convertPoint(fromScreen: screenPoint)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                panel.sendEvent(e)
            }
        }
        return "panel key: \(panel.isKeyWindow), app active: \(NSApp.isActive), first responder is the shelf: \(panel.firstResponder === view), active jar: \(scene.activeRig?.name ?? "none")"
    }

    /// A key with modifiers sent to the app as the system would, to whichever window is key.
    func debugKey(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: panel.windowNumber, context: nil, characters: characters,
                                       charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode) else { return }
        NSApp.sendEvent(e)
    }
    var debugRevealed: Bool { revealed }
    var debugPeeking: Bool { peeking }
    var debugPanelShown: Bool { panel.isVisible }
    var debugPanelTakesMouse: Bool { !panel.ignoresMouseEvents }

    /// Something picked up in another app and carried about (on), or let go (off).
    /// The middle of what shows of jar n while the jars peek, in screen points; nil if nothing shows.
    func debugPeekCenter(_ index: Int) -> NSPoint? {
        let rects = toScreen(scene.peekRects())
        guard rects.indices.contains(index) else { return nil }
        return NSPoint(x: rects[index].midX, y: rects[index].midY)
    }

    func debugExternalDrag(_ on: Bool) {
        debugMouseDown = on
        externalDrag = on
    }

    /// The middle of a jar as drawn right now, in screen points.
    func debugJarCenter(_ index: Int) -> NSPoint? {
        guard index < scene.rigs.count else { return nil }
        let p = scene.convert(scene.rigs[index].node.position, from: scene.world)
        let v = view.convert(scene.convertPoint(toView: p), to: nil)
        return panel.convertPoint(toScreen: v)
    }

    /// A point on the left edge of the panel's screen, halfway up.
    var debugLeftEdge: NSPoint {
        let f = (panel.screen ?? NSScreen.main!).frame
        return NSPoint(x: f.minX + 0.5, y: f.midY)
    }
    var debugView: ShelfView { view }
    var debugModel: ShelfModel { model }
    var debugCard: ItemCard { card }
}
