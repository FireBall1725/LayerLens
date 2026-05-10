import Foundation

/// Severity levels for the `Log` API. Numeric ordering reflects severity:
/// `debug < info < warn < error`. Comparable, so the runtime gate can be a
/// simple `level >= Log.minimumLevel`.
public enum LogLevel: Int, Sendable, Comparable, CaseIterable {
    case debug = 0
    case info  = 1
    case warn  = 2
    case error = 3

    public var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info:  return "INFO"
        case .warn:  return "WARN"
        case .error: return "ERROR"
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Log API for the app + core. Emissions go through `print`, which the
/// LayerLens app target redirects to `~/Library/Logs/LayerLens/LayerLens.log`
/// at startup, so the same line shows up in both the Logs tab and a
/// `tail -f` against the log file.
///
/// `Log.minimumLevel` (default `.info`) gates output. Set from
/// `Preferences.logLevel`; updates take effect on the next emission.
///
/// `nonisolated(unsafe)` on `minimumLevel` is fine: a race only ever
/// causes a single line to be over- or under-emitted at the moment of a
/// preference change. No lock so hot paths (poll heartbeat, lighting
/// tx/rx) don't pay for one.
public enum Log {
    nonisolated(unsafe) public static var minimumLevel: LogLevel = .info

    public static func debug(_ message: @autoclosure () -> String) {
        emit(.debug, message)
    }

    public static func info(_ message: @autoclosure () -> String) {
        emit(.info, message)
    }

    public static func warn(_ message: @autoclosure () -> String) {
        emit(.warn, message)
    }

    public static func error(_ message: @autoclosure () -> String) {
        emit(.error, message)
    }

    private static func emit(_ level: LogLevel, _ message: () -> String) {
        guard level >= minimumLevel else { return }
        let stamp = formatter.string(from: Date())
        print("[\(stamp) \(level.label)] \(message())")
    }

    /// Wall-clock prefix on every line. Local time, second resolution.
    /// Enough to correlate against macOS Console / Activity Monitor when
    /// chasing a hang.
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
