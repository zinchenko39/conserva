import Foundation
import Testing
@testable import ConservaCore

/// These set process-wide environment variables, so they run one at a time.
@Suite(.serialized)
struct AppPathsTests {
    @Test func theHomeIsInApplicationSupportUnlessMovedByTheEnvironment() {
        unsetenv("CONSERVA_HOME")
        #expect(AppPaths.home.path.hasSuffix("/Library/Application Support/Conserva"))

        setenv("CONSERVA_HOME", "/tmp/conserva-elsewhere", 1)
        defer { unsetenv("CONSERVA_HOME") }
        #expect(AppPaths.home.path == "/tmp/conserva-elsewhere")

        // Empty means unset, not a home at the root.
        setenv("CONSERVA_HOME", "", 1)
        #expect(AppPaths.home.path.hasSuffix("/Library/Application Support/Conserva"))
    }

    @Test func theTrashStandInIsOnlyThereWhenAsked() {
        unsetenv("CONSERVA_TRASH")
        #expect(AppPaths.trash == nil)
        setenv("CONSERVA_TRASH", "~/conserva-bin", 1)
        defer { unsetenv("CONSERVA_TRASH") }
        #expect(AppPaths.trash?.path.hasPrefix("/") == true)
        #expect(AppPaths.trash?.path.hasSuffix("/conserva-bin") == true)
    }
}
