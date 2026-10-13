import Foundation

/// A jar nothing has been taken out of for a while gathers dust: a quiet sign of what has been
/// forgotten. The drawing code only asks how thick it is.
public enum Dust {
    /// How many days until the first dust, unless the user picks otherwise.
    public static let defaultDays = 7
    /// The dust is at its thickest after this many times the days it took to start.
    public static let fullAfter = 6.0

    /// Since when the jar's contents have been waiting: the later of the last time something was taken
    /// out and the day the oldest thing still in it went in, so a new thing in a long-empty jar does not
    /// arrive under a month of dust. Nil for an empty jar: nothing in it waits.
    public static func since(_ jar: Jar) -> Date? {
        guard let oldest = jar.items.map(\.addedAt).min() else { return nil }
        return max(oldest, jar.lastTakenAt ?? oldest)
    }

    /// 0 for a clean jar, 1 for the thickest dust. `days` is how long until the first dust; 0 or less
    /// means jars never gather any.
    public static func level(_ jar: Jar, after days: Int, now: Date = Date()) -> Double {
        guard days > 0, let since = since(jar) else { return 0 }
        let waited = now.timeIntervalSince(since) / 86_400
        let start = Double(days)
        return min(1, max(0, (waited - start) / (start * (fullAfter - 1))))
    }
}
