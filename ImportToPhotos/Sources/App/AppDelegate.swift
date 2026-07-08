import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let launchURLs: [URL]
    private let launchMode: LaunchMode
    private let imageScanner = ImageScanner()
    private let photosImporter = PhotosImporter()
    private lazy var copyService = FinderSyncCopyService(importer: photosImporter)
    private lazy var backgroundAgent = BackgroundJobAgent(
        jobQueue: FinderSyncJobQueue(),
        copyService: copyService
    )
    private var hasStarted = false

    init(launchURLs: [URL], launchMode: LaunchMode) {
        self.launchURLs = launchURLs
        self.launchMode = launchMode
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if !self.hasStarted {
                self.start(with: self.launchURLs)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if !hasStarted {
            start(with: urls)
        }
    }

    private func start(with urls: [URL]) {
        hasStarted = true
        switch launchMode {
        case .standardImport:
            startStandardImport(with: urls)
        case .finderSyncCopy:
            startFinderSyncCopy(with: urls)
        case .backgroundAgent:
            backgroundAgent.start()
        }
    }

    private func startStandardImport(with urls: [URL]) {
        let inputs = urls.isEmpty ? [AppConfig.defaultImportFolder()] : urls
        let images = imageScanner.collectImages(from: inputs)
        let selection = imageScanner.partitionUploadedImages(images)

        guard !images.isEmpty else {
            NoticePresenter.showAlert(title: "No Images Found", message: "No supported image files were found in the selected folder.")
            return
        }

        guard !selection.newImages.isEmpty else {
            NoticePresenter.showAlert(
                title: "No New Photos To Import",
                message: "Skipped \(selection.skippedImages.count) already marked image(s)."
            )
            return
        }

        photosImporter.requestAddOnlyAccess { [weak self] allowed in
            guard let self else {
                return
            }
            guard allowed else {
                NoticePresenter.showAlert(
                    title: "Photos Access Needed",
                    message: "Allow this app to add photos in System Settings > Privacy & Security > Photos, then run it again."
                )
                return
            }
            self.importStandardImages(selection.newImages, skippedCount: selection.skippedImages.count)
        }
    }

    private func startFinderSyncCopy(
        with urls: [URL],
        terminateAfterNotice: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        copyService.synchronize(urls: urls) { outcome in
            NoticePresenter.showTimedNotice(
                outcome.noticeKind,
                terminateAfterClose: terminateAfterNotice,
                completion: completion
            )
        }
    }

    private func importStandardImages(
        _ urls: [URL],
        skippedCount: Int,
        index: Int = 0,
        imported: Int = 0,
        importFailures: [ImportFailure] = [],
        markerFailures: [ImportFailure] = []
    ) {
        guard index < urls.count else {
            showStandardImportResult(
                imported: imported,
                skippedCount: skippedCount,
                importFailures: importFailures,
                markerFailures: markerFailures
            )
            return
        }

        let url = urls[index]
        photosImporter.importImage(at: url) { [weak self] success, errorMessage in
            guard let self else {
                return
            }

            var nextImportFailures = importFailures
            var nextMarkerFailures = markerFailures
            let nextImported = imported + (success ? 1 : 0)
            if success {
                if let markerError = UploadedMarkerStore.writeMarker(to: url) {
                    nextMarkerFailures.append(ImportFailure(url: url, message: markerError))
                }
            } else {
                nextImportFailures.append(ImportFailure(url: url, message: errorMessage ?? "Unknown error"))
            }
            self.importStandardImages(
                urls,
                skippedCount: skippedCount,
                index: index + 1,
                imported: nextImported,
                importFailures: nextImportFailures,
                markerFailures: nextMarkerFailures
            )
        }
    }

    private func showStandardImportResult(
        imported: Int,
        skippedCount: Int,
        importFailures: [ImportFailure],
        markerFailures: [ImportFailure]
    ) {
        if importFailures.isEmpty && markerFailures.isEmpty {
            NoticePresenter.showAlert(
                title: "Import Complete",
                message: "Imported \(imported) new image(s) into Photos.\nSkipped \(skippedCount) already marked image(s)."
            )
            return
        }

        var details: [String] = [
            "Imported \(imported) new image(s) into Photos.",
            "Skipped \(skippedCount) already marked image(s).",
            "Failed to import \(importFailures.count) image(s).",
            "Imported but not marked \(markerFailures.count) image(s)."
        ]

        let failedImports = importFailures.prefix(5).map { "- \($0.url.lastPathComponent): \($0.message)" }
        if !failedImports.isEmpty {
            details.append("\nImport failures:")
            details.append(contentsOf: failedImports)
        }

        let failedMarkers = markerFailures.prefix(5).map { "- \($0.url.lastPathComponent): \($0.message)" }
        if !failedMarkers.isEmpty {
            details.append("\nMarker failures:")
            details.append(contentsOf: failedMarkers)
        }

        NoticePresenter.showAlert(
            title: "Import Finished With Errors",
            message: details.joined(separator: "\n")
        )
    }
}
