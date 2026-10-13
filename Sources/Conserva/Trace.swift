import ConservaCore
import Foundation

/// A record of the shelf's comings and goings for finding out why it did not come when called:
/// one short line per event, in `trace.log` next to `shelf.json`, only while the `trace` default is
/// on (`defaults write app.conserva.Conserva trace -bool true`). Never anything the user put in a jar.
@MainActor
enum Trace {
    static let enabled = UserDefaults.standard.bool(forKey: "trace")
    private static let url = AppPaths.home.appendingPathComponent("trace.log")
    private static let limit = 512 * 1024
    private static let clock = ISO8601DateFormatter()

    static func log(_ event: @autoclosure () -> String) {
        guard enabled else { return }
        let line = "\(clock.string(from: Date())) \(event())\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            // Started over once it is big enough: this is a notebook, not an archive.
            if (try? handle.seekToEnd()) ?? 0 > UInt64(limit) { try? handle.truncate(atOffset: 0) }
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
