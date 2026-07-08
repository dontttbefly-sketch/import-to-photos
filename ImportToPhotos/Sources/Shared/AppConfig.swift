import Darwin
import Foundation

enum AppConfig {
    static let uploadedMarkerAttributeName = "local.import-to-photos.uploaded"
    static let finderSyncJobNotificationName = Notification.Name("local.import-to-photos.sync-job")
    static let finderSyncExtensionContainerIdentifier = "local.import-to-photos.finder-sync"

    static func defaultImportFolder() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["IMPORT_TO_PHOTOS_DEFAULT_FOLDER"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath).standardizedFileURL
        }

        if let configuredFolder = Bundle.main.url(forResource: "DefaultImportFolder", withExtension: "txt"),
           let configuredPath = try? String(contentsOf: configuredFolder, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredPath.isEmpty {
            return URL(fileURLWithPath: configuredPath).standardizedFileURL
        }

        return realUserHomeDirectory()
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("ImportToPhotos", isDirectory: true)
            .standardizedFileURL
    }

    static func finderSyncJobDirectory() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["IMPORT_TO_PHOTOS_JOB_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath, isDirectory: true).standardizedFileURL
        }

        return finderSyncSharedSupportDirectory()
            .appendingPathComponent("jobs", isDirectory: true)
            .standardizedFileURL
    }

    static func finderSyncHeartbeatURL() -> URL {
        finderSyncSharedSupportDirectory()
            .appendingPathComponent("finder-sync-heartbeat.log", isDirectory: false)
            .standardizedFileURL
    }

    static func appLogURL() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["IMPORT_TO_PHOTOS_APP_LOG_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath, isDirectory: false).standardizedFileURL
        }

        return realUserHomeDirectory()
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("ImportToPhotos", isDirectory: true)
            .appendingPathComponent("app.log", isDirectory: false)
            .standardizedFileURL
    }

    static func finderSyncSharedSupportDirectory() -> URL {
        realUserHomeDirectory()
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent(finderSyncExtensionContainerIdentifier, isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("ImportToPhotos", isDirectory: true)
            .standardizedFileURL
    }

    static func realUserHomeDirectory() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["IMPORT_TO_PHOTOS_HOME_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath, isDirectory: true)
                .standardizedFileURL
        }

        if let passwordRecord = getpwuid(getuid()),
           let homeDirectory = passwordRecord.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: homeDirectory), isDirectory: true)
                .standardizedFileURL
        }

        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .standardizedFileURL
    }
}
