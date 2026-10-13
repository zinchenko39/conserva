import Foundation

/// Paper yellows and photos fade the longer they sit in a jar. The drawing
/// code only asks how far along that is.
public enum Aging {
    /// After this many days a slip is as yellow as it gets.
    public static let fullAfterDays = 30.0

    public static func days(since date: Date, now: Date = Date()) -> Int {
        max(0, Int(now.timeIntervalSince(date) / 86_400))
    }

    /// 0 for something put in today, 1 for something forgotten for a month or more.
    public static func yellowing(since date: Date, now: Date = Date()) -> Double {
        min(1, max(0, now.timeIntervalSince(date) / 86_400 / fullAfterDays))
    }
}
