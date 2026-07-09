import Foundation
import UniformTypeIdentifiers

struct ImageSelection {
    let newImages: [URL]
    let skippedImages: [URL]
}

struct ImageScanner {
    func collectImages(from inputs: [URL]) -> [URL] {
        var seen = Set<String>()
        var results: [URL] = []
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        let toolDirectoryPath = bundleURL.pathExtension.lowercased() == "app"
            ? bundleURL.deletingLastPathComponent().path
            : nil
        let resourceKeys: Set<URLResourceKey> = [
            .contentTypeKey,
            .isDirectoryKey,
            .isPackageKey,
            .fileSizeKey
        ]

        func isInsideToolDirectory(_ url: URL) -> Bool {
            guard let toolDirectoryPath else {
                return false
            }
            let path = url.standardizedFileURL.path
            return path == toolDirectoryPath || path.hasPrefix(toolDirectoryPath + "/")
        }

        func addIfImage(_ url: URL, contentType: UTType?, isDirectory: Bool?, fileSize: Int?) {
            let standardized = url.standardizedFileURL
            guard !isInsideToolDirectory(standardized) else {
                return
            }
            guard ImageTypePolicy.isStrictlySupportedImageFile(
                standardized,
                contentType: contentType,
                isDirectory: isDirectory,
                fileSize: fileSize
            ) else {
                return
            }
            let path = standardized.path
            guard !seen.contains(path) else {
                return
            }
            seen.insert(path)
            results.append(standardized)
        }

        for input in inputs {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: input.path, isDirectory: &isDirectory) else {
                continue
            }

            if !isDirectory.boolValue {
                let values = try? input.resourceValues(forKeys: resourceKeys)
                addIfImage(
                    input,
                    contentType: values?.contentType,
                    isDirectory: values?.isDirectory,
                    fileSize: values?.fileSize
                )
                continue
            }

            guard let enumerator = FileManager.default.enumerator(
                at: input,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                if isInsideToolDirectory(url) {
                    enumerator.skipDescendants()
                    continue
                }

                let values = try? url.resourceValues(forKeys: resourceKeys)

                if values?.isDirectory == true {
                    let name = url.lastPathComponent
                    let ext = url.pathExtension.lowercased()
                    if values?.isPackage == true
                        || ext == "app"
                        || ext == "photoslibrary"
                        || ext == "iconset"
                        || name == "ImportToPhotos" {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                addIfImage(
                    url,
                    contentType: values?.contentType,
                    isDirectory: values?.isDirectory,
                    fileSize: values?.fileSize
                )
            }
        }

        return results.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func partitionUploadedImages(_ images: [URL]) -> ImageSelection {
        var newImages: [URL] = []
        var skippedImages: [URL] = []

        for image in images {
            if UploadedMarkerStore.hasMarker(image) {
                skippedImages.append(image)
            } else {
                newImages.append(image)
            }
        }

        return ImageSelection(newImages: newImages, skippedImages: skippedImages)
    }
}
