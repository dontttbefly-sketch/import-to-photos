import Foundation
import Photos

enum ImportFailureKind: String {
    case permanent
    case temporary
    case marker
}

struct ImportFailure {
    let url: URL
    let message: String
    let kind: ImportFailureKind
    let retrySourceURL: URL?
    let retryStagedURL: URL?

    init(
        url: URL,
        message: String,
        kind: ImportFailureKind = .temporary,
        retrySourceURL: URL? = nil,
        retryStagedURL: URL? = nil
    ) {
        self.url = url
        self.message = message
        self.kind = kind
        self.retrySourceURL = retrySourceURL
        self.retryStagedURL = retryStagedURL
    }
}

protocol PhotosImporting: AnyObject {
    func currentAddOnlyAccessAllowsImport() -> Bool
    func requestAddOnlyAccess(completion: @escaping (Bool) -> Void)
    func importImage(at url: URL, completion: @escaping (_ success: Bool, _ errorMessage: String?) -> Void)
}

final class PhotosImporter: PhotosImporting {
    func currentAddOnlyAccessAllowsImport() -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            return true
        default:
            return false
        }
    }

    func requestAddOnlyAccess(completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            switch status {
            case .authorized, .limited:
                completion(true)
            default:
                completion(false)
            }
        }
    }

    func importImage(at url: URL, completion: @escaping (_ success: Bool, _ errorMessage: String?) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
        }) { success, error in
            if let error = error as NSError? {
                completion(success, "\(error.localizedDescription) (\(error.domain) \(error.code))")
            } else {
                completion(success, nil)
            }
        }
    }
}
