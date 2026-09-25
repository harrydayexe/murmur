import Foundation

/// Formats dates with Obsidian/moment-style tokens:
/// `YYYY YY MMMM MMM MM M DD D dddd ddd HH H hh h mm ss A Z ZZ w ww`, with `[literal]` escapes.
/// Pure: names come from the given locale's calendar symbols.
struct DateTokenFormatter: Sendable {
    var timeZone: TimeZone
    var locale: Locale

    static let dateFormat = "YYYY-MM-DD"
    static let timeFormat = "HH:mm"
    static let obsidianDateTimeFormat = "YYYY-MM-DDTHH:mm:ss"
    static let isoDateTimeFormat = "YYYY-MM-DDTHH:mm:ssZ"
    static let weekdayFormat = "dddd"

    // Longest first, so `MMMM` wins over `MM`.
    private static let tokens = [
        "YYYY", "MMMM", "dddd",
        "MMM", "ddd",
        "YY", "MM", "DD", "HH", "hh", "mm", "ss", "ZZ", "ww",
        "M", "D", "H", "h", "A", "Z", "w",
    ]

    func string(from date: Date, format: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)

        var output = ""
        var index = format.startIndex
        while index < format.endIndex {
            if format[index] == "[" {
                if let close = format[index...].firstIndex(of: "]") {
                    output += format[format.index(after: index)..<close]
                    index = format.index(after: close)
                } else {
                    output += format[index...]
                    index = format.endIndex
                }
                continue
            }
            if let token = Self.tokens.first(where: { format[index...].hasPrefix($0) }) {
                output += value(for: token, parts: parts, date: date, calendar: calendar)
                index = format.index(index, offsetBy: token.count)
            } else {
                output.append(format[index])
                index = format.index(after: index)
            }
        }
        return output
    }

    private func value(for token: String, parts: DateComponents, date: Date, calendar: Calendar) -> String {
        let year = parts.year ?? 0, month = parts.month ?? 1, day = parts.day ?? 1
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0, second = parts.second ?? 0
        let weekdayIndex = (parts.weekday ?? 1) - 1
        let hour12 = hour % 12 == 0 ? 12 : hour % 12

        switch token {
        case "YYYY": return String(format: "%04d", year)
        case "YY": return String(format: "%02d", year % 100)
        case "MMMM": return calendar.monthSymbols[month - 1]
        case "MMM": return calendar.shortMonthSymbols[month - 1]
        case "MM": return String(format: "%02d", month)
        case "M": return String(month)
        case "DD": return String(format: "%02d", day)
        case "D": return String(day)
        case "dddd": return calendar.weekdaySymbols[weekdayIndex]
        case "ddd": return calendar.shortWeekdaySymbols[weekdayIndex]
        case "HH": return String(format: "%02d", hour)
        case "H": return String(hour)
        case "hh": return String(format: "%02d", hour12)
        case "h": return String(hour12)
        case "mm": return String(format: "%02d", minute)
        case "ss": return String(format: "%02d", second)
        case "A": return hour < 12 ? "AM" : "PM"
        case "Z": return offset(for: date, separator: ":")
        case "ZZ": return offset(for: date, separator: "")
        case "w", "ww":
            var iso = Calendar(identifier: .iso8601)
            iso.timeZone = timeZone
            let week = iso.component(.weekOfYear, from: date)
            return token == "ww" ? String(format: "%02d", week) : String(week)
        default: return token
        }
    }

    private func offset(for date: Date, separator: String) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let minutes = abs(seconds) / 60
        return String(format: "%@%02d%@%02d", sign, minutes / 60, separator, minutes % 60)
    }
}
