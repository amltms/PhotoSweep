import Foundation

/// Date, duration and count formatting.
///
/// `DateFormatter` instances are expensive to build, so the few needed are made once.
/// Nothing here formats a byte count: PhotoSweep deliberately never shows a "space freed"
/// figure, because the only ways to obtain a real per-asset size are undocumented private
/// KVC or downloading the iCloud original, and an estimate would be a plausible-looking
/// number that is wrong in a way nobody can check.
enum Formatters {

    private static let cardDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMMM yyyy"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private static let dateAndTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM yyyy 'at' HH:mm"
        return f
    }()

    /// "14 March 2024", or "Date unknown" — an asset really can have no creation date.
    static func cardDate(_ date: Date?) -> String {
        guard let date else { return "Date unknown" }
        return cardDateFormatter.string(from: date)
    }

    static func shortDate(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return shortDateFormatter.string(from: date)
    }

    static func dateAndTime(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return dateAndTimeFormatter.string(from: date)
    }

    static func monthYear(year: Int, month: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let date = Calendar(identifier: .gregorian).date(from: components) else {
            return "\(month)/\(year)"
        }
        return monthYearFormatter.string(from: date)
    }

    static func accessibleDate(_ date: Date?) -> String {
        guard let date else { return "an unknown date" }
        return cardDateFormatter.string(from: date)
    }

    /// "1:04" or "12:03:41" — video lengths, never rounded up to a lie.
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// "4,182" — grouped, because a six-figure library is not unusual.
    static func count(_ n: Int) -> String {
        n.formatted(.number.grouping(.automatic))
    }

    static func pixels(width: Int, height: Int) -> String {
        guard width > 0, height > 0 else { return "" }
        return "\(count(width)) × \(count(height))"
    }
}
