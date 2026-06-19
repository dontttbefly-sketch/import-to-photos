import Darwin
import Foundation
import UniformTypeIdentifiers

let uploadedMarkerAttributeName = "local.import-to-photos.uploaded"
let finderSyncJobNotificationName = Notification.Name("local.import-to-photos.sync-job")
let finderSyncExtensionContainerIdentifier = "local.import-to-photos.finder-sync"

struct FinderSyncQueuedJob: Codable {
    let id: String
    let createdAt: String
    let paths: [String]
}

let supportedImageExtensions: Set<String> = [
    "jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp",
    "dng", "cr2", "cr3", "nef", "arw", "raf", "rw2", "orf"
]

struct UploadedMarker: Codable {
    let version: Int
    let importedAt: String
    let appIdentifier: String
}

func defaultImportFolder() -> URL {
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

    let bundleURL = Bundle.main.bundleURL
    if bundleURL.pathExtension.lowercased() == "app" {
        return bundleURL.deletingLastPathComponent().deletingLastPathComponent()
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}

func finderSyncJobDirectory() -> URL {
    finderSyncSharedSupportDirectory()
        .appendingPathComponent("jobs", isDirectory: true)
        .standardizedFileURL
}

func finderSyncSharedSupportDirectory() -> URL {
    let home: URL
    if let passwordRecord = getpwuid(getuid()),
       let homeDirectory = passwordRecord.pointee.pw_dir {
        home = URL(fileURLWithPath: String(cString: homeDirectory), isDirectory: true)
    } else {
        home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    return home
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Containers", isDirectory: true)
        .appendingPathComponent(finderSyncExtensionContainerIdentifier, isDirectory: true)
        .appendingPathComponent("Data", isDirectory: true)
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("ImportToPhotos", isDirectory: true)
        .standardizedFileURL
}

func isSupportedImage(_ url: URL, contentType: UTType?) -> Bool {
    let ext = url.pathExtension.lowercased()
    if supportedImageExtensions.contains(ext) {
        return true
    }

    guard let contentType else {
        return false
    }

    if contentType == .svg || contentType == .pdf || contentType.identifier == "com.apple.icns" {
        return false
    }

    return contentType.conforms(to: .image)
}

func hasUploadedMarker(_ url: URL) -> Bool {
    let result = getxattr(url.path, uploadedMarkerAttributeName, nil, 0, 0, 0)
    return result >= 0
}

func uploadedMarkerData() throws -> Data {
    let marker = UploadedMarker(
        version: 1,
        importedAt: ISO8601DateFormatter().string(from: Date()),
        appIdentifier: Bundle.main.bundleIdentifier ?? "local.import-to-photos"
    )
    return try JSONEncoder().encode(marker)
}

func writeUploadedMarker(to url: URL) -> String? {
    do {
        let data = try uploadedMarkerData()
        let result = data.withUnsafeBytes { buffer in
            setxattr(url.path, uploadedMarkerAttributeName, buffer.baseAddress, data.count, 0, 0)
        }
        guard result == 0 else {
            return NSError(domain: NSPOSIXErrorDomain, code: Int(errno)).localizedDescription
        }
        return nil
    } catch {
        return error.localizedDescription
    }
}

func isFinderSyncEligibleImage(_ url: URL) -> Bool {
    guard !hasUploadedMarker(url) else {
        return false
    }

    let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
    if values?.isDirectory == true {
        return false
    }

    return isSupportedImage(url, contentType: values?.contentType)
}

func isFinderSyncEligibleSelection(_ urls: [URL]) -> Bool {
    guard !urls.isEmpty else {
        return false
    }
    return urls.allSatisfy(isFinderSyncEligibleImage)
}
