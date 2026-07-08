import Foundation
import OSLog

enum FinderSyncLogger {
    private static let logger = Logger(
        subsystem: "local.import-to-photos.finder-sync",
        category: "FinderSync"
    )

    static var isVerbose: Bool {
        ProcessInfo.processInfo.environment["IMPORT_TO_PHOTOS_VERBOSE_FINDER_SYNC"] == "1"
    }

    static func log(_ message: String) {
        writeHeartbeat(reason: message)
        logger.info("\(message, privacy: .public)")

        guard let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            logger.error("container log unavailable: missing application support directory")
            return
        }

        let logDirectory = supportDirectory
            .appendingPathComponent("ImportToPhotos", isDirectory: true)
        let logURL = logDirectory.appendingPathComponent("finder-sync.log")

        FileLogWriter.append(message, to: logURL) { errorMessage in
            logger.error("container log failed: \(errorMessage, privacy: .public)")
        }
    }

    static func writeHeartbeat(reason: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let sanitizedReason = reason.replacingOccurrences(of: "\n", with: " ")
        FileLogWriter.write(
            "\(timestamp) \(sanitizedReason)",
            to: AppConfig.finderSyncHeartbeatURL()
        ) { errorMessage in
            logger.error("heartbeat failed: \(errorMessage, privacy: .public)")
        }
    }
}
