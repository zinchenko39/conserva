import AppKit
import ConservaCore
import SpriteKit

/// The jars wherever they were left on the screen, everything in them, and
/// everything taken out of them. Owns the motion; the model owns the data.
final class ShelfScene: SKScene, SKPhysicsContactDelegate {
    let model: ShelfModel

    /// On-screen size of a jar compared with its design box.
    static let jarScale: CGFloat = 0.62
    static let gap: CGFloat = 18
    static let margin: CGFloat = 22
    let floorY: CGFloat = 6

    /// Gravity inside a jar and for things taken out, in design units per second².
    private let gravity: CGFloat = 1500
    /// The most a shake can feel like, in multiples of gravity; also keeps the simulation sane.
    private let maxG: CGFloat = 6
    private let maxSpeed: CGFloat = 950
    /// How much bigger a thing in a jar is shown while the pointer rests on it, so it can be read.
    static let hoverScale: CGFloat = 1.9
    /// Seconds it takes to come up to that size, and to go back.
    private static let hoverDuration: CGFloat = 0.35

    /// All jars and loose things, in screen points.
    let world = SKNode()
    /// The jars' contents' physics boxes, out of sight.
    private let labRoot = SKNode()

    private(set) var rigs: [JarRig] = []
    private(set) var things: [UUID: Thing] = [:]
    private(set) var revealed = false
    /// 0 hidden, 1 shown; the jars slide between the two.
    private var shown: CGFloat = 0
    /// Hidden jars put their tops out from their edge while something is dragged in another app.
    private(set) var peeking = false
    /// 0 hidden, 1 peeking.
    private var peeked: CGFloat = 0
    private var lastTime: TimeInterval = 0
    private var time: TimeInterval = 0
    private var laidOutFor = CGSize.zero
    private var lastClink: TimeInterval = 0

    private let backTexture = JarArt.back()
    private let frontTexture = JarArt.front()
    private let outlineTexture = JarArt.dropOutline()
    private let lidTexture = JarArt.lid()
    private let leverTexture = JarArt.lever()
    private let hingeTexture = JarArt.hingeFront()
    private let shadowTexture = JarArt.floorShadow()
    private var thumbnails: [UUID: CGImage] = [:]
    private var linkImages: [String: CGImage] = [:]

    /// A thing came out and came to rest: time to show its card.
    var onSettled: ((Thing) -> Void)?
    var onActiveJarChanged: ((UUID) -> Void)?
    /// A sound, its volume, and where it happened across the screen, -1 at the left edge to 1 at the right.
    var onSound: ((Sound, Float, Float) -> Void)?
    /// Every jar has slid off the screen.
    var onHidden: (() -> Void)?

    private(set) var activeJarID: UUID?
    private var hotRig: JarRig?
    private var hovered: Thing?

    init(model: ShelfModel, size: CGSize) {
        self.model = model
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        anchorPoint = .zero
        // Only the jars feel the world's gravity; their contents get theirs from `update`.
        // SpriteKit counts 150 points to the metre.
        physicsWorld.gravity = CGVector(dx: 0, dy: -gravity * Self.jarScale / 150)
        physicsWorld.contactDelegate = self
        addChild(world)
        labRoot.alpha = 0
        labRoot.position = CGPoint(x: -20_000, y: -20_000)
        addChild(labRoot)
        for jar in model.shelf.jars { addRig(for: jar) }
        activeJarID = rigs.first?.id
        model.onItemsAdded = { [weak self] jarID, items, point in self?.receive(items, into: jarID, from: point) }
        model.onItemChanged = { [weak self] item in self?.refresh(item) }
        model.onJarsChanged = { [weak self] in self?.syncJars() }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    private var visibleJarWidth: CGFloat { (JarGeometry.outerRight - JarGeometry.outerLeft) * Self.jarScale }
    private var standY: CGFloat { floorY + (JarGeometry.bottomY - JarGeometry.pivot.y) * Self.jarScale }

    /// Where a jar nobody has moved stands: in a row from the bottom left.
    private func slot(_ i: Int) -> CGPoint {
        CGPoint(x: Self.margin + CGFloat(i) * (visibleJarWidth + Self.gap) + visibleJarWidth / 2, y: standY)
    }

    private func spot(for jar: Jar, index: Int) -> CGPoint {
        guard let place = jar.place else { return slot(index) }
        let half = visibleJarWidth / 2
        return CGPoint(x: clamp(CGFloat(place.x) * size.width, half, size.width - half),
                       y: clamp(CGFloat(place.y) * size.height, standY, size.height - standY))
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // The bottom of the screen is the floor the jars stand on; the sides and top keep them on screen.
        let edge = SKPhysicsBody(edgeLoopFrom: CGRect(x: 0, y: floorY, width: size.width, height: size.height - floorY))
        edge.friction = 0.7
        edge.restitution = 0.1
        edge.categoryBitMask = Category.screenEdge
        edge.collisionBitMask = 0
        physicsBody = edge
        layOutIfNeeded()
    }

    /// Puts every jar where it was left, once the scene knows the screen it is on.
    private func layOutIfNeeded() {
        guard size.width > visibleJarWidth * 2, size != laidOutFor else { return }
        laidOutFor = size
        for (i, rig) in rigs.enumerated() {
            guard let jar = model.jar(rig.id) else { continue }
            rig.teleport(to: spot(for: jar, index: i))
        }
        computeHideOffsets()
    }

    private func addRig(for jar: Jar) {
        let rig = JarRig(id: jar.id, name: jar.name, scale: Self.jarScale, back: backTexture, front: frontTexture,
                         outline: outlineTexture, lidTexture: lidTexture, leverTexture: leverTexture, hingeTexture: hingeTexture,
                         shadowTexture: shadowTexture)
        let index = rigs.count
        rigs.append(rig)
        world.addChild(rig.body)
        world.addChild(rig.shadow)
        world.addChild(rig.node)
        labRoot.addChild(rig.lab)
        relabelLabs()
        rig.teleport(to: size.width > visibleJarWidth * 2 ? spot(for: jar, index: index) : slot(index))

        // Settled from the start: things go to resting spots, the rest wait underneath.
        let loose = Array(jar.items.suffix(JarGeometry.maxLoose))
        let spots = JarGeometry.restingSpots(for: loose.map { JarGeometry.size(of: $0) })
        for (item, spot) in zip(loose, spots) {
            let thing = makeThing(item, rig: rig)
            putLoose(thing, in: rig, at: JarGeometry.local(spot), angle: CGFloat.random(in: -0.08...0.08), velocity: .zero)
        }
        // Older than those, then any that found no room: the last of them comes up first.
        for item in jar.items.dropLast(loose.count) + loose.dropFirst(spots.count) {
            let thing = makeThing(item, rig: rig)
            thing.state = .waiting
            rig.waiting.append(thing)
        }
        updateLabel(rig)
    }

    /// Each jar's contents get a box of their own, far from the others.
    private func relabelLabs() {
        for (i, r) in rigs.enumerated() { r.lab.position = CGPoint(x: CGFloat(i) * 900, y: 0) }
    }

    private func removeRig(_ rig: JarRig) {
        [rig.body, rig.node, rig.shadow, rig.lab].forEach { $0.removeFromParent() }
        for thing in things.values where thing.rig === rig {
            thing.sprite.removeFromParent()
            things[thing.id] = nil
            forgetImages(of: thing.id)
        }
    }

    /// The model's jars changed: added, renamed, removed or emptied.
    private func syncJars() {
        let jars = model.shelf.jars
        for rig in rigs where !jars.contains(where: { $0.id == rig.id }) { removeRig(rig) }
        rigs.removeAll { r in !jars.contains { $0.id == r.id } }
        for jar in jars {
            if let rig = rigs.first(where: { $0.id == jar.id }) {
                rig.name = jar.name
                let ids = Set(jar.items.map(\.id))
                for thing in things.values where thing.rig === rig && !ids.contains(thing.id) { dispose(thing) }
                rig.waiting.removeAll { !ids.contains($0.id) }
                rig.shownCount = -1
                updateLabel(rig)
            } else {
                addRig(for: jar)
                if let rig = rigs.last { arrive(rig) }
            }
        }
        rigs.sort { a, b in (jars.firstIndex { $0.id == a.id } ?? 0) < (jars.firstIndex { $0.id == b.id } ?? 0) }
        relabelLabs()
        if activeJarID == nil || !rigs.contains(where: { $0.id == activeJarID }) { setActive(rigs.first) }
    }

    /// A new jar drops in from the top over the first free spot along the bottom.
    private func arrive(_ rig: JarRig) {
        let others = rigs.filter { $0 !== rig }
        var target = CGPoint(x: size.width / 2, y: standY)
        for i in 0..<(Shelf.maxJars + 2) {
            let s = slot(i)
            if s.x + visibleJarWidth / 2 > size.width { break }
            let taken = others.contains { abs($0.position.x - s.x) < visibleJarWidth + Self.gap / 2 && abs($0.position.y - s.y) < 200 }
            if !taken { target = s; break }
        }
        rig.teleport(to: CGPoint(x: target.x, y: size.height - 170))
        rig.placeDirty = true
        rig.hideOffset = .zero
    }

    func setActive(_ rig: JarRig?) {
        guard let rig, activeJarID != rig.id else { return }
        activeJarID = rig.id
        onActiveJarChanged?(rig.id)
    }

    var activeRig: JarRig? { rigs.first { $0.id == activeJarID } ?? rigs.first }

    func rig(_ id: UUID) -> JarRig? { rigs.first { $0.id == id } }

    // MARK: Things

    private func makeThing(_ item: Item, rig: JarRig) -> Thing {
        let thing = Thing(item: item, texture: texture(for: item))
        thing.rig = rig
        things[item.id] = thing
        return thing
    }

    private func look(_ item: Item) -> JarArt.Look {
        let url = item.url.flatMap(URL.init(string:))
        return JarArt.Look(kind: item.kind, title: item.title,
                           host: url.map(Intake.displayHost),
                           fileExtension: (item.originalName as NSString?)?.pathExtension,
                           thumbnail: thumbnail(item), aged: Aging.yellowing(since: item.addedAt),
                           link: item.linkKind, icon: linkImage(item, model.store.iconURL(of: item.id)),
                           preview: item.linkKind == .video ? linkImage(item, model.store.previewURL(of: item.id)) : nil,
                           repository: url.flatMap(LinkKind.repository))
    }

    /// A link's icon or still, read once from the previews folder; nil until it has been fetched.
    private func linkImage(_ item: Item, _ url: URL) -> CGImage? {
        let key = url.lastPathComponent
        if let cached = linkImages[key] { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        linkImages[key] = image
        return image
    }

    private func texture(for item: Item) -> SKTexture {
        JarArt.thing(look(item))
    }

    private func thumbnail(_ item: Item) -> CGImage? {
        guard item.kind == .image else { return nil }
        if let cached = thumbnails[item.id] { return cached }
        guard let url = model.fileURL(of: item),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 360,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        thumbnails[item.id] = image
        return image
    }

    /// Redraws a thing whose title arrived.
    func refresh(_ item: Item) {
        guard let thing = things[item.id] else { return }
        thing.item = item
        // Its icon or still may just have arrived.
        linkImages = linkImages.filter { !$0.key.hasPrefix(item.id.uuidString) }
        thing.sprite.texture = texture(for: item)
    }

    private func putLoose(_ thing: Thing, in rig: JarRig, at local: CGPoint, angle: CGFloat, velocity: CGVector) {
        thing.state = .loose
        thing.rig = rig
        thing.sprite.removeFromParent()
        rig.contents.addChild(thing.sprite)
        thing.sprite.position = local
        thing.sprite.zRotation = angle
        thing.sprite.setScale(1)
        thing.sprite.zPosition = 0
        let proxy = SKNode()
        proxy.position = local
        proxy.zRotation = angle
        // Paper, card and thin plastic: no bounce, a good grip on each other, slowed by the air so a
        // thing floats down to the pile instead of hitting it. The corners are cut off so one slides
        // over another's edge rather than catching on it. No continuous collision detection between
        // things: Box2D stops a "bullet" dead at the moment it touches another body, which jolts a
        // pile every time something lands or shifts, and nothing here moves far enough in a frame to
        // pass through a neighbour; against the glass, which is static, it still applies.
        let body = SKPhysicsBody(polygonFrom: Self.chamfered(thing.size))
        body.affectedByGravity = false
        body.friction = 0.35
        body.restitution = 0.02
        body.linearDamping = 2.2
        body.angularDamping = 1.6
        body.density = 1
        body.usesPreciseCollisionDetection = false
        body.categoryBitMask = Category.contents
        body.collisionBitMask = Category.contents | Category.glass
        body.contactTestBitMask = 0
        body.velocity = velocity
        proxy.physicsBody = body
        rig.lab.addChild(proxy)
        thing.proxy = proxy
    }

    /// A thing's outline for the physics: its rectangle with the corners cut off.
    private static func chamfered(_ size: CGSize) -> CGPath {
        let w = size.width / 2, h = size.height / 2, c = min(6, h / 3)
        let path = CGMutablePath()
        path.addLines(between: [CGPoint(x: -w + c, y: -h), CGPoint(x: w - c, y: -h), CGPoint(x: w, y: -h + c), CGPoint(x: w, y: h - c),
                                CGPoint(x: w - c, y: h), CGPoint(x: -w + c, y: h), CGPoint(x: -w, y: h - c), CGPoint(x: -w, y: -h + c)])
        path.closeSubpath()
        return path
    }

    private func dropProxy(_ thing: Thing) {
        thing.proxy?.removeFromParent()
        thing.proxy = nil
    }

    private func dispose(_ thing: Thing) {
        dropProxy(thing)
        thing.sprite.removeFromParent()
        thing.state = .gone
        things[thing.id] = nil
        forgetImages(of: thing.id)
    }

    /// The decoded pictures kept for a thing's texture go when the thing does, or the caches would
    /// only ever grow. Not on pulling out or putting back: the texture is reused on re-entry.
    private func forgetImages(of id: UUID) {
        thumbnails[id] = nil
        let prefix = id.uuidString
        linkImages = linkImages.filter { !$0.key.hasPrefix(prefix) }
    }

    /// The language changed: every label says "empty" or the count anew.
    func relabelJars() {
        for rig in rigs {
            rig.shownCount = -1
            updateLabel(rig)
        }
    }

    private func updateLabel(_ rig: JarRig) {
        let n = (model.jar(rig.id)?.items.count) ?? 0
        guard n != rig.shownCount || rig.labelSprite.texture == nil else { return }
        rig.shownCount = n
        let count = n == 0 ? L("label.empty") : L("label.count", n)
        rig.labelSprite.texture = JarArt.label(name: rig.name, count: count)
        rig.labelSprite.size = JarArt.labelSize
    }

    // MARK: In and out

    /// New things from the model: they fly in from where they were dropped, or from above the jar.
    private func receive(_ items: [Item], into jarID: UUID, from point: CGPoint?) {
        guard let rig = rig(jarID) else { return }
        for (i, item) in items.enumerated() {
            let thing = makeThing(item, rig: rig)
            var start = point.map { world.convert($0, from: self) } ?? rig.designToWorld(x: 150, y: -260)
            start.y = min(start.y, size.height - 20)
            thing.position = CGPoint(x: start.x + CGFloat(i) * 14, y: start.y + CGFloat(i) * 10)
            thing.angle = -0.25
            world.addChild(thing.sprite)
            thing.sprite.setScale(Self.jarScale)
            fly(thing, into: rig, delay: Double(i) * 0.12)
        }
        setActive(rig)
    }

    private func fly(_ thing: Thing, into rig: JarRig, delay: Double = 0) {
        thing.rig = rig
        thing.state = .flying
        thing.t = CGFloat(-delay / 0.55)
        thing.queued = 0
        thing.start = thing.position
        thing.startAngle = thing.angle
        thing.settled = false
        if thing.sprite.parent !== world {
            thing.sprite.removeFromParent()
            world.addChild(thing.sprite)
            thing.sprite.setScale(Self.jarScale)
        }
        thing.sprite.zPosition = 40
        openLid(rig)
    }

    /// Takes one thing out through the neck. The lid opens if it is shut, and stays open for the next one.
    func pull(_ thing: Thing) {
        guard thing.state == .loose, let rig = thing.rig, let proxy = thing.proxy else { return }
        thing.start = proxy.position
        thing.startAngle = proxy.zRotation
        thing.position = proxy.position
        thing.angle = proxy.zRotation
        dropProxy(thing)
        thing.state = .pulling
        thing.phase = 0
        thing.t = 0
        thing.sprite.zPosition = 10
        setHover(nil)
        openLid(rig)
        promoteWaiting(in: rig)
        model.markTaken(from: rig.id)
        setActive(rig)
    }

    func pullRandom(from rig: JarRig) -> Bool {
        let loose = things.values.filter { $0.rig === rig && $0.state == .loose }
        guard let pick = loose.randomElement() else { return false }
        pull(pick)
        return true
    }

    /// Back into its jar.
    func putBack(_ thing: Thing) {
        guard thing.state == .out, let rig = thing.rig else { return }
        fly(thing, into: rig)
    }

    /// Done with it: it crumples away and leaves the shelf.
    func discard(_ thing: Thing) {
        thing.state = .gone
        let id = thing.id
        thing.sprite.run(.group([.scale(to: 0.1, duration: 0.3), .fadeOut(withDuration: 0.3), .rotate(byAngle: 1.2, duration: 0.3)])) { [weak self] in
            thing.sprite.removeFromParent()
            self?.things[id] = nil
            self?.forgetImages(of: id)
        }
        model.discard(id)
        if let rig = thing.rig { updateLabel(rig) }
    }

    /// Everything taken out goes back where it came from.
    func collectAll() {
        for thing in things.values where thing.state == .out { putBack(thing) }
    }

    /// Everything not sitting in a jar: lying out, on its way out, or on its way in.
    var thingsNotInAJar: [Thing] { things.values.filter { $0.state == .out || $0.state == .pulling || $0.state == .flying } }

    private func promoteWaiting(in rig: JarRig) {
        let loose = things.values.filter { $0.rig === rig && $0.state == .loose }.count
        guard loose < JarGeometry.maxLoose, !rig.waiting.isEmpty else { return }
        let next = rig.waiting.removeLast()
        putLoose(next, in: rig, at: JarGeometry.local(x: 150, y: 250), angle: 0, velocity: CGVector(dx: 0, dy: -60))
    }

    // MARK: Lid

    /// Lets the lever go and swings the lid back. It stays open until closed.
    func openLid(_ rig: JarRig) {
        switch rig.lid {
        case .closed:
            rig.lid = .opening(0)
            sound(.leverRelease, 0.45, at: rig)
        // Caught on its way down: it swings back from where it is. Once it has landed and sealed, it
        // starts from just under the lever's share, so the unsealing step is crossed again.
        case .closing(let p): rig.lid = .opening(rig.sealed ? min(1 - p, Self.leverShare - 0.01) : max(Self.leverShare, 1 - p))
        case .held(let a): rig.lid = .opening(progress(showing: a, closing: false))
        default: break
        }
    }

    func closeLid(_ rig: JarRig) {
        switch rig.lid {
        case .open: rig.lid = .closing(0)
        case .opening(let p): rig.lid = .closing(min(0.7, 1 - p))
        case .held(let a): rig.lid = .closing(progress(showing: a, closing: true))
        default: break
        }
    }

    func toggleLid(_ rig: JarRig) {
        switch rig.lid {
        case .closed, .closing: openLid(rig)
        case .open, .opening, .held: closeLid(rig)
        }
    }

    // MARK: The lid by hand

    /// Takes hold of the open lid where the pointer is. False when it is shut, or the lever
    /// has already clamped it: then the drag tilts the jar instead.
    func grabLid(_ rig: JarRig, at scenePoint: CGPoint) -> Bool {
        guard !rig.lid.isClosed, !rig.sealed else { return false }
        let a = rig.lidSprite.zRotation
        rig.lidGrip = a - angleAroundHinge(rig, scenePoint)
        rig.lidSwing = 0
        lidDragTime = time
        rig.lid = .held(a)
        setHover(nil)
        setActive(rig)
        return true
    }

    /// Swings the held lid on its hinge after the pointer, between shut and fully open.
    func dragLid(_ rig: JarRig, to scenePoint: CGPoint) {
        guard case .held(let a) = rig.lid else { return }
        let target = angleAroundHinge(rig, scenePoint) + rig.lidGrip
        let next = clamp(a + wrap(target - a), 0, JarGeometry.lidOpenAngle)
        let dt = max(CGFloat(time - lidDragTime), 1.0 / 240)
        lidDragTime = time
        // Smoothed a little, so one jittery event does not decide a flick.
        rig.lidSwing = lerp(rig.lidSwing, (next - a) / dt, 0.7)
        rig.lid = .held(next)
    }

    /// Let go of the lid: pushed most of the way down, or flicked down, it swings shut and the
    /// lever snaps; otherwise it falls back open against its hinge.
    func releaseLid(_ rig: JarRig) {
        guard case .held(let a) = rig.lid else { return }
        // A hand that stopped before letting go has not flicked it.
        let swing = time - lidDragTime > 0.1 ? 0 : rig.lidSwing
        let shuts = a < JarGeometry.lidOpenAngle * 0.45 || swing < -4
        if shuts { closeLid(rig) } else { openLid(rig) }
    }

    private var lidDragTime: TimeInterval = 0

    /// The pointer's angle around the lid's hinge, in the jar's frame: 0 towards the lever, as the shut lid lies.
    private func angleAroundHinge(_ rig: JarRig, _ scenePoint: CGPoint) -> CGFloat {
        let p = rig.toLocal(world.convert(scenePoint, from: self))
        let hinge = JarGeometry.local(JarGeometry.lidHinge)
        return atan2(p.y - hinge.y, p.x - hinge.x)
    }

    /// Where in opening or closing the lid stands at this angle, so letting go of it carries on
    /// from there instead of jumping. Both swings are monotonic over the part searched.
    private func progress(showing angle: CGFloat, closing: Bool) -> CGFloat {
        let share = Self.leverShare
        // Opening is searched only up to where its overshoot peaks.
        var lo: CGFloat = closing ? 0 : share, hi: CGFloat = closing ? 1 - share : share + 0.6 * (1 - share)
        for _ in 0..<30 {
            let mid = (lo + hi) / 2
            let shown = lidPose(closing ? .closing(mid) : .opening(mid)).lid
            // Closing lowers the lid as it goes on; opening raises it.
            if (shown > angle) == closing { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// The lever takes the first part of opening, the lid the rest; closing is the reverse.
    private static let leverShare: CGFloat = 0.3
    private static let leverOpenAngle: CGFloat = 2.2
    /// Seconds for the whole of opening and of closing: slow enough to see a heavy glass lid swing.
    private static let openDuration: CGFloat = 1.0
    private static let closeDuration: CGFloat = 0.85
    /// How far into opening the lid has swung clear of the mouth, so things need not wait
    /// for it to finish settling against its hinge.
    private static let clearOfMouth: CGFloat = 0.7

    /// The lid is off and the contents are pulled towards the mouth: the jar is tipped or turned over.
    private func isPouring(_ rig: JarRig) -> Bool {
        !rig.sealed && rig.felt.dy > gravity * 0.3
    }

    private func lidLetsThrough(_ rig: JarRig) -> Bool {
        switch rig.lid {
        case .open: return true
        case .opening(let p): return p >= Self.clearOfMouth
        case .held(let a): return a > JarGeometry.lidOpenAngle * 0.6
        default: return false
        }
    }

    private func stepLid(_ rig: JarRig, _ dt: CGFloat) {
        switch rig.lid {
        case .closed, .open, .held:
            break
        case .opening(let p0):
            let p = min(1, p0 + dt / Self.openDuration)
            if p0 < Self.leverShare, p >= Self.leverShare {
                rig.setSealed(false)
                sound(.sealPop, 0.5, at: rig)
            }
            if p >= 1 { sound(.lidRest, 0.25, at: rig) }
            rig.lid = p >= 1 ? .open : .opening(p)
        case .closing(let p0):
            let p = min(1, p0 + dt / Self.closeDuration)
            let latch = 1 - Self.leverShare
            if p0 < latch, p >= latch {
                // Anything sitting in the mouth is nudged down before the lid comes down on it.
                for thing in things.values where thing.rig === rig && thing.state == .loose {
                    if let proxy = thing.proxy, proxy.position.y > JarGeometry.local(x: 150, y: 70).y {
                        proxy.position = JarGeometry.local(x: 150, y: 120)
                        proxy.physicsBody?.velocity = .zero
                    }
                }
                rig.setSealed(true)
                sound(.lidLand(pitch: pitch(of: rig)), 0.5, at: rig)
            }
            if p >= 1 { sound(.leverClamp(pitch: pitch(of: rig)), 0.55, at: rig) }
            rig.lid = p >= 1 ? .closed : .closing(p)
        }
    }

    /// Lid and lever angles for the current state.
    private func renderLid(_ rig: JarRig) {
        let pose = lidPose(rig.lid)
        rig.lidSprite.zRotation = pose.lid
        rig.leverSprite.zRotation = pose.lever
    }

    /// Lid and lever angles for a state of the lid.
    private func lidPose(_ state: JarRig.Lid) -> (lid: CGFloat, lever: CGFloat) {
        let open = JarGeometry.lidOpenAngle, leverOpen = Self.leverOpenAngle, share = Self.leverShare
        switch state {
        case .closed:
            return (0, 0)
        case .open:
            return (open, leverOpen)
        case .held(let a):
            return (a, leverOpen)
        case .opening(let p):
            return (open * swingOpen(max(0, (p - share) / (1 - share))), leverOpen * ease(min(1, p / share)))
        case .closing(let p):
            let latch = 1 - share
            return (open * (1 - swingShut(min(1, p / latch))), leverOpen * (1 - ease(max(0, (p - latch) / share))))
        }
    }

    // MARK: The jar moving

    /// The hand on a held jar: a spring towards where the hand is, with a limit
    /// on how hard it pulls, plus enough lift to cancel gravity. Applied as an
    /// acceleration rather than a set speed, so a jar pushed into another
    /// shoves it like an equal weight would, instead of launching it.
    private func drive(_ rig: JarRig, _ dt: CGFloat) {
        let b = rig.physics
        let lift = gravity * Self.jarScale
        func pull(towards target: CGPoint, stiffness k: CGFloat, damping c: CGFloat) {
            var a = CGVector(dx: (target.x - rig.position.x) * k - b.velocity.dx * c,
                             dy: (target.y - rig.position.y) * k - b.velocity.dy * c)
            a = limit(a, 9000)
            b.velocity = CGVector(dx: b.velocity.dx + a.dx * dt, dy: b.velocity.dy + (a.dy + lift) * dt)
        }
        switch rig.mode {
        case .carry(let offset):
            pull(towards: CGPoint(x: rig.pointer.x - offset.dx, y: rig.pointer.y - offset.dy), stiffness: 260, damping: 30)
            let lean = clamp(b.velocity.dx * 0.00035, -0.4, 0.4)
            b.angularVelocity = clamp((lean - wrap(rig.angle)) * 10, -10, 10)
        case .tilt(let hold, let startAngle, let turned, _):
            pull(towards: hold, stiffness: 300, damping: 35)
            // The body's angle is kept within ±π while `turned` keeps counting, so past half a turn
            // the raw difference is off by a full turn; without `wrap` the jar chases it round forever.
            // No faster than a hand turns a full jar: a neighbour in the way is pushed, not flung.
            b.angularVelocity = clamp(wrap(startAngle + turned - rig.angle) * 12, -5, 5)
        case .free:
            // A jar is heavy at the bottom (thick glass, contents settled low), so a tilted jar
            // rocks back onto its base. One that has fallen past about 60° stays lying down.
            let a = wrap(rig.angle)
            if abs(a) < 1.05 { b.angularVelocity += (-22 * sin(a) - 2 * b.angularVelocity) * dt }
        }
    }

    // MARK: Loop

    override func update(_ currentTime: TimeInterval) {
        let raw = lastTime == 0 ? 1.0 / 60 : currentTime - lastTime
        lastTime = currentTime
        let dt = debugStep ?? CGFloat(min(max(raw, 1.0 / 240), 1.0 / 30))
        // The physics follows the clock; scaled so it moves on by the same fixed step.
        physicsWorld.speed = debugStep.map { $0 / CGFloat(max(raw, 1.0 / 240)) } ?? 1
        frameDT = dt
        time += Double(dt)
        layOutIfNeeded()

        let target: CGFloat = revealed ? 1 : 0
        let peekTarget: CGFloat = peeking && !revealed ? 1 : 0
        if shown != target || peeked != peekTarget {
            shown = target > shown ? min(1, shown + dt / 0.4) : max(0, shown - dt / 0.32)
            peeked = peekTarget > peeked ? min(1, peeked + dt / 0.3) : max(0, peeked - dt / 0.25)
            if shown == 0, peeked == 0 { onHidden?() }
        }

        for rig in rigs {
            drive(rig, dt)

            // What the contents feel: gravity minus the jar's acceleration, in the jar's frame.
            var gx = -rig.acceleration.dx / Self.jarScale
            var gy = (-gravity * Self.jarScale - rig.acceleration.dy) / Self.jarScale
            let m = hypot(gx, gy), cap = gravity * maxG
            if m > cap { gx *= cap / m; gy *= cap / m }
            let c = cos(-rig.angle), s = sin(-rig.angle)
            let lx = c * gx - s * gy, ly = s * gx + c * gy
            rig.felt = CGVector(dx: lx, dy: ly)
            rig.pouring = isPouring(rig)
            stepLid(rig, dt)
        }

        // One pass over everything, whichever jar it is in: scanning all things once per jar would
        // grow with jars times things.
        for thing in things.values {
            guard thing.state == .loose, let rig = thing.rig, let body = thing.proxy?.physicsBody else { continue }
            // Poured, the bigger things lock into an arch across the shoulders and hold each other up,
            // and two can wedge side by side in the neck. While a jar is being emptied they only meet
            // the glass, so each slides down to the neck on its own; none is long enough to jam there alone.
            let between = rig.pouring ? Category.glass : Category.contents | Category.glass
            if body.collisionBitMask != between { body.collisionBitMask = between }
            var v = body.velocity
            v.dx += rig.felt.dx * dt
            v.dy += rig.felt.dy * dt
            body.velocity = limit(v, maxSpeed)
        }

        for thing in things.values {
            // Comes up at an even pace; `show` eases it in and out.
            let lifted: CGFloat = thing === hovered && thing.state == .loose ? 1 : 0
            let step = dt / Self.hoverDuration
            thing.lift = lifted > thing.lift ? min(lifted, thing.lift + step) : max(lifted, thing.lift - step)
            switch thing.state {
            case .pulling: stepPull(thing, dt)
            case .out: stepOut(thing, dt)
            case .flying: stepFly(thing, dt)
            default: break
            }
        }
    }

    private var frameDT: CGFloat = 1.0 / 60

    override func didSimulatePhysics() {
        let e = ease(shown), pe = ease(peeked)
        for rig in rigs {
            let b = rig.physics
            let v = b.velocity
            // Smoothed over a few frames: the jar's velocity comes in steps (the pointer moves between
            // frames, the solver corrects a landing), and the raw difference divided by one frame would
            // kick the contents with accelerations no hand produces.
            let raw = CGVector(dx: (v.dx - rig.velocity.dx) / frameDT, dy: (v.dy - rig.velocity.dy) / frameDT)
            let k = min(1, frameDT / 0.06)
            rig.acceleration = CGVector(dx: lerp(rig.acceleration.dx, raw.dx, k), dy: lerp(rig.acceleration.dy, raw.dy, k))
            rig.velocity = v
            rig.position = rig.body.position
            rig.angle = rig.body.zRotation
            rig.spin = b.angularVelocity
            rememberPlace(rig)

            let out = max(e, pe * rig.peekShare)
            let offset = CGVector(dx: rig.hideOffset.dx * (1 - out), dy: rig.hideOffset.dy * (1 - out))
            rig.node.position = CGPoint(x: rig.position.x + offset.dx, y: rig.position.y + offset.dy)
            rig.node.zRotation = rig.angle
            let bottom = rig.designToWorld(x: 150, y: JarGeometry.bottomY + 4)
            rig.shadow.position = CGPoint(x: bottom.x + offset.dx, y: bottom.y + offset.dy)
            let upright = max(0, cos(rig.angle))
            rig.shadow.setScale(Self.jarScale * (0.6 + 0.4 * upright))
            rig.shadow.alpha = 0.8 * upright
            renderLid(rig)
            rig.dropOutline.alpha = hotRig === rig ? 1 : 0
            updateLabel(rig)
        }
        for thing in things.values {
            switch thing.state {
            case .loose:
                guard let proxy = thing.proxy, let rig = thing.rig else { continue }
                show(thing, at: proxy.position, angle: proxy.zRotation, in: rig)
                let design = JarGeometry.design(proxy.position)
                if design.y < JarGeometry.escapeY && !rig.sealed {
                    escape(thing, from: rig)
                } else if !JarGeometry.isInside(design) || (rig.sealed && design.y < 6) {
                    // Squeezed through the glass by a hard knock: put it back in the middle.
                    proxy.position = JarGeometry.local(x: 150, y: 300)
                    proxy.physicsBody?.velocity = .zero
                }
            case .pulling:
                thing.sprite.position = thing.position
                thing.sprite.zRotation = thing.angle
                thing.sprite.setScale(1 + (Self.hoverScale - 1) * ease(thing.lift))
            case .out, .flying:
                thing.sprite.position = thing.position
                thing.sprite.zRotation = thing.angle
            default:
                break
            }
        }
        debugProbe?()
        debugFilm?()
    }

    /// A thing in a jar, where its body is; while the pointer rests on it, it grows, turns level
    /// and comes forward over the glass and the label, drawn towards the jar's middle and kept
    /// above the bottom so none of it goes below the jar.
    private func show(_ thing: Thing, at position: CGPoint, angle: CGFloat, in rig: JarRig) {
        let lift = ease(thing.lift)
        guard lift > 0.002 else {
            thing.sprite.position = position
            thing.sprite.zRotation = angle
            thing.sprite.setScale(1)
            thing.sprite.zPosition = 0
            return
        }
        let scale = 1 + (Self.hoverScale - 1) * lift
        let floor = JarGeometry.local(x: 150, y: JarGeometry.bottomY - 18).y + thing.size.height * scale / 2
        thing.sprite.position = CGPoint(x: position.x * (1 - 0.35 * lift), y: max(position.y, lerp(position.y, floor, lift)))
        thing.sprite.zRotation = lerpAngle(angle, wrap(-rig.angle), lift)
        thing.sprite.setScale(scale)
        thing.sprite.zPosition = 10
    }

    /// Once a moved jar has come to rest, its spot is saved.
    private func rememberPlace(_ rig: JarRig) {
        let still = hypot(rig.velocity.dx, rig.velocity.dy) < 4 && abs(rig.spin) < 0.05
        if !still || rig.isHeld { rig.placeDirty = true; rig.restingSince = nil; return }
        guard rig.placeDirty, size.width > 0, size.height > 0 else { return }
        let since = rig.restingSince ?? time
        rig.restingSince = since
        if time - since > 0.4 {
            rig.placeDirty = false
            model.setPlace(rig.id, Place(x: Double(rig.position.x / size.width), y: Double(rig.position.y / size.height)))
        }
    }

    func didBegin(_ contact: SKPhysicsContact) {
        let jarHit = contact.bodyA.categoryBitMask == Category.jar && contact.bodyB.categoryBitMask == Category.jar
        guard jarHit, contact.collisionImpulse > 40, time - lastClink > 0.12 else { return }
        lastClink = time
        let strength = Float(min(1, contact.collisionImpulse / 600))
        let jars = [contact.bodyA.node, contact.bodyB.node].map { node in rigs.first { $0.body === node } }
        let pitches = (jars[0].map(pitch) ?? 760, jars[1].map(pitch) ?? 790)
        onSound?(.clink(strength: strength, pitches: pitches), 0.15 + 0.85 * strength, pan(contact.contactPoint.x))
    }

    private func sound(_ sound: Sound, _ volume: Float, at rig: JarRig) {
        onSound?(sound, volume, pan(rig.position.x))
    }

    private func pan(_ x: CGFloat) -> Float {
        size.width > 0 ? Float(x / size.width * 2 - 1) * 0.7 : 0
    }

    /// Every jar rings at a note of its own, a little apart from the others, as no two jars are quite
    /// the same; it stays the same for the life of the jar.
    private func pitch(of rig: JarRig) -> Float {
        760 * (0.92 + 0.16 * Float(rig.id.uuid.0) / 255)
    }

    private func stepPull(_ thing: Thing, _ dt: CGFloat) {
        guard let rig = thing.rig else { return }
        let target = JarGeometry.local(x: 150, y: 110)
        if thing.phase == 0 {
            thing.t = min(1, thing.t + dt / 0.43)
            let e = ease(thing.t)
            thing.position = CGPoint(x: lerp(thing.start.x, target.x, e), y: lerp(thing.start.y, target.y, e))
            thing.angle = lerpAngle(thing.startAngle, thing.entryAngle, e)
            if thing.t >= 1 { thing.phase = 1; thing.t = 0 }
            return
        }
        if !lidLetsThrough(rig) { openLid(rig); return }
        // Up through the neck, gathering speed, and over the rim at exactly the speed it then flies
        // with: the rise lasts as long as it takes to reach that speed, so nothing jerks at the handoff.
        let rim = JarGeometry.local(x: 150, y: -10)
        let rise = rim.y - target.y
        let duration = 2 * rise / (Self.launchSpeed / Self.jarScale)
        thing.t = min(1, thing.t + dt / duration)
        thing.position.y = target.y + rise * thing.t * thing.t
        if thing.t >= 1 {
            let world = rig.toWorld(thing.position)
            thing.sprite.removeFromParent()
            self.world.addChild(thing.sprite)
            thing.sprite.setScale(Self.jarScale)
            thing.sprite.zPosition = Self.outZ
            thing.position = world
            thing.angle = thing.angle + rig.angle
            thing.lift = 0
            thing.settled = false
            thing.state = .out
            placeOut(thing, from: rig)
            thing.velocity = toss(from: world, to: thing.slot, awayFrom: rig)
            thing.spin = thing.velocity.dx < 0 ? 2 : -2
        }
    }

    /// How fast a thing leaves the rim, straight up, before gravity bends its flight.
    private static let launchSpeed: CGFloat = 300
    /// The most a landed thing slides along the floor to its place, in points a second.
    private static let slideSpeed: CGFloat = 360

    /// The throw that lands a thing on its place in the row: up at the launch speed, and sideways
    /// just enough to come down there, like a slip tossed onto the table. With no place to land it
    /// is tossed a little way clear of the jar.
    private func toss(from point: CGPoint, to slot: CGPoint?, awayFrom rig: JarRig) -> CGVector {
        let g = gravity * Self.jarScale, up = Self.launchSpeed
        guard let slot else {
            let direction: CGFloat = rig.position.x < size.width / 2 ? 1 : -1
            return CGVector(dx: direction * 160, dy: up)
        }
        let drop = max(0, point.y - slot.y)
        let flight = (up + sqrt(up * up + 2 * g * drop)) / g
        return CGVector(dx: (slot.x - point.x) / flight, dy: up)
    }

    private func escape(_ thing: Thing, from rig: JarRig) {
        guard let proxy = thing.proxy, let body = proxy.physicsBody else { return }
        let world = rig.toWorld(proxy.position)
        let c = cos(rig.angle), s = sin(rig.angle)
        let v = CGVector(dx: (c * body.velocity.dx - s * body.velocity.dy) * Self.jarScale + rig.velocity.dx,
                         dy: (s * body.velocity.dx + c * body.velocity.dy) * Self.jarScale + rig.velocity.dy)
        thing.angle = proxy.zRotation + rig.angle
        thing.spin = body.angularVelocity
        thing.lift = 0
        dropProxy(thing)
        thing.sprite.removeFromParent()
        self.world.addChild(thing.sprite)
        thing.sprite.setScale(Self.jarScale)
        thing.sprite.zPosition = Self.outZ
        thing.position = world
        thing.velocity = v
        thing.settled = false
        // Poured or taken out, it falls to the bottom of the screen.
        thing.state = .out
        placeOut(thing, from: rig)
        promoteWaiting(in: rig)
    }

    /// Space between things lying in a row, and between a row and a jar.
    private static let rowGap: CGFloat = 10
    /// Things out of a jar lie behind the jars, above their shadows: one sliding to its place in a row
    /// past a jar is seen through the glass, not passing in front of it.
    private static let outZ: CGFloat = -0.5
    /// Rows along the floor are a thing's tallest height apart, so a second row lies on the first.
    private var rowHeight: CGFloat { JarGeometry.allSizes.map(\.height).max()! * Self.jarScale + 4 }

    /// Where a thing just out of a jar will lie: the first free place in a row along the floor beside
    /// the jar, growing away from it towards the middle of the screen, so what came out can be seen
    /// whole and in order. Jars and what already lies out are stepped over; when a row reaches the
    /// screen's edge, the next one goes on top of it. With no room anywhere it lies where it falls.
    private func placeOut(_ thing: Thing, from rig: JarRig) {
        let width = thing.size.width * Self.jarScale, gap = Self.rowGap
        let direction: CGFloat = rig.position.x < size.width / 2 ? 1 : -1
        let start = rig.position.x + direction * (visibleJarWidth / 2 + gap)
        let jars = rigs.map { ($0.position.x - visibleJarWidth / 2, $0.position.x + visibleJarWidth / 2) }
        thing.slot = nil
        for row in 0..<8 {
            let taken = jars + things.values.compactMap { other -> (CGFloat, CGFloat)? in
                guard other !== thing, other.state == .out, let s = other.slot, other.row == row else { return nil }
                let w = other.size.width * Self.jarScale
                return (s.x - w / 2, s.x + w / 2)
            }
            var edge = start
            while true {
                let (lo, hi) = direction > 0 ? (edge, edge + width) : (edge - width, edge)
                if lo < 0 || hi > size.width { break }
                if let blocking = taken.first(where: { $0.0 < hi + gap && $0.1 > lo - gap }) {
                    edge = direction > 0 ? blocking.1 + gap : blocking.0 - gap
                    continue
                }
                thing.row = row
                thing.slot = CGPoint(x: (lo + hi) / 2, y: floorY + CGFloat(row) * rowHeight + thing.size.height * Self.jarScale / 2)
                // Put down by hand, not by a machine.
                thing.slotAngle = CGFloat.random(in: -0.05...0.05)
                return
            }
        }
    }

    private func stepOut(_ thing: Thing, _ dt: CGFloat) {
        let g = gravity * Self.jarScale
        thing.velocity.dy -= g * dt
        thing.position.x += thing.velocity.dx * dt
        thing.position.y += thing.velocity.dy * dt
        thing.angle += thing.spin * dt
        let half = thing.size.height / 2 * Self.jarScale
        let floor = thing.slot?.y ?? (floorY + half)
        if thing.position.y <= floor {
            thing.position.y = floor
            if thing.velocity.dy < -90 {
                thing.velocity.dy = -thing.velocity.dy * 0.3
                thing.spin *= 0.5
            } else {
                thing.velocity.dy = 0
            }
            thing.velocity.dx *= max(0, 1 - 9 * dt)
            thing.spin *= max(0, 1 - 12 * dt)
            // Once it is down it slides into its place in the row, turning flat as it goes.
            // No faster than a hand pushes a slip along a table, slowing over the last stretch.
            if let slot = thing.slot { thing.position.x += clamp((slot.x - thing.position.x) * 6, -Self.slideSpeed, Self.slideSpeed) * dt }
            let flat = (thing.angle / .pi).rounded() * .pi + thing.slotAngle
            thing.angle += (flat - thing.angle) * min(1, 14 * dt)
        }
        let halfWidth = thing.size.width / 2 * Self.jarScale
        if thing.position.x < halfWidth { thing.position.x = halfWidth; thing.velocity.dx = abs(thing.velocity.dx) * 0.4 }
        if thing.position.x > size.width - halfWidth { thing.position.x = size.width - halfWidth; thing.velocity.dx = -abs(thing.velocity.dx) * 0.4 }
        let inPlace = thing.slot.map { abs($0.x - thing.position.x) < 0.5 } ?? true
        if !thing.settled, thing.position.y <= floor + 0.5, thing.velocity.dy == 0, abs(thing.velocity.dx) < 12, inPlace {
            thing.settled = true
            thing.velocity = .zero
            thing.spin = 0
            if let slot = thing.slot { thing.position = slot }
            // Face up, the way you would put it down.
            thing.angle = thing.slotAngle
            onSettled?(thing)
        }
    }

    private func stepFly(_ thing: Thing, _ dt: CGFloat) {
        guard let rig = thing.rig else { return }
        thing.t = min(1, thing.t + dt / 0.55)
        guard thing.t > 0 else { return }
        let e = ease(thing.t)
        let to = rig.designToWorld(x: 150, y: -50)
        thing.position = CGPoint(x: lerp(thing.start.x, to.x, e), y: lerp(thing.start.y, to.y, e) + 70 * Self.jarScale * sin(.pi * thing.t))
        thing.angle = lerpAngle(thing.startAngle, rig.angle + thing.entryAngle, e)
        guard thing.t >= 1 else { return }
        openLid(rig)
        guard lidLetsThrough(rig) else { return }
        // Several dropped at once go in one by one: one coming in on top of another still in the
        // neck knocks it back out of the open jar. Not for long, in case the neck never clears.
        let neckBusy = things.values.contains {
            $0 !== thing && $0.rig === rig && $0.state == .loose
                && JarGeometry.design($0.proxy?.position ?? .zero).y < JarGeometry.shoulderY - 20
        }
        if neckBusy, thing.queued < 1.2 { thing.queued += frameDT; return }
        // The wait counts from the last one let in, so a queue never goes in all at once.
        for other in things.values where other !== thing && other.rig === rig && other.state == .flying { other.queued = 0 }
        let loose = things.values.filter { $0.rig === rig && $0.state == .loose }.count
        if loose >= JarGeometry.maxLoose,
           let oldest = things.values.filter({ $0.rig === rig && $0.state == .loose }).min(by: { $0.item.addedAt < $1.item.addedAt }) {
            // A full jar: the oldest thing in it sinks under the rest to make room, so what is on top
            // is the newest, the same as a relaunch shows (`addRig`), and it is the last to come back up.
            dropProxy(oldest)
            oldest.sprite.removeFromParent()
            oldest.state = .waiting
            rig.waiting.append(oldest)
        }
        do {
            // Let go just above the mouth, a little off true and turning, so a slip topples over
            // instead of standing on end.
            putLoose(thing, in: rig, at: JarGeometry.local(x: 150 + CGFloat.random(in: -14...14), y: 0),
                     angle: thing.entryAngle + CGFloat.random(in: -0.25...0.25), velocity: CGVector(dx: CGFloat.random(in: -25...25), dy: -140))
            thing.proxy?.physicsBody?.angularVelocity = CGFloat.random(in: -1.5...1.5)
        }
        rig.shownCount = -1
        // Put back while the jars were going away: shut it, so it is closed next time.
        if !revealed, !things.values.contains(where: { $0.rig === rig && $0.state == .flying }) { closeLid(rig) }
    }

    // MARK: Showing and hiding

    /// Each jar slides off past the screen edge nearest to it, and comes back the same way.
    private func computeHideOffsets() {
        let reach = JarGeometry.box.height * Self.jarScale
        let half = CGSize(width: JarGeometry.box.width * Self.jarScale / 2, height: reach / 2)
        for rig in rigs {
            let p = rig.position
            // (distance to the edge, the way off past it, the jar's half size that way)
            let options: [(CGFloat, CGVector, CGFloat)] = [
                (p.x, CGVector(dx: -(p.x + reach), dy: 0), half.width),
                (size.width - p.x, CGVector(dx: size.width - p.x + reach, dy: 0), half.width),
                (p.y, CGVector(dx: 0, dy: -(p.y + reach)), half.height),
                (size.height - p.y, CGVector(dx: 0, dy: size.height - p.y + reach), half.height),
            ]
            let edge = options.min { $0.0 < $1.0 }!
            rig.hideOffset = edge.1
            // Peeking, 40% of the jar shows past its edge: its lid and shoulders, or its side.
            let travel = hypot(edge.1.dx, edge.1.dy)
            let showing = Self.peekShowing * 2 * edge.2
            rig.peekShare = travel > 0 ? clamp(1 - (edge.0 + edge.2 - showing) / travel, 0, 1) : 0
        }
    }

    private static let peekShowing: CGFloat = 0.4

    /// Hidden jars put their tops out from their edge, or go back.
    func setPeeking(_ on: Bool) {
        guard peeking != on else { return }
        peeking = on
        if on { computeHideOffsets() }
    }

    /// Where the jars are drawn right now, in scene coordinates, cut to the screen: while they
    /// peek, what of them shows.
    func peekRects() -> [CGRect] {
        let screen = CGRect(origin: .zero, size: size)
        return rigs.compactMap { rig in
            let f = rig.node.calculateAccumulatedFrame()
            let a = convert(CGPoint(x: f.minX, y: f.minY), from: world), b = convert(CGPoint(x: f.maxX, y: f.maxY), from: world)
            let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)).intersection(screen)
            return r.isNull || r.isEmpty ? nil : r
        }
    }

    func setRevealed(_ on: Bool) {
        guard revealed != on else { return }
        revealed = on
        if !on {
            computeHideOffsets()
            setHover(nil)
            setHot(nil)
            // Put away with their lids shut, ready for next time.
            rigs.forEach(closeLid)
            // Whatever was left out goes back into its jar.
            for thing in things.values where thing.state == .out || thing.state == .pulling {
                if thing.state == .pulling {
                    thing.state = .out
                    thing.position = thing.rig?.designToWorld(x: 150, y: -60) ?? .zero
                    thing.sprite.removeFromParent()
                    world.addChild(thing.sprite)
                    thing.sprite.setScale(Self.jarScale)
                }
                putBack(thing)
            }
        }
    }

    // MARK: Hit testing (scene points)

    enum Target {
        case thing(Thing)
        case label(JarRig)
        case jar(JarRig, local: CGPoint)
        case lid(JarRig)
        case out(Thing)
    }

    func target(at scenePoint: CGPoint) -> Target? {
        guard revealed else { return nil }
        let p = world.convert(scenePoint, from: self)
        // One still sliding to its place may lie over one already settled: the moving one is on top.
        for thing in things.values.sorted(by: { !$0.settled && $1.settled }) where thing.state == .out {
            if contains(p, center: thing.position, angle: thing.angle, size: thing.size, scale: Self.jarScale) { return .out(thing) }
        }
        for rig in rigs.reversed() {
            let local = rig.toLocal(p)
            let d = JarGeometry.design(local)
            if isOnLid(rig, local) { return .lid(rig) }
            // A thing shown larger keeps the pointer while it is over the larger picture, over the label
            // too, or still over where the thing lies. The picture moves and turns as it grows, so
            // near an edge the pointer can be off one and on the other: losing it there would shrink
            // it back under the pointer, and it would come up again, round and round.
            if let h = hovered, h.state == .loose, h.rig === rig,
               contains(local, center: h.sprite.position, angle: h.sprite.zRotation, size: h.size, scale: h.sprite.xScale)
                || (h.proxy.map { contains(local, center: $0.position, angle: $0.zRotation, size: h.size, scale: 1) } ?? false) {
                return .thing(h)
            }
            guard d.x >= JarGeometry.outerLeft, d.x <= JarGeometry.outerRight, d.y >= 10, d.y <= JarGeometry.bottomY else { continue }
            if JarGeometry.labelRect.contains(d) { return .label(rig) }
            for sprite in rig.contents.children.reversed() {
                guard let name = sprite.name, let id = UUID(uuidString: name), let thing = things[id], thing.state == .loose else { continue }
                if contains(local, center: sprite.position, angle: sprite.zRotation, size: thing.size, scale: 1) { return .thing(thing) }
            }
            return .jar(rig, local: local)
        }
        return nil
    }

    /// The jar a drop at this point goes into, lid included; none when the point is beside the jars,
    /// as something carried past them is only being moved about the screen.
    func rig(under scenePoint: CGPoint) -> JarRig? {
        let p = world.convert(scenePoint, from: self)
        return rigs.reversed().first { rig in
            let d = JarGeometry.design(rig.toLocal(p))
            return d.x >= JarGeometry.outerLeft - 10 && d.x <= JarGeometry.outerRight + 10 && d.y >= -40 && d.y <= JarGeometry.bottomY
        }
    }

    /// The jars and what lies around them, in scene coordinates: where the panel takes the mouse.
    func interactiveRects() -> [CGRect] {
        guard revealed else { return [] }
        var rects: [CGRect] = []
        for rig in rigs {
            let corners = [(JarGeometry.outerLeft, CGFloat(-10)), (JarGeometry.outerRight, -10),
                           (JarGeometry.outerLeft, JarGeometry.bottomY), (JarGeometry.outerRight, JarGeometry.bottomY)]
                .map { rig.designToWorld(x: $0.0, y: $0.1) }
            let xs = corners.map(\.x), ys = corners.map(\.y)
            rects.append(CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!))
            if !rig.lid.isClosed {
                // The open lid stands up past the jar's top: its far corner counts too.
                let r = JarGeometry.lidRect
                let tip = rig.toWorld(lidPointToLocal(rig, CGPoint(x: r.maxX, y: -r.minY)))
                rects.append(CGRect(x: tip.x - 40, y: tip.y - 40, width: 80, height: 80))
                rects[rects.count - 2] = rects[rects.count - 2].union(rects[rects.count - 1])
            }
        }
        for thing in things.values where thing.state == .out {
            let r = max(thing.size.width, thing.size.height) * Self.jarScale / 2 + 6
            rects.append(CGRect(x: thing.position.x - r, y: thing.position.y - r, width: r * 2, height: r * 2))
        }
        return rects
    }

    /// The lid (open or closed) and the lever, in the jar's frame.
    private func isOnLid(_ rig: JarRig, _ local: CGPoint) -> Bool {
        let q = rig.lidLocal(local)
        let r = JarGeometry.lidRect
        // The lid's frame is y-up from the hinge; the art's rect is y-down.
        if q.x >= r.minX - 4, q.x <= r.maxX + 4, q.y >= -r.maxY - 6, q.y <= -r.minY + 6 { return true }
        let lever = JarGeometry.design(local)
        return abs(lever.x - JarGeometry.leverPivot.x) < 12 && lever.y > JarGeometry.leverPivot.y - 6 && lever.y < JarGeometry.leverPivot.y + 52
    }

    /// From the lid's own frame (y-up, from the hinge) to the jar's.
    private func lidPointToLocal(_ rig: JarRig, _ q: CGPoint) -> CGPoint {
        let hinge = JarGeometry.local(JarGeometry.lidHinge)
        let a = rig.lidSprite.zRotation
        return CGPoint(x: hinge.x + cos(a) * q.x - sin(a) * q.y, y: hinge.y + sin(a) * q.x + cos(a) * q.y)
    }

    private func contains(_ p: CGPoint, center: CGPoint, angle: CGFloat, size: CGSize, scale: CGFloat) -> Bool {
        let dx = p.x - center.x, dy = p.y - center.y
        let c = cos(-angle), s = sin(-angle)
        let x = (c * dx - s * dy) / scale, y = (s * dx + c * dy) / scale
        return abs(x) <= size.width / 2 + 3 && abs(y) <= size.height / 2 + 3
    }

    // MARK: Pointer

    func grab(_ rig: JarRig, at scenePoint: CGPoint, tilt: Bool) {
        let p = world.convert(scenePoint, from: self)
        rig.pointer = p
        if tilt {
            let a = atan2(p.y - rig.position.y, p.x - rig.position.x)
            rig.mode = .tilt(hold: rig.position, startAngle: rig.angle, turned: 0, lastPointerAngle: a)
        } else {
            rig.mode = .carry(offset: CGVector(dx: p.x - rig.position.x, dy: p.y - rig.position.y))
        }
        setHover(nil)
        setActive(rig)
    }

    func drag(_ rig: JarRig, to scenePoint: CGPoint) {
        let p = world.convert(scenePoint, from: self)
        rig.pointer = p
        if case .tilt(let hold, let start, let turned, let last) = rig.mode {
            let a = atan2(p.y - rig.position.y, p.x - rig.position.x)
            rig.mode = .tilt(hold: hold, startAngle: start, turned: turned + wrap(a - last), lastPointerAngle: a)
        }
    }

    /// Let go: the jar keeps the speed the hand gave it and falls until it lands on something.
    func release(_ rig: JarRig) {
        rig.mode = .free
        rig.body.zRotation = wrap(rig.body.zRotation)
        rig.angle = rig.body.zRotation
    }

    /// Space: the jar jumps and lands where it stood, which shakes everything in it.
    func hop(_ rig: JarRig) {
        guard case .free = rig.mode, abs(rig.velocity.dy) < 30 else { return }
        rig.physics.velocity.dy = 520
    }

    func nudge(_ rig: JarRig, by spin: CGFloat) { rig.physics.angularVelocity += spin }

    func setHover(_ thing: Thing?) {
        guard hovered !== thing else { return }
        // Things in a jar grow through `lift` in the loop; those lying out just swell a little.
        if let old = hovered, old.state == .out { old.sprite.run(.scale(to: Self.jarScale, duration: 0.12)) }
        hovered = thing
        if let thing, thing.state == .out { thing.sprite.run(.scale(to: Self.jarScale * 1.08, duration: 0.12)) }
    }

    func setHot(_ rig: JarRig?) {
        guard hotRig !== rig else { return }
        hotRig = rig
    }

    // MARK: Debug

    /// Called after every physics step while set, so a test run can watch the contents frame by frame.
    var debugProbe: (() -> Void)?
    /// Called once a frame after everything has moved, while a test instance films the shelf.
    var debugFilm: (() -> Void)?
    /// While a test instance films the shelf, every frame moves it on by this much whatever the clock
    /// says, so a frame that takes long to capture neither jolts anything nor drops out of the film.
    var debugStep: CGFloat?

    /// The middle of the jar's lid, where a click opens or closes it, in scene coordinates.
    func debugLidTop(_ rig: JarRig) -> CGPoint {
        convert(rig.designToWorld(x: 150, y: 2), from: world)
    }

    /// The acceleration the contents feel, in design units a second squared, when the jar stands still.
    var debugGravity: CGFloat { gravity }

    /// How far out the jars are (0 away, 1 out) and how far they peek, as the animation stands.
    var debugShown: CGFloat { shown }
    var debugPeeked: CGFloat { peeked }

    /// What the jar's contents feel this frame, and the proxy velocity of every loose thing, oldest first.
    func debugMotion(_ rig: JarRig) -> (felt: CGVector, velocities: [UUID: CGVector]) {
        var velocities: [UUID: CGVector] = [:]
        for thing in things.values where thing.rig === rig && thing.state == .loose {
            velocities[thing.id] = thing.proxy?.physicsBody?.velocity ?? .zero
        }
        return (rig.felt, velocities)
    }

    func debugState() -> [[String: Any]] {
        rigs.map { rig in
            let mine = things.values.filter { $0.rig === rig }
            func count(_ s: Thing.State) -> Int { mine.filter { $0.state == s }.count }
            let lidName: String
            switch rig.lid {
            case .closed: lidName = "closed"
            case .open: lidName = "open"
            case .held: lidName = "held"
            default: lidName = "moving"
            }
            // Jars must never pass through each other: closer than a jar's width means they do.
            let nearest = rigs.filter { $0 !== rig }.map { hypot($0.position.x - rig.position.x, $0.position.y - rig.position.y) }.min()
            return ["name": rig.name, "loose": count(.loose), "waiting": rig.waiting.count, "out": count(.out),
                    "pulling": count(.pulling), "flying": count(.flying), "lid": lidName, "sealed": rig.sealed,
                    "position": [rig.position.x.rounded(), rig.position.y.rounded()], "angle": (rig.angle * 100).rounded() / 100,
                    "nearestJar": (nearest ?? -1).rounded(), "jarWidth": visibleJarWidth.rounded(),
                    "looseInside": mine.filter { $0.state == .loose }.allSatisfy { JarGeometry.isInside(JarGeometry.design($0.proxy?.position ?? .zero)) },
                    "overlaps": overlappingPairs(mine.filter { $0.state == .loose }),
                    // Long things on end: paper should not stay like that.
                    "standing": mine.filter { $0.state == .loose && $0.size.width > $0.size.height * 1.6 }
                        .filter { abs(abs(wrap($0.proxy?.zRotation ?? 0)) - .pi / 2) < 0.45 }.count]
        }
    }

    func debugCarry(_ rig: JarRig, to point: CGPoint) {
        rig.pointer = point
        rig.mode = .carry(offset: .zero)
    }

    /// A point on the lid's arc at this angle, in scene coordinates, as a hand holding its far edge would be.
    func debugLidPoint(_ rig: JarRig, angle: CGFloat) -> CGPoint {
        let hinge = JarGeometry.local(JarGeometry.lidHinge)
        let local = CGPoint(x: hinge.x + 140 * cos(angle), y: hinge.y + 140 * sin(angle))
        return convert(rig.toWorld(local), from: world)
    }

    /// Just inside a corner of the jar's n-th thing (oldest first) where it lies, in scene coordinates.
    func debugEdgePoint(_ rig: JarRig, _ index: Int) -> CGPoint? {
        let loose = things.values.filter { $0.rig === rig && $0.state == .loose }.sorted { $0.item.addedAt < $1.item.addedAt }
        guard loose.indices.contains(index), let proxy = loose[index].proxy else { return nil }
        let half = CGSize(width: loose[index].size.width / 2 - 3, height: loose[index].size.height / 2 - 3)
        let c = cos(proxy.zRotation), s = sin(proxy.zRotation)
        let local = CGPoint(x: proxy.position.x + c * half.width - s * half.height, y: proxy.position.y + s * half.width + c * half.height)
        return convert(rig.toWorld(local), from: world)
    }

    var debugHoveredID: UUID? { hovered?.id }

    /// The jar a drop would go into at this many points right of jar n's middle, if any.
    func debugJarUnder(_ index: Int, dx: CGFloat) -> String {
        guard index < rigs.count else { return "no such jar" }
        let p = convert(rigs[index].node.position, from: world)
        return rig(under: CGPoint(x: p.x + dx, y: p.y))?.name ?? "none"
    }

    func debugHover(_ rig: JarRig, _ index: Int) {
        let loose = things.values.filter { $0.rig === rig && $0.state == .loose }.sorted { $0.item.addedAt < $1.item.addedAt }
        setHover(loose.indices.contains(index) ? loose[index] : nil)
    }

    /// Takes the jar's n-th thing (oldest first) out as a click on it would; where its middle was, in scene coordinates.
    func debugPull(_ rig: JarRig, _ index: Int) -> CGPoint? {
        let loose = things.values.filter { $0.rig === rig && $0.state == .loose }.sorted { $0.item.addedAt < $1.item.addedAt }
        guard loose.indices.contains(index), let proxy = loose[index].proxy else { return nil }
        let at = convert(rig.toWorld(proxy.position), from: world)
        pull(loose[index])
        return at
    }

    /// Pairs of things in a jar whose drawings overlap by more than 2 units: a corner of one
    /// sits inside the other's outline pulled in by that much.
    private func overlappingPairs(_ loose: [Thing]) -> Int {
        func corners(_ t: Thing) -> [CGPoint] {
            guard let p = t.proxy else { return [] }
            let c: CGFloat = cos(p.zRotation), s: CGFloat = sin(p.zRotation)
            let w: CGFloat = t.size.width / 2, h: CGFloat = t.size.height / 2
            let offsets: [CGVector] = [CGVector(dx: -w, dy: -h), CGVector(dx: w, dy: -h), CGVector(dx: w, dy: h), CGVector(dx: -w, dy: h)]
            return offsets.map { o -> CGPoint in
                CGPoint(x: p.position.x + c * o.dx - s * o.dy, y: p.position.y + s * o.dx + c * o.dy)
            }
        }
        func inside(_ q: CGPoint, _ t: Thing) -> Bool {
            guard let p = t.proxy else { return false }
            let dx = q.x - p.position.x, dy = q.y - p.position.y, c = cos(-p.zRotation), s = sin(-p.zRotation)
            return abs(c * dx - s * dy) < t.size.width / 2 - 2 && abs(s * dx + c * dy) < t.size.height / 2 - 2
        }
        var n = 0
        for i in loose.indices {
            for j in loose.indices where j > i {
                if corners(loose[i]).contains(where: { inside($0, loose[j]) }) || corners(loose[j]).contains(where: { inside($0, loose[i]) }) { n += 1 }
            }
        }
        return n
    }

    func debugTilt(_ rig: JarRig, by radians: CGFloat) {
        rig.mode = .tilt(hold: rig.position, startAngle: rig.angle, turned: radians, lastPointerAngle: 0)
    }
}

// MARK: - Small math

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
func ease(_ t: CGFloat) -> CGFloat { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
/// The lid swinging open: it starts from rest as the lever lets go, swings, goes a couple of
/// degrees past and settles back against its hinge.
func swingOpen(_ t: CGFloat) -> CGFloat {
    let s = t * t * (3 - 2 * t)
    let c1: CGFloat = 0.8, c3 = c1 + 1
    return 1 + c3 * pow(s - 1, 3) + c1 * pow(s - 1, 2)
}
/// The lid coming down: it starts from rest and meets the rim still moving, but not slamming.
func swingShut(_ t: CGFloat) -> CGFloat { t * t * (2 - t) }
func wrap(_ a: CGFloat) -> CGFloat { atan2(sin(a), cos(a)) }
func lerpAngle(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + wrap(b - a) * t }
func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(hi, max(lo, v)) }
func limit(_ v: CGVector, _ maxLength: CGFloat) -> CGVector {
    let l = hypot(v.dx, v.dy)
    return l > maxLength ? CGVector(dx: v.dx * maxLength / l, dy: v.dy * maxLength / l) : v
}
