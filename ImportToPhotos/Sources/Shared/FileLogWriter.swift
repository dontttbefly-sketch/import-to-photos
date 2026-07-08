import Darwin
import Foundation

enum FileLogWriter {
    static func write(_ message: String, to logURL: URL, fallback: (String) -> Void) {
        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard let data = "\(message)\n".data(using: .utf8) else {
                return
            }
            try data.write(to: logURL, options: [.atomic])
        } catch {
            fallback(error.localizedDescription)
        }
    }

    static func append(_ message: String, to logURL: URL, fallback: (String) -> Void) {
        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] \(message)\n"
            guard let data = line.data(using: .utf8) else {
                return
            }

            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: logURL)
            flock(handle.fileDescriptor, LOCK_EX)
            defer {
                flock(handle.fileDescriptor, LOCK_UN)
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            fallback(error.localizedDescription)
        }
    }
}
