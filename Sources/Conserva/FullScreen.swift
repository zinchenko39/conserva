import AppKit

/// Whether a screen is showing a full screen app. The jars stay away then: a film or a slide show
/// is not the place for them, and a floating panel would sit on top of it.
///
/// AppKit does not say what kind of Space a display is on; the window server does, through two
/// private calls that window managers have relied on for years and that need no permission. Each
/// display comes back as a dictionary whose "Current Space" carries a "type", 4 for full screen.
enum FullScreen {
    @_silgen_name("CGSMainConnectionID") private static func connection() -> Int32
    @_silgen_name("CGSCopyManagedDisplaySpaces") private static func displaySpaces(_ connection: Int32) -> CFArray

    private static let fullScreenType = 4

    static func isActive(on screen: NSScreen) -> Bool {
        guard let displays = displaySpaces(connection()) as? [[String: Any]] else { return false }
        // One entry covers every screen when "Displays have separate Spaces" is off; otherwise the
        // screen is found by its display's UUID.
        let display = displays.count == 1 ? displays.first : displays.first { ($0["Display Identifier"] as? String) == uuid(of: screen) }
        guard let space = display?["Current Space"] as? [String: Any] else { return false }
        return space["type"] as? Int == fullScreenType
    }

    private static func uuid(of screen: NSScreen) -> String? {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
