import CoreGraphics

/// The shape of a 5-litre jar, in one design box of 300 × 430 units drawn
/// y-down like the artwork. `local` turns a design point into the y-up frame
/// centred on the jar that the scene and the physics use.
///
/// The proportions follow a real 5-litre jar: a thick lip with a groove under it
/// for the wire, a short neck about 55% of the body's width, sloping shoulders
/// reaching full width at a little over a quarter of the height, a straight body
/// and a thick rounded heel. Slips settle on the bottom, nothing escapes a shaken
/// jar with its lid shut, and everything pours out of one held upside down.
public enum JarGeometry {
    public static let box = CGSize(width: 300, height: 430)
    /// The point everything turns around: the middle of the design box.
    public static let pivot = CGPoint(x: 150, y: 215)

    /// The inside of the glass as an open chain; the gap between the first and
    /// last point is the mouth.
    public static let innerChain: [CGPoint] = [
        (88, 16), (88, 46), (79, 64), (58, 80), (37, 98), (28, 124), (28, 364), (39, 389), (70, 396),
        (230, 396), (261, 389), (272, 364), (272, 124), (263, 98), (242, 80), (221, 64), (212, 46), (212, 16),
    ].map { CGPoint(x: $0.0, y: $0.1) }

    /// Top of the rim. The cap sits on it.
    public static let mouthY: CGFloat = 16
    public static let mouthHalfWidth: CGFloat = 62
    /// Bottom of the glass, standing on the floor.
    public static let bottomY: CGFloat = 414
    /// Outer extent used to keep the jar above the floor when it tilts.
    public static let outerLeft: CGFloat = 22
    public static let outerRight: CGFloat = 278
    /// The wire hinge on the left of the mouth the lid swings on.
    public static let lidHinge = CGPoint(x: 68, y: 14)
    /// How far the lid swings back when open: past upright, resting against its hinge.
    public static let lidOpenAngle: CGFloat = 1.95
    /// The lid in its own frame, design units y-down from the hinge: glass, gasket and the wire
    /// round its edge, with the loop the lever catches and the tab of the rubber ring below.
    public static let lidRect = CGRect(x: -10, y: -22, width: 190, height: 36)
    /// The pivot of the wire lever on the right of the neck that clamps the lid down.
    public static let leverPivot = CGPoint(x: 236, y: 28)

    /// A thing whose centre rises past this, with the cap off, has left the jar.
    public static let escapeY: CGFloat = -8
    /// Grabbing above this line tilts the jar around its middle; below it carries it. It runs just
    /// under the neck, so only the neck (and the lid above it) turns the jar: the shoulders carry it.
    public static let tiltGripY: CGFloat = 64
    /// Where the paper label is stuck on, halfway up the jar; clicks there rename the jar, not pick a slip.
    public static let labelRect = CGRect(x: pivot.x - 88, y: pivot.y - 42, width: 176, height: 84)

    /// Each kind has a shape of its own, in design units: a tag for a link, a strip of notebook
    /// paper for a note, a folder for a file, a print with a white border for a picture.
    /// Two of the long ones side by side must lie flat on the 244-unit bottom, and each must be
    /// shorter corner to corner than the 124-unit neck is wide, with room for the thin skin the
    /// physics keeps round every body, so it goes through at any angle instead of wedging across.
    /// A photo stays under ~60 wide: two side by side must still pass the neck, or they jam.
    /// A link takes the shape of what it leads to (`LinkKind`); nil gives the luggage tag.
    public static func size(of kind: ItemKind, link: LinkKind? = nil) -> CGSize {
        switch kind {
        case .link: return size(of: link ?? .page)
        case .text: return CGSize(width: 110, height: 40)
        case .file: return CGSize(width: 104, height: 44)
        case .image: return CGSize(width: 58, height: 64)
        }
    }

    public static func size(of link: LinkKind) -> CGSize {
        switch link {
        case .video: return CGSize(width: 84, height: 60)
        case .post: return CGSize(width: 108, height: 42)
        case .article: return CGSize(width: 110, height: 38)
        case .code: return CGSize(width: 110, height: 38)
        case .audio: return CGSize(width: 84, height: 52)
        case .place: return CGSize(width: 82, height: 50)
        case .product: return CGSize(width: 92, height: 44)
        case .document: return CGSize(width: 50, height: 62)
        case .page: return CGSize(width: 112, height: 36)
        }
    }

    public static func size(of item: Item) -> CGSize { size(of: item.kind, link: item.linkKind) }

    /// Every shape a thing can take, for checking them all against the jar.
    public static var allSizes: [CGSize] {
        [ItemKind.text, .file, .image].map { size(of: $0) } + LinkKind.allCases.map { size(of: $0) }
    }

    /// Where the shoulders end: below this the inside is full width.
    public static let shoulderY: CGFloat = 124

    /// More than this many things in one jar would fill it past the shoulders.
    /// The rest wait underneath and come up as others are taken out.
    public static let maxLoose = 8

    public static func local(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - pivot.x, y: pivot.y - p.y)
    }

    public static func local(x: CGFloat, y: CGFloat) -> CGPoint { local(CGPoint(x: x, y: y)) }

    public static func design(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x + pivot.x, y: pivot.y - p.y)
    }

    /// Resting places for things of these sizes, in order, in rows from the bottom up, so a jar
    /// loaded at launch is already settled. Only as many as fit below the shoulders get a place;
    /// the caller lets the rest wait underneath.
    public static func restingSpots(for sizes: [CGSize]) -> [CGPoint] {
        let inner = (left: CGFloat(30), right: CGFloat(270), floor: CGFloat(394))
        let gap: CGFloat = 4
        var spots: [CGPoint] = []
        var rowBottom = inner.floor - 1
        var row: [CGSize] = []
        func place(_ row: [CGSize]) -> Bool {
            let height = row.map(\.height).max() ?? 0
            guard rowBottom - height >= shoulderY else { return false }
            let width = row.map(\.width).reduce(0, +) + gap * CGFloat(row.count - 1)
            var x = pivot.x - width / 2
            for size in row {
                spots.append(CGPoint(x: x + size.width / 2, y: rowBottom - size.height / 2))
                x += size.width + gap
            }
            rowBottom -= height + 2
            return true
        }
        for size in sizes {
            let width = row.map(\.width).reduce(0, +) + gap * CGFloat(row.count) + size.width
            if !row.isEmpty, width > inner.right - inner.left {
                guard place(row) else { return spots }
                row = []
            }
            row.append(size)
        }
        if !row.isEmpty { _ = place(row) }
        return spots
    }

    public static func isInside(_ p: CGPoint) -> Bool {
        p.x > 14 && p.x < 286 && p.y < 410 && p.y > escapeY
    }
}
