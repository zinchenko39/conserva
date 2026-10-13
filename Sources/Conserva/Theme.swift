import AppKit
import CoreText

/// All colors and faces in one place. The jars themselves are glass, paper
/// and plastic: they look the same in light and dark, so most tokens have one
/// value. The card follows the system appearance through the system colors.
enum Theme {
    // Glass: clear, so it shows by its edges and highlights; only where the light crosses
    // a lot of it (the walls seen edge-on, the heel, the lip) does it turn cool grey, then green.
    static let glassTint = NSColor(hex: 0xDCE7E9)
    static let glassEdge = NSColor(hex: 0x9FB5BA)
    /// The thickest glass, where soda-lime glass shows its faint green.
    static let glassThick = NSColor(hex: 0x7FA5A1)
    static let glassLine = NSColor(hex: 0x22313A, alpha: 0.28)
    /// A thin dark line round the jar, so it still has an edge on a white desktop.
    static let glassOutline = NSColor(hex: 0x22313A, alpha: 0.38)

    // The swing-top lid: a glass lid, an orange rubber seal, zinc-plated wire.
    static let gasket = NSColor(hex: 0xEE5A24)
    static let gasketLight = NSColor(hex: 0xF57E48)
    static let gasketShade = NSColor(hex: 0xB43A12)
    /// The crease under the squeezed rubber.
    static let gasketEdge = NSColor(hex: 0x9C3010)
    // Polished steel wire: a dark rim, a light body, a darker reflection along it and a shine.
    static let wire = NSColor(hex: 0xC9CED2)
    static let wireDark = NSColor(hex: 0x4E555B)
    static let wireCore = NSColor(hex: 0x7F868C)
    static let gasketSheen = NSColor(hex: 0xFFB08A)

    // Paper: fresh slips, the yellow they turn, the label and the pen.
    static let paper = NSColor(hex: 0xFDFCF9)
    static let paperAged = NSColor(hex: 0xE8CF8F)
    static let labelPaper = NSColor(hex: 0xF4EBD3)
    static let labelEdge = NSColor(hex: 0xC9B98F)
    static let tape = NSColor(hex: 0xF2EFE4, alpha: 0.8)
    static let ink = NSColor(hex: 0x2D4A8A)
    static let slipText = NSColor(hex: 0x3A3A3C)
    static let slipMeta = NSColor(hex: 0x857C69)
    // Notebook paper for notes, a manila folder for files, and the stamp of a file's type.
    static let notebookRule = NSColor(hex: 0x8FB3D9, alpha: 0.55)
    static let notebookMargin = NSColor(hex: 0xD9827A, alpha: 0.6)
    static let folder = NSColor(hex: 0xE7C987)
    static let folderEdge = NSColor(hex: 0x8A6A2A, alpha: 0.45)
    static let folderText = NSColor(hex: 0x3B2F17)
    static let tagText = NSColor(hex: 0x2C2C2E)
    static let thingEdge = NSColor(hex: 0x000000, alpha: 0.18)

    // Links, each drawn as what it leads to.
    /// A video still: its paper frame, the dark stand-in until the still arrives, the play button.
    static let videoFrame = NSColor(hex: 0xFBFAF6)
    static let videoEmptyTop = NSColor(hex: 0x4A525C)
    static let videoEmptyBottom = NSColor(hex: 0x23272D)
    static let playDisc = NSColor(hex: 0x000000, alpha: 0.55)
    /// A post: a white card, its avatar, the site under the name, the text, the reactions bar.
    static let postCard = NSColor(hex: 0xFFFFFF)
    static let postAvatar = NSColor(hex: 0xC9B79C)
    static let postMeta = NSColor(hex: 0x86868B)
    static let postBar = NSColor(hex: 0xC7CBD1)
    /// An article: a clipping of newsprint.
    static let newsprint = NSColor(hex: 0xEFE9DB)
    static let newsInk = NSColor(hex: 0x1F1D1A)
    static let newsMeta = NSColor(hex: 0x8A8170)
    static let newsColumns = NSColor(hex: 0xA9A291)
    /// Code: a card of squared paper.
    static let graphPaper = NSColor(hex: 0xFBFBF6)
    static let graphGrid = NSColor(hex: 0x9FC2D9, alpha: 0.35)
    static let codeInk = NSColor(hex: 0x1D1D1F)
    static let codeMeta = NSColor(hex: 0x6E6E73)
    /// Music and podcasts: a cassette.
    static let cassetteBody = NSColor(hex: 0x2E2D31)
    static let cassetteRim = NSColor(hex: 0x45434A)
    static let cassetteWindow = NSColor(hex: 0x1E1D21)
    static let cassetteLabel = NSColor(hex: 0xF3EEE0)
    static let cassetteTape = NSColor(hex: 0x6B4A2E)
    static let cassetteFoot = NSColor(hex: 0x3A383E)
    /// A place: a folded piece of map with a pin in it.
    static let mapLand = NSColor(hex: 0xEEF0E6)
    static let mapWater = NSColor(hex: 0xA9D3E8)
    static let mapPark = NSColor(hex: 0xCFE3B8)
    static let mapRoad = NSColor(hex: 0xFFFFFF)
    static let mapMainRoad = NSColor(hex: 0xF2C66B)
    static let mapPin = NSColor(hex: 0xE0453A)
    /// A product: a cardboard price tag.
    static let kraft = NSColor(hex: 0xD9BC8C)
    static let kraftEdge = NSColor(hex: 0x9C7C4A)
    static let kraftInk = NSColor(hex: 0x2B241A)
    static let kraftMeta = NSColor(hex: 0x5A4528)
    static let barcodePaper = NSColor(hex: 0xF5EFE3)
    /// A document: a page with its corner folded.
    static let page = NSColor(hex: 0xFFFFFF)
    static let pageFold = NSColor(hex: 0xE4E6EA)
    static let pageLines = NSColor(hex: 0xC9CCD1)

    /// The stamp on a file's folder: red for PDF, blue for documents, green for tables, orange for slides.
    static func stamp(for ext: String) -> NSColor {
        switch ext.lowercased() {
        case "pdf": return NSColor(hex: 0xC2402F)
        case "doc", "docx", "pages", "rtf", "txt", "md", "odt": return NSColor(hex: 0x2B5BB5)
        case "xls", "xlsx", "numbers", "csv", "ods": return NSColor(hex: 0x2E7D4F)
        case "ppt", "pptx", "key", "odp": return NSColor(hex: 0xC8671E)
        default: return NSColor(hex: 0x6E6E73)
        }
    }

    static let floorShadow = NSColor(hex: 0x141420, alpha: 0.42)
    /// The rim of a jar something is being dragged over.
    static let dropTarget = NSColor.controlAccentColor

    // Card: system colors, so it follows light and dark.
    static let cardText = NSColor.labelColor
    static let cardSecondary = NSColor.secondaryLabelColor

    /// A site's colour: the average of its icon when the icon has a colour worth the name,
    /// otherwise the hue picked from its address.
    static func site(_ host: String, icon: CGImage?) -> NSColor {
        guard let icon, let mean = averageColor(icon) else { return favicon(for: host) }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        mean.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        guard s > 0.25, b > 0.2 else { return favicon(for: host) }
        return NSColor(hue: h, saturation: min(0.85, max(s, 0.45)), brightness: min(0.75, max(b, 0.45)), alpha: 1)
    }

    private static func averageColor(_ image: CGImage) -> NSColor? {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let alpha = CGFloat(pixel[3]) / 255
        guard alpha > 0.1 else { return nil }
        return NSColor(srgbRed: CGFloat(pixel[0]) / 255 / alpha, green: CGFloat(pixel[1]) / 255 / alpha,
                       blue: CGFloat(pixel[2]) / 255 / alpha, alpha: 1)
    }

    static func favicon(for host: String) -> NSColor {
        var h: UInt32 = 7
        for u in host.unicodeScalars { h = (h &* 31 &+ u.value) % 360 }
        return NSColor(hue: CGFloat(h) / 360, saturation: 0.52, brightness: 0.62, alpha: 1)
    }

    /// Paper between fresh and fully yellow.
    static func paper(aged amount: Double) -> NSColor {
        paper.blended(withFraction: CGFloat(amount), of: paperAged) ?? paper
    }

    // MARK: Faces

    /// The handwriting on the labels. Caveat ships with the app (SIL OFL).
    static func hand(_ size: CGFloat, bold: Bool = true) -> NSFont {
        Fonts.registerOnce()
        let weight: CGFloat = bold ? 700 : 600
        if let base = Fonts.caveat {
            let wght = 0x7767_6874 // 'wght'
            let desc = CTFontDescriptorCreateCopyWithVariation(base, wght as CFNumber, weight)
            return CTFontCreateWithFontDescriptor(desc, size, nil) as NSFont
        }
        return NSFont(name: "Bradley Hand", size: size) ?? .systemFont(ofSize: size, weight: .semibold)
    }

    static func ui(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    /// Headlines on a newspaper clipping.
    static func serif(_ size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }
}

enum Fonts {
    private(set) static var caveat: CTFontDescriptor?
    private static var registered = false

    static func registerOnce() {
        guard !registered else { return }
        registered = true
        guard let url = Localization.resources.url(forResource: "Caveat", withExtension: "ttf", subdirectory: "Fonts")
                ?? Localization.resources.url(forResource: "Caveat", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        caveat = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
