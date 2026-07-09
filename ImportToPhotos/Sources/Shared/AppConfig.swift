import Darwin
import Foundation

enum AppConfig {
    static let uploadedMarkerAttributeName = "local.import-to-photos.uploaded"
    static let finderSyncJobNotificationName = Notification.Name("local.import-to-photos.sync-job")
    static let finderSyncExtensionContainerIdentifier = "local.import-to-photos.finder-sync"

    static func defaultImportFolder() -> URL {
        if let overridePath = settingValue(named: "IMPORT_TO_PHOTOS_DEFAULT_FOLDER") {
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

    static func finderSyncKeepCopyEnabled() -> Bool {
        guard let value = settingValue(named: "IMPORT_TO_PHOTOS_KEEP_COPY") else {
            return false
        }

        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
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

    static func importedRecordStoreURL() -> URL {
        realUserHomeDirectory()
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("ImportToPhotos", isDirectory: true)
            .appendingPathComponent("imported-records.jsonl", isDirectory: false)
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

    private static func settingValue(named name: String) -> String? {
        if let environmentValue = ProcessInfo.processInfo.environment[name]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !environmentValue.isEmpty {
            return environmentValue
        }

        guard let settingsValue = settingsFileValues()[name]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !settingsValue.isEmpty else {
            return nil
        }

        return settingsValue
    }

    private static func settingsFileURL() -> URL {
        realUserHomeDirectory()
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("ImportToPhotos", isDirectory: true)
            .appendingPathComponent("settings.env", isDirectory: false)
            .standardizedFileURL
    }

    private static func settingsFileValues() -> [String: String] {
        guard let contents = try? String(contentsOf: settingsFileURL(), encoding: .utf8) else {
            return [:]
        }

        var values: [String: String] = [:]
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else {
                continue
            }

            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2,
               ((value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                (value.hasPrefix("'") && value.hasSuffix("'"))) {
                value.removeFirst()
                value.removeLast()
            }

            if !key.isEmpty {
                values[key] = value
            }
        }

        return values
    }
}
