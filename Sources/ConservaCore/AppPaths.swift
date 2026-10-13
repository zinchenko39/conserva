import Foundation

public enum AppPaths {
    /// `CONSERVA_TRASH`: a folder that stands in for the Trash, so a test instance never puts
    /// anything in the real one. Nil normally.
    public static var trash: URL? {
        guard let custom = ProcessInfo.processInfo.environment["CONSERVA_TRASH"], !custom.isEmpty else { return nil }
        return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// `~/Library/Application Support/Conserva`, or `CONSERVA_HOME` for a test
    /// instance that must not touch the real shelf.
    public static var home: URL {
        if let custom = ProcessInfo.processInfo.environment["CONSERVA_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Conserva", isDirectory: true)
    }
}
