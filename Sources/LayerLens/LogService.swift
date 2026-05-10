import Foundation
import AppKit

/// Single source of truth for where LayerLens writes its console output and
/// how the rest of the app finds / reveals / tails that file.
///
/// The app redirects stdout and stderr to `~/Library/Logs/LayerLens/LayerLens.log`
/// at launch. Every `print(...)` and OS-level write to fd 1/2 from then on
/// lands in that file; the menu bar exposes "Reveal log in Finder" and the
/// Settings → Logs tab live-tails it.
@MainActor
enum LogService {
    /// Directory: `~/Library/Logs/LayerLens/`
    static let logsDirectoryURL: URL = {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return lib.appendingPathComponent("Logs").appendingPathComponent("LayerLens")
    }()

    /// File: `~/Library/Logs/LayerLens/LayerLens.log`. Append-mode; never
    /// truncated automatically.
    static let logFileURL: URL = logsDirectoryURL.appendingPathComponent("LayerLens.log")

    /// Redirect stdout + stderr to `logFileURL`. Idempotent: safe to call
    /// from `applicationDidFinishLaunching` exactly once. Errors are
    /// swallowed (the app will keep working with stdio going to nowhere if
    /// the disk is misbehaved, and the symptom is "no log file appears" so
    /// the user can still file an issue).
    static func redirectStdioToLogFile() {
        let fm = FileManager.default
        try? fm.createDirectory(
            at: logsDirectoryURL,
            withIntermediateDirectories: true
        )
        let path = logFileURL.path
        // Append mode so a relaunch keeps prior context. freopen returns
        // nil on failure; ignore. The original stdout/stderr stay valid.
        _ = freopen(path, "a", stdout)
        _ = freopen(path, "a", stderr)
        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IOLBF, 0)
        // Bookend each launch so the tail view's "current session" is
        // visually obvious when scrolling. Emit through the raw stdio
        // path (not Log.info) so this header appears regardless of the
        // user's current log level. It's a structural divider, not a
        // debug-grade event.
        let stamp = ISO8601DateFormatter().string(from: Date())
        print("=== LayerLens session started at \(stamp) ===")
    }

    /// Open Finder to the log file (selecting it). Falls back to opening
    /// just the directory if the file doesn't exist yet.
    static func revealLogInFinder() {
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
        } else {
            NSWorkspace.shared.open(logsDirectoryURL)
        }
    }

    /// Read the tail of the log. Returns at most `maxBytes` of the file's
    /// final bytes, decoded as UTF-8 with replacement on invalid sequences.
    static func tail(maxBytes: Int = 256 * 1024) -> String {
        guard let handle = try? FileHandle(forReadingFrom: logFileURL) else {
            return ""
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Truncate the log file to zero length. Used by the "Clear log" button
    /// in Settings → Logs. Keeps the file open for stdout/stderr writes;
    /// the OS handles the truncation transparently for the existing fd.
    static func clearLog() {
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            try? handle.truncate(atOffset: 0)
            try? handle.close()
        }
    }
}
