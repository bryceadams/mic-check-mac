import Foundation
import os

/// Minimal file logger for diagnosing audio issues: ~/Library/Logs/MicCheck.log, capped at 512 KB.
/// Only failures and one-off events are logged; nothing per-buffer or per-panel-open.
enum DebugLog {
    private static let osLog = Logger(subsystem: "dev.bryceadams.MicCheck", category: "debug")
    private static let queue = DispatchQueue(label: "dev.bryceadams.MicCheck.log")
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("MicCheck.log")
    }()
    private static let stamp: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()

    static func write(_ message: String) {
        osLog.notice("\(message)")
        let line = "\(stamp.string(from: Date())) \(message)\n"
        queue.async {
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 512 * 1024 {
                try? FileManager.default.removeItem(at: url)
            }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
