import Foundation

public enum ByteFormatting {
    public static func format(bytes: UInt64, raw: Bool) -> String {
        raw ? String(bytes) : humanReadable(bytes)
    }

    public static func humanReadable(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB", "EB"]

        if bytes < 1024 {
            return "\(bytes) B"
        }

        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024.0, unitIndex < units.count - 1 {
            value /= 1024.0
            unitIndex += 1
        }

        if value >= 10.0 || value.rounded() == value {
            return String(format: "%.0f %@", value, units[unitIndex])
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }
}
