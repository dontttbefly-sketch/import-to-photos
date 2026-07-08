import Darwin
import Foundation

struct UploadedMarker: Codable {
    let version: Int
    let importedAt: String
    let appIdentifier: String
}
enum UploadedMarkerStore {
    static func hasMarker(_ url: URL) -> Bool {
        let result = getxattr(url.path, AppConfig.uploadedMarkerAttributeName, nil, 0, 0, 0)
        return result >= 0
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
        do {
            let data = try markerData()
            let result = data.withUnsafeBytes { buffer in
                setxattr(url.path, AppConfig.uploadedMarkerAttributeName, buffer.baseAddress, data.count, 0, 0)
            }
            guard result == 0 else {
                return NSError(domain: NSPOSIXErrorDomain, code: Int(errno)).localizedDescription
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
