import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImportSupportStatus: Equatable {
    case supported
    case possibleRaw(String)
    case unsupported(String)

    var cliLabel: String {
        switch self {
        case .supported:
            return "SUPPORTED"
        case .possibleRaw:
            return "POSSIBLE_RAW"
        case .unsupported:
            return "UNSUPPORTED"
        }
    }

    var message: String {
        switch self {
        case .supported:
            return "ImageIO can read this file."
        case .possibleRaw(let message), .unsupported(let message):
            return message
        }
    }

    var canAttemptPhotosImport: Bool {
        switch self {
        case .supported, .possibleRaw:
            return true
        case .unsupported:
            return false
        }
    }
}

enum ImageTypePolicy {
    static let supportedImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp",
        "avif", "hif", "heics", "heifs", "jp2", "j2k", "jpf", "jpx",
        "dng", "cr2", "cr3", "nef", "arw", "raf", "rw2", "orf",
        "srw", "pef", "dcr", "kdc", "mrw", "nrw", "rwl", "3fr", "erf", "mef",
        "mos", "x3f", "srf", "sr2", "raw"
    ]

    static let rawImageExtensions: Set<String> = [
        "dng", "cr2", "cr3", "nef", "arw", "raf", "rw2", "orf",
        "srw", "pef", "dcr", "kdc", "mrw", "nrw", "rwl", "3fr", "erf", "mef",
        "mos", "x3f", "srf", "sr2", "raw"
    ]

    static let finderSyncExcludedPathComponents: Set<String> = [
        ".git", "node_modules", ".venv", "venv", "__pycache__", ".build", "build",
        "DerivedData", ".cache", ".npm", ".pnpm-store", ".swiftpm", ".gradle", "Pods"
    ]

    static let finderSyncExcludedHomeChildren: Set<String> = [
        "Library", ".Trash", "Applications"
    ]

    static func hasSupportedImageExtension(_ url: URL) -> Bool {
        supportedImageExtensions.contains(url.pathExtension.lowercased())
    }

    static func hasRawImageExtension(_ url: URL) -> Bool {
        rawImageExtensions.contains(url.pathExtension.lowercased())
    }

    static func isSupportedImage(_ url: URL, contentType: UTType?) -> Bool {
        if hasSupportedImageExtension(url) {
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

    static func isFinderSyncExcludedPath(
        _ url: URL,
        homeDirectory: URL = AppConfig.realUserHomeDirectory()
    ) -> Bool {
        let standardized = url.standardizedFileURL
        let pathComponents = standardized.pathComponents.filter { $0 != "/" }
        if pathComponents.contains(where: { finderSyncExcludedPathComponents.contains($0) }) {
            return true
        }

        let homePath = homeDirectory.standardizedFileURL.path
        let path = standardized.path
        guard path == homePath || path.hasPrefix(homePath + "/") else {
            return false
        }

        let relativePath = String(path.dropFirst(homePath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let firstComponent = relativePath.split(separator: "/").first else {
            return false
        }

        return finderSyncExcludedHomeChildren.contains(String(firstComponent))
    }

    static func isFinderSyncEligibleImage(_ url: URL) -> Bool {
        isFinderSyncMenuCandidate(url)
    }

    static func isFinderSyncMenuCandidate(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        guard !isFinderSyncExcludedPath(standardized) else {
            return false
        }

        let hasKnownImageExtension = hasSupportedImageExtension(standardized)
        if !hasKnownImageExtension && !standardized.pathExtension.isEmpty {
            return false
        }

        guard !UploadedMarkerStore.hasMarker(standardized) else {
            return false
        }

        let resourceKeys: Set<URLResourceKey> = hasKnownImageExtension
            ? [.isDirectoryKey]
            : [.contentTypeKey, .isDirectoryKey]
        let values = try? standardized.resourceValues(forKeys: resourceKeys)
        if values?.isDirectory == true {
            return false
        }

        if hasKnownImageExtension {
            return true
        }

        return isSupportedImage(standardized, contentType: values?.contentType)
    }

    static func isImportExecutionCandidate(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        guard isFinderSyncMenuCandidate(standardized) else {
            return false
        }

        return importSupportStatus(for: standardized).canAttemptPhotosImport
    }

    static func isStrictlySupportedImageFile(_ url: URL, contentType: UTType? = nil) -> Bool {
        importSupportStatus(for: url, contentType: contentType).canAttemptPhotosImport
    }

    static func importSupportStatus(for url: URL, contentType: UTType? = nil) -> ImportSupportStatus {
        let standardized = url.standardizedFileURL
        let values = try? standardized.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey, .fileSizeKey])

        if values?.isDirectory == true {
            return .unsupported("Directory is not an image file.")
        }

        if values?.fileSize == 0 {
            return .unsupported("File is empty.")
        }

        let resolvedContentType = contentType ?? values?.contentType
        guard isSupportedImage(standardized, contentType: resolvedContentType) else {
            return .unsupported("Unsupported file type.")
        }

        if hasRawImageExtension(standardized) {
            return .possibleRaw("RAW import depends on Photos and this macOS version.")
        }

        guard let imageSource = CGImageSourceCreateWithURL(standardized as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0 else {
            return .unsupported("Unsupported or invalid image data.")
        }

        return .supported
    }

    static func importExecutionFailureMessage(for url: URL) -> String? {
        let standardized = url.standardizedFileURL
        guard isFinderSyncMenuCandidate(standardized) else {
            return "Not eligible"
        }

        let status = importSupportStatus(for: standardized)
        return status.canAttemptPhotosImport ? nil : status.message
    }

    static func supportSummary(for url: URL) -> String {
        let standardized = url.standardizedFileURL
        let status = importSupportStatus(for: standardized)
        return "\(status.cliLabel) \(standardized.path) - \(status.message)"
    }

    static func isFinderSyncEligibleSelection(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else {
            return false
        }
        return urls.allSatisfy(isFinderSyncEligibleImage)
    }
}
