import Darwin
import Foundation

struct UploadedMarker: Codable {
    let version: Int
    let importedAt: String
    let appIdentifier: String
}

struct UploadedMarkerRecord: Codable {
    let version: Int
    let importedAt: String
    let path: String
    let fileSize: Int?
    let modificationDate: String?
}

enum UploadedMarkerStore {
    static func hasMarker(_ url: URL) -> Bool {
        let result = getxattr(url.path, AppConfig.uploadedMarkerAttributeName, nil, 0, 0, 0)
        if result >= 0 {
            return true
        }

        return hasImportedRecord(for: url)
    }

    static func markerData() throws -> Data {
        let marker = UploadedMarker(
            version: 1,
            importedAt: ISO8601DateFormatter().string(from: Date()),
            appIdentifier: Bundle.main.bundleIdentifier ?? "local.import-to-photos"
        )
        return try JSONEncoder().encode(marker)
    }

    static func writeMarker(to url: URL) -> String? {
        let xattrError: String?
        do {
            let data = try markerData()
            if shouldForceMarkerWriteFailure {
                xattrError = "Forced marker write failure"
            } else {
                let result = data.withUnsafeBytes { buffer in
                    setxattr(url.path, AppConfig.uploadedMarkerAttributeName, buffer.baseAddress, data.count, 0, 0)
                }
                xattrError = result == 0
                    ? nil
                    : NSError(domain: NSPOSIXErrorDomain, code: Int(errno)).localizedDescription
            }
        } catch {
            xattrError = error.localizedDescription
        }

        guard let xattrError else {
            return nil
        }

        if let recordError = appendImportedRecord(for: url) {
            return "\(xattrError); fallback record failed: \(recordError)"
        }

        return nil
    }

    private static var shouldForceMarkerWriteFailure: Bool {
        ProcessInfo.processInfo.environment["IMPORT_TO_PHOTOS_ENABLE_TEST_HOOKS"] == "1"
            && ProcessInfo.processInfo.environment["IMPORT_TO_PHOTOS_FORCE_MARKER_WRITE_FAILURE"] == "1"
    }

    private static func hasImportedRecord(for url: URL) -> Bool {
        guard let contents = try? String(contentsOf: AppConfig.importedRecordStoreURL(), encoding: .utf8) else {
            return false
        }

        let expected = recordIdentity(for: url)
        let decoder = JSONDecoder()
        for line in contents.components(separatedBy: .newlines) where !line.isEmpty {
            guard let data = line.data(using: .utf8),
                  let record = try? decoder.decode(UploadedMarkerRecord.self, from: data) else {
                continue
            }
            guard record.path == expected.path else {
                continue
            }
            if let recordSize = record.fileSize,
               let expectedSize = expected.fileSize,
               recordSize != expectedSize {
                continue
            }
            if let recordDate = record.modificationDate,
               let expectedDate = expected.modificationDate,
               recordDate != expectedDate {
                continue
            }
            return true
        }

        return false
    }

    private static func appendImportedRecord(for url: URL) -> String? {
        do {
            let record = recordIdentity(for: url)
            let data = try JSONEncoder().encode(record)
            guard let line = String(data: data, encoding: .utf8)?.appending("\n"),
                  let lineData = line.data(using: .utf8) else {
                return "Could not encode imported record."
            }

            let storeURL = AppConfig.importedRecordStoreURL()
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: storeURL.path) {
                FileManager.default.createFile(atPath: storeURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: storeURL)
            flock(handle.fileDescriptor, LOCK_EX)
            defer {
                flock(handle.fileDescriptor, LOCK_UN)
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: lineData)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private static func recordIdentity(for url: URL) -> UploadedMarkerRecord {
        let standardized = url.standardizedFileURL
        let values = try? standardized.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let modificationDate = values?.contentModificationDate.map {
            ISO8601DateFormatter().string(from: $0)
        }
        return UploadedMarkerRecord(
            version: 1,
            importedAt: ISO8601DateFormatter().string(from: Date()),
            path: standardized.path,
            fileSize: values?.fileSize,
            modificationDate: modificationDate
        )
    }
}
