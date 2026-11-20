import Foundation

// MARK: - Cached DateFormatters (Avoids Per-Tick Allocations)
enum AppDateFormatters {
    static let timeHHmm: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df
    }()

    static let fullDate: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMMM d, yyyy"
        return df
    }()

    static let monthYear: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMMM yyyy"
        return df
    }()

    static let readableDate: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMMM d, yyyy"
        return df
    }()

    static let weekdayFull: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEEE"
        return df
    }()
}
