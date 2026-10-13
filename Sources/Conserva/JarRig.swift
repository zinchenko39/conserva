import ConservaCore
import SpriteKit

/// Physics categories. Jars collide with each other and the screen's edges;
/// the contents only ever meet each other and their own jar's glass, in a box far away.
enum Category {
    static let contents: UInt32 = 1 << 0
    static let jar: UInt32 = 1 << 1
    static let screenEdge: UInt32 = 1 << 2
    static let glass: UInt32 = 1 << 3
}

/// One thing on the shelf, wherever it is right now: loose in a jar, on its
/// way out, lying beside its jar, or flying back in.
final class Thing {
    enum State {
        /// In a jar but below the others, not simulated until there is room.
        case waiting
        /// Loose in a jar; its proxy body is simulated.
        case loose
        /// Being taken out through the neck.
        case pulling
        /// Out of the jar, falling or lying beside it.
        case out
        /// On its way into a jar.
        case flying
        case gone
    }

    let id: UUID
    var item: Item
    let size: CGSize
    let sprite: SKSpriteNode
    var proxy: SKNode?
    weak var rig: JarRig?
    var state: State = .waiting

    // Kinematics while pulling (jar-local) or out and flying (world).
    var position = CGPoint.zero
    var velocity = CGVector.zero
    var angle: CGFloat = 0
    var spin: CGFloat = 0
    var t: CGFloat = 0
    var phase = 0
    var start = CGPoint.zero
    var startAngle: CGFloat = 0
    var settled = false
    /// 0…1: how far it has come up to be looked at while the pointer rests on it in the jar.
    var lift: CGFloat = 0
    /// Seconds it has waited at the mouth for the one before it to drop clear of the neck.
    var queued: CGFloat = 0
    /// Out of a jar: the place in the row along the floor it slides to once it lands, and which row.
    var slot: CGPoint?
    var slotAngle: CGFloat = 0
    var row = 0

    init(item: Item, texture: SKTexture) {
        id = item.id
        self.item = item
        size = JarGeometry.size(of: item)
        sprite = SKSpriteNode(texture: texture, size: size)
        sprite.name = item.id.uuidString
    }

    /// Long things go through the neck upright; narrow ones, a photo or a page, are narrow enough to go flat.
    var entryAngle: CGFloat { size.width < 70 ? 0 : .pi / 2 }
}

/// A jar: its artwork, its body on the screen, its cap, and a private physics
/// box where its contents are simulated.
///
/// The jar itself is a rigid body under gravity: it falls when let go, stands
/// on the bottom of the screen or on another jar, and jars push and knock
/// into each other.
/// Its contents are simulated in the jar's own frame, in a box that never
/// moves (`lab`). The jar's motion reaches them as a change of effective
/// gravity: real gravity minus the jar's acceleration, turned into the jar's
/// frame. The sprites copy the proxies' poses.
final class JarRig {
    enum Mode {
        case free
        case carry(offset: CGVector)
        case tilt(hold: CGPoint, startAngle: CGFloat, turned: CGFloat, lastPointerAngle: CGFloat)
    }

    /// The swing-top lid. It never leaves the jar: the lever lets go and the
    /// lid swings back on its hinge, and stays open until it is closed.
    enum Lid {
        case closed
        /// 0…1: the lever flips out, then the lid swings back.
        case opening(CGFloat)
        case open
        /// 0…1: the lid swings down, then the lever snaps shut.
        case closing(CGFloat)
        /// Held by the pointer at this angle on its hinge, the lever out.
        case held(CGFloat)

        var isOpen: Bool { if case .open = self { return true } else { return false } }
        var isClosed: Bool { if case .closed = self { return true } else { return false } }
    }

    let id: UUID
    var name: String
    /// The jar's rigid body on the screen. Its pose is the jar's pose.
    let body = SKNode()
    /// The artwork. Follows `body`, pushed off screen while the jars are hidden.
    let node = SKNode()
    let contents = SKNode()
    let labelSprite: SKSpriteNode
    let dropOutline: SKSpriteNode
    let shadow: SKSpriteNode
    let lidSprite: SKSpriteNode
    let leverSprite: SKSpriteNode
    let lab = SKNode()
    private let capEdge = SKNode()

    var position = CGPoint.zero
    var velocity = CGVector.zero
    /// How fast the jar's velocity changed over the last frame: what the contents feel.
    var acceleration = CGVector.zero
    /// What the contents feel this frame, in the jar's frame (y towards the mouth): gravity minus the jar's acceleration.
    var felt = CGVector.zero
    /// The lid is off and the contents are drawn towards the mouth: tipped or turned over.
    var pouring = false
    var angle: CGFloat = 0
    var spin: CGFloat = 0
    var mode = Mode.free
    var pointer = CGPoint.zero

    var lid = Lid.closed
    /// While the lid is held: its angle minus the pointer's around the hinge, so it does not jump to the pointer.
    var lidGrip: CGFloat = 0
    /// While the lid is held: how fast the hand is swinging it, in radians a second.
    var lidSwing: CGFloat = 0
    let scale: CGFloat

    /// Where the jar slides to while hidden, from where it stands.
    var hideOffset = CGVector.zero
    /// How far out it comes while the jars peek from their edge, as a fraction of the way from hidden to shown.
    var peekShare: CGFloat = 0
    /// Moved since its place was last saved.
    var placeDirty = false
    var restingSince: TimeInterval?

    var waiting: [Thing] = []
    var shownCount = -1

    init(id: UUID, name: String, scale: CGFloat, back: SKTexture, front: SKTexture, outline: SKTexture,
         lidTexture: SKTexture, leverTexture: SKTexture, hingeTexture: SKTexture, shadowTexture: SKTexture) {
        self.id = id
        self.name = name
        self.scale = scale
        let box = JarGeometry.box
        let backSprite = SKSpriteNode(texture: back, size: box)
        backSprite.zPosition = 0
        contents.zPosition = 1
        let frontSprite = SKSpriteNode(texture: front, size: box)
        frontSprite.zPosition = 2
        labelSprite = SKSpriteNode(color: .clear, size: JarArt.labelSize)
        labelSprite.zPosition = 3
        // The paper sits 2 units below the middle of its texture, which leaves room for the tape above it.
        let labelCenter = CGPoint(x: JarGeometry.labelRect.midX, y: JarGeometry.labelRect.midY - 2)
        labelSprite.position = JarGeometry.local(labelCenter)
        labelSprite.zRotation = -1.5 * .pi / 180
        dropOutline = SKSpriteNode(texture: outline, size: box)
        dropOutline.zPosition = 4
        dropOutline.alpha = 0
        node.addChild(backSprite)
        node.addChild(contents)
        node.addChild(frontSprite)
        node.addChild(labelSprite)

        // The lid and its lever are part of the jar: they move, tip and hide with it.
        lidSprite = SKSpriteNode(texture: lidTexture, size: JarGeometry.lidRect.size)
        lidSprite.anchorPoint = JarArt.lidAnchor
        lidSprite.position = JarGeometry.local(JarGeometry.lidHinge)
        lidSprite.zPosition = 2.5
        leverSprite = SKSpriteNode(texture: leverTexture, size: JarArt.leverSize)
        leverSprite.anchorPoint = JarArt.leverAnchor
        leverSprite.position = JarGeometry.local(JarGeometry.leverPivot)
        leverSprite.zPosition = 2.6
        // The near half of the hinge's upright eye, over the lid's eye that is threaded through it.
        let hingeSprite = SKSpriteNode(texture: hingeTexture, size: JarArt.hingeSize)
        hingeSprite.position = JarGeometry.local(JarGeometry.lidHinge)
        hingeSprite.zPosition = 2.55
        node.addChild(lidSprite)
        node.addChild(hingeSprite)
        node.addChild(leverSprite)
        node.addChild(dropOutline)
        node.setScale(scale)

        shadow = SKSpriteNode(texture: shadowTexture)
        shadow.zPosition = -1

        body.physicsBody = Self.makeBody(scale: scale)

        // The glass: the inner outline as an open chain, the mouth left open.
        let chain = CGMutablePath()
        for (i, p) in JarGeometry.innerChain.enumerated() {
            let l = JarGeometry.local(p)
            if i == 0 { chain.move(to: l) } else { chain.addLine(to: l) }
        }
        // Box2D takes the higher restitution of the two bodies that meet, so the glass bounces as little
        // as the paper things do.
        // Slippery, so a slip leaning on the shoulders slides down to the pile instead of hanging there.
        let glass = SKPhysicsBody(edgeChainFrom: chain)
        glass.friction = 0.3
        glass.restitution = 0.02
        glass.categoryBitMask = Category.glass
        glass.collisionBitMask = Category.contents
        lab.physicsBody = glass
        let y = JarGeometry.local(x: 150, y: JarGeometry.mouthY).y + 1
        let half = JarGeometry.mouthHalfWidth + 12
        let capBody = SKPhysicsBody(edgeFrom: CGPoint(x: -half, y: y), to: CGPoint(x: half, y: y))
        capBody.restitution = 0.02
        capBody.categoryBitMask = Category.glass
        capBody.collisionBitMask = Category.contents
        capEdge.physicsBody = capBody
        lab.addChild(capEdge)
    }

    /// The jar's outside as two convex pieces, body and shoulders, at its on-screen size.
    private static func makeBody(scale: CGFloat) -> SKPhysicsBody {
        func piece(_ points: [(CGFloat, CGFloat)]) -> SKPhysicsBody {
            let path = CGMutablePath()
            for (i, p) in points.enumerated() {
                let l = JarGeometry.local(x: p.0, y: p.1)
                let q = CGPoint(x: l.x * scale, y: l.y * scale)
                if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
            path.closeSubpath()
            return SKPhysicsBody(polygonFrom: path)
        }
        // Listed clockwise on the y-down artwork, which is counterclockwise once flipped, as SpriteKit wants.
        // The shoulders reach up to the cap's top, so a jar stood on another rests on its cap.
        let bodyPiece = piece([(22, 122), (278, 122), (278, 392), (256, 414), (44, 414), (22, 392)])
        let shoulders = piece([(22, 122), (72, -3), (228, -3), (278, 122)])
        let b = SKPhysicsBody(bodies: [bodyPiece, shoulders])
        b.affectedByGravity = true
        b.allowsRotation = true
        b.density = 1
        // Glass on glass grips enough to stack; a thrown jar slides a little and stops.
        b.friction = 0.6
        b.restitution = 0.12
        b.linearDamping = 0.15
        b.angularDamping = 0.8
        b.categoryBitMask = Category.jar
        b.collisionBitMask = Category.jar | Category.screenEdge
        b.contactTestBitMask = Category.jar
        b.usesPreciseCollisionDetection = true
        return b
    }

    var physics: SKPhysicsBody { body.physicsBody! }

    /// Puts the jar somewhere at once, at rest.
    func teleport(to p: CGPoint) {
        body.position = p
        body.zRotation = 0
        physics.velocity = .zero
        physics.angularVelocity = 0
        position = p
        angle = 0
        velocity = .zero
        spin = 0
        acceleration = .zero
    }

    // MARK: Frames

    /// A point in the jar's frame (design units, y-up, centred) on the screen.
    func toWorld(_ local: CGPoint) -> CGPoint {
        let c = cos(angle), s = sin(angle)
        let x = local.x * scale, y = local.y * scale
        return CGPoint(x: position.x + c * x - s * y, y: position.y + s * x + c * y)
    }

    func toLocal(_ world: CGPoint) -> CGPoint {
        let c = cos(angle), s = sin(angle)
        let dx = (world.x - position.x) / scale, dy = (world.y - position.y) / scale
        return CGPoint(x: c * dx + s * dy, y: -s * dx + c * dy)
    }

    func designToWorld(x: CGFloat, y: CGFloat) -> CGPoint { toWorld(JarGeometry.local(x: x, y: y)) }

    // MARK: Lid

    /// Whether the lid blocks the mouth for the contents right now.
    var sealed: Bool { capEdge.parent != nil }

    func setSealed(_ on: Bool) {
        if on, capEdge.parent == nil { lab.addChild(capEdge) }
        if !on, capEdge.parent != nil { capEdge.removeFromParent() }
    }

    /// A point in the lid's own frame (design units, y-up, from the hinge), given the lid's angle.
    func lidLocal(_ local: CGPoint) -> CGPoint {
        let hinge = JarGeometry.local(JarGeometry.lidHinge)
        let a = -lidSprite.zRotation
        let dx = local.x - hinge.x, dy = local.y - hinge.y
        return CGPoint(x: cos(a) * dx - sin(a) * dy, y: sin(a) * dx + cos(a) * dy)
    }

    var isHeld: Bool {
        if case .free = mode { return false }
        return true
    }
}
