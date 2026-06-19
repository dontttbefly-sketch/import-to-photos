import AppKit
import Foundation
import Photos

private struct ImportFailure {
    let url: URL
    let message: String
}

private struct ImageSelection {
    let newImages: [URL]
    let skippedImages: [URL]
}

private struct FinderSyncCopyJob {
    let sourceURL: URL
    let backupURL: URL
}

private func logImportToPhotos(_ message: String) {
    let logDirectory = URL(fileURLWithPath: "/tmp/local.import-to-photos", isDirectory: true)
    let logURL = logDirectory.appendingPathComponent("app.log", isDirectory: false)

    do {
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }

        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: logURL)
        }
    } catch {
        NSLog("ImportToPhotos log failed: \(error.localizedDescription)")
    }
}

private func normalizedInputURLs(from arguments: [String]) -> [URL] {
    let urls = explicitInputURLs(from: arguments)
    if urls.isEmpty {
        return [defaultImportFolder()]
    }
    return urls
}

private func explicitInputURLs(from arguments: [String]) -> [URL] {
    arguments.dropFirst()
        .filter { !$0.hasPrefix("-") }
        .map { URL(fileURLWithPath: $0).standardizedFileURL }
}

private func collectImages(from inputs: [URL]) -> [URL] {
    var seen = Set<String>()
    var results: [URL] = []
    let bundleURL = Bundle.main.bundleURL.standardizedFileURL
    let toolDirectoryPath = bundleURL.pathExtension.lowercased() == "app"
        ? bundleURL.deletingLastPathComponent().path
        : nil
    let resourceKeys: Set<URLResourceKey> = [
        .contentTypeKey,
        .isDirectoryKey,
        .isPackageKey
    ]

    func isInsideToolDirectory(_ url: URL) -> Bool {
        guard let toolDirectoryPath else {
            return false
        }
        let path = url.standardizedFileURL.path
        return path == toolDirectoryPath || path.hasPrefix(toolDirectoryPath + "/")
    }

    func addIfImage(_ url: URL, contentType: UTType?) {
        let standardized = url.standardizedFileURL
        guard !isInsideToolDirectory(standardized) else {
            return
        }
        guard isSupportedImage(standardized, contentType: contentType) else {
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
            addIfImage(input, contentType: values?.contentType)
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
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

            if isDirectory.boolValue {
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

            addIfImage(url, contentType: values?.contentType)
        }
    }

    return results.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
}

private func partitionUploadedImages(_ images: [URL]) -> ImageSelection {
    var newImages: [URL] = []
    var skippedImages: [URL] = []

    for image in images {
        if hasUploadedMarker(image) {
            skippedImages.append(image)
        } else {
            newImages.append(image)
        }
    }

    return ImageSelection(newImages: newImages, skippedImages: skippedImages)
}

private func showAlert(title: String, message: String) {
    DispatchQueue.main.async {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
        NSApp.terminate(nil)
    }
}

private var transientNoticePanel: NSPanel?

private func showTimedNotice(
    _ message: String,
    terminateAfterClose: Bool = true,
    completion: (() -> Void)? = nil
) {
    DispatchQueue.main.async {
        NSApp.setActivationPolicy(.accessory)
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let textWidth = ceil((message as NSString).size(withAttributes: [.font: font]).width)
        let size = NSSize(width: min(max(textWidth + 74, 156), 220), height: 44)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let finalFrame = NSRect(
            x: screenFrame.maxX - size.width - 28,
            y: screenFrame.maxY - size.height - 34,
            width: size.width,
            height: size.height
        )
        let initialFrame = finalFrame.offsetBy(dx: 0, dy: 8)
        let exitFrame = finalFrame.offsetBy(dx: 0, dy: 6)

        let panel = NSPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .statusBar
        panel.alphaValue = 0
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        let container = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let icon = NSImageView(frame: NSRect(x: 16, y: 13, width: 18, height: 18))
        let symbol = NSImage(
            systemSymbolName: noticeSymbolName(for: message),
            accessibilityDescription: message
        )?.withSymbolConfiguration(symbolConfiguration)
        symbol?.isTemplate = true
        icon.image = symbol
        icon.contentTintColor = noticeTintColor(for: message)
        icon.imageScaling = .scaleProportionallyDown
        container.addSubview(icon)

        let label = NSTextField(labelWithString: message)
        label.alignment = .center
        label.font = font
        label.textColor = .labelColor
        label.frame = NSRect(x: 42, y: 12, width: size.width - 58, height: 20)
        label.lineBreakMode = .byTruncatingTail
        container.addSubview(label)

        panel.contentView = container
        transientNoticePanel = panel
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.65) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
                panel.animator().setFrame(exitFrame, display: true)
            } completionHandler: {
                transientNoticePanel?.close()
                transientNoticePanel = nil
                completion?()
                if terminateAfterClose {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

private func noticeSymbolName(for message: String) -> String {
    switch message {
    case "已同步相册", "已同步过":
        return "checkmark.circle"
    case "需要授权":
        return "lock"
    case "同步失败", "部分失败":
        return "xmark.circle"
    default:
        return "checkmark.circle"
    }
}

private func noticeTintColor(for message: String) -> NSColor {
    switch message {
    default:
        return .white
    }
}

private func nextAvailableBackupURL(for sourceURL: URL, in uploadFolder: URL) -> URL {
    let fileManager = FileManager.default
    let source = sourceURL.standardizedFileURL
    let folder = uploadFolder.standardizedFileURL

    if source.deletingLastPathComponent().path == folder.path {
        return source
    }

    let baseName = source.deletingPathExtension().lastPathComponent
    let fileExtension = source.pathExtension
    var candidate = folder.appendingPathComponent(source.lastPathComponent)
    var suffix = 2

    while fileManager.fileExists(atPath: candidate.path) {
        let fileName = fileExtension.isEmpty
            ? "\(baseName) \(suffix)"
            : "\(baseName) \(suffix).\(fileExtension)"
        candidate = folder.appendingPathComponent(fileName)
        suffix += 1
    }

    return candidate.standardizedFileURL
}

private func prepareFinderSyncCopyJobs(from sourceURLs: [URL]) -> (jobs: [FinderSyncCopyJob], failures: [ImportFailure]) {
    let fileManager = FileManager.default
    let uploadFolder = defaultImportFolder()
    var jobs: [FinderSyncCopyJob] = []
    var failures: [ImportFailure] = []

    do {
        try fileManager.createDirectory(at: uploadFolder, withIntermediateDirectories: true)
    } catch {
        return ([], sourceURLs.map { ImportFailure(url: $0, message: error.localizedDescription) })
    }

    for sourceURL in sourceURLs {
        let source = sourceURL.standardizedFileURL
        guard isFinderSyncEligibleImage(source) else {
            failures.append(ImportFailure(url: source, message: "Not eligible"))
            continue
        }

        let backup = nextAvailableBackupURL(for: source, in: uploadFolder)
        if backup.path != source.path {
            do {
                try fileManager.copyItem(at: source, to: backup)
            } catch {
                logImportToPhotos("prepare copy failed source=\(source.path) backup=\(backup.path) error=\(error.localizedDescription)")
                failures.append(ImportFailure(url: source, message: error.localizedDescription))
                continue
            }
        }

        jobs.append(FinderSyncCopyJob(sourceURL: source, backupURL: backup))
    }

    return (jobs, failures)
}

private func runFinderSyncCopyTest(with sourceURLs: [URL]) -> Int32 {
    let result = prepareFinderSyncCopyJobs(from: sourceURLs)

    for job in result.jobs {
        if job.sourceURL.path == job.backupURL.path {
            print("USING_SOURCE \(job.sourceURL.path)")
        } else {
            print("COPIED \(job.backupURL.path)")
        }

        if let error = writeUploadedMarker(to: job.sourceURL) {
            print("MARK_SOURCE_FAILED \(job.sourceURL.path): \(error)")
        } else {
            print("MARKED_SOURCE \(job.sourceURL.path)")
        }

        if let error = writeUploadedMarker(to: job.backupURL) {
            print("MARK_BACKUP_FAILED \(job.backupURL.path): \(error)")
        } else {
            print("MARKED_BACKUP \(job.backupURL.path)")
        }
    }

    for failure in result.failures {
        print("FAILED \(failure.url.path): \(failure.message)")
    }

    return result.failures.isEmpty && !result.jobs.isEmpty ? 0 : 1
}

private func requestPhotosAccess(completion: @escaping (Bool) -> Void) {
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        switch status {
        case .authorized, .limited:
            completion(true)
        default:
            completion(false)
        }
    }
}

private func importImages(
    _ urls: [URL],
    skippedCount: Int,
    index: Int = 0,
    imported: Int = 0,
    importFailures: [ImportFailure] = [],
    markerFailures: [ImportFailure] = []
) {
    guard index < urls.count else {
        if importFailures.isEmpty && markerFailures.isEmpty {
            showAlert(
                title: "Import Complete",
                message: "Imported \(imported) new image(s) into Photos.\nSkipped \(skippedCount) already marked image(s)."
            )
        } else {
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

            showAlert(
                title: "Import Finished With Errors",
                message: details.joined(separator: "\n")
            )
        }
        return
    }

    let url = urls[index]
    PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
    }) { success, error in
        var nextImportFailures = importFailures
        var nextMarkerFailures = markerFailures
        let nextImported = imported + (success ? 1 : 0)
        if success {
            if let markerError = writeUploadedMarker(to: url) {
                nextMarkerFailures.append(ImportFailure(url: url, message: markerError))
            }
        } else {
            nextImportFailures.append(ImportFailure(url: url, message: error?.localizedDescription ?? "Unknown error"))
        }
        importImages(
            urls,
            skippedCount: skippedCount,
            index: index + 1,
            imported: nextImported,
            importFailures: nextImportFailures,
            markerFailures: nextMarkerFailures
        )
    }
}

private func importFinderSyncCopyJobs(
    _ jobs: [FinderSyncCopyJob],
    index: Int = 0,
    imported: Int = 0,
    failures: [ImportFailure] = [],
    terminateAfterNotice: Bool = true,
    completion: (() -> Void)? = nil
) {
    guard index < jobs.count else {
        let message: String
        if failures.isEmpty && imported > 0 {
            message = "已同步相册"
        } else if imported > 0 {
            message = "部分失败"
        } else {
            message = "同步失败"
        }
        if !failures.isEmpty {
            let details = failures.prefix(5)
                .map { "\($0.url.path): \($0.message)" }
                .joined(separator: " | ")
            logImportToPhotos("finder sync import finished message=\(message) imported=\(imported) failures=\(failures.count) details=\(details)")
        } else {
            logImportToPhotos("finder sync import finished message=\(message) imported=\(imported) failures=0")
        }
        showTimedNotice(message, terminateAfterClose: terminateAfterNotice, completion: completion)
        return
    }

    let job = jobs[index]
    PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: job.backupURL)
    }) { success, error in
        var nextFailures = failures
        var nextImported = imported

        if success {
            nextImported += 1
            if let markerError = writeUploadedMarker(to: job.backupURL) {
                nextFailures.append(ImportFailure(url: job.backupURL, message: markerError))
            }
            if job.sourceURL.path != job.backupURL.path,
               let markerError = writeUploadedMarker(to: job.sourceURL) {
                nextFailures.append(ImportFailure(url: job.sourceURL, message: markerError))
            }
        } else {
            nextFailures.append(ImportFailure(
                url: job.backupURL,
                message: error?.localizedDescription ?? "Unknown error"
            ))
        }

        importFinderSyncCopyJobs(
            jobs,
            index: index + 1,
            imported: nextImported,
            failures: nextFailures,
            terminateAfterNotice: terminateAfterNotice,
            completion: completion
        )
    }
}

private func printUsage() {
    print("""
    ImportToPhotos

    Usage:
      ImportToPhotos [folder-or-image ...]
      ImportToPhotos --dry-run [folder-or-image ...]
      ImportToPhotos --sync-copy [image ...]
      ImportToPhotos --background-agent

    If no path is provided, the app imports the folder that contains ImportToPhotos.app.
    Successfully imported files are marked with the \(uploadedMarkerAttributeName) extended attribute.
    """)
}

private enum LaunchMode {
    case standardImport
    case finderSyncCopy
    case backgroundAgent
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let launchURLs: [URL]
    private let launchMode: LaunchMode
    private var hasStarted = false
    private var agentJobTimer: Timer?
    private var isProcessingAgentJob = false

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
            startBackgroundAgent()
        }
    }

    private func startBackgroundAgent() {
        logImportToPhotos("background agent started jobDirectory=\(finderSyncJobDirectory().path)")
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(finderSyncJobPosted(_:)),
            name: finderSyncJobNotificationName,
            object: nil
        )
        agentJobTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.processPendingFinderSyncJobs()
        }
        processPendingFinderSyncJobs()
    }

    @objc private func finderSyncJobPosted(_ notification: Notification) {
        processPendingFinderSyncJobs()
    }

    private func processPendingFinderSyncJobs() {
        guard !isProcessingAgentJob else {
            return
        }

        let fileManager = FileManager.default
        let directory = finderSyncJobDirectory()
        let jobURLs = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ))?
            .filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate < rhsDate
            } ?? []

        guard let jobURL = jobURLs.first else {
            return
        }

        isProcessingAgentJob = true
        let processingURL = jobURL
            .deletingPathExtension()
            .appendingPathExtension("processing")

        do {
            try? fileManager.removeItem(at: processingURL)
            try fileManager.moveItem(at: jobURL, to: processingURL)
            let data = try Data(contentsOf: processingURL)
            let job = try JSONDecoder().decode(FinderSyncQueuedJob.self, from: data)
            try? fileManager.removeItem(at: processingURL)

            let urls = job.paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
            logImportToPhotos("agent processing sync job id=\(job.id) paths=\(job.paths.joined(separator: " | "))")
            startFinderSyncCopy(with: urls, terminateAfterNotice: false) { [weak self] in
                self?.isProcessingAgentJob = false
                self?.processPendingFinderSyncJobs()
            }
        } catch {
            logImportToPhotos("agent sync job failed url=\(jobURL.path) error=\(error.localizedDescription)")
            try? fileManager.removeItem(at: jobURL)
            try? fileManager.removeItem(at: processingURL)
            showTimedNotice("同步失败", terminateAfterClose: false) { [weak self] in
                self?.isProcessingAgentJob = false
                self?.processPendingFinderSyncJobs()
            }
        }
    }

    private func startStandardImport(with urls: [URL]) {
        let inputs = urls.isEmpty ? [defaultImportFolder()] : urls
        let images = collectImages(from: inputs)
        let selection = partitionUploadedImages(images)

        guard !images.isEmpty else {
            showAlert(title: "No Images Found", message: "No supported image files were found in the selected folder.")
            return
        }

        guard !selection.newImages.isEmpty else {
            showAlert(
                title: "No New Photos To Import",
                message: "Skipped \(selection.skippedImages.count) already marked image(s)."
            )
            return
        }

        requestPhotosAccess { allowed in
            guard allowed else {
                showAlert(
                    title: "Photos Access Needed",
                    message: "Allow this app to add photos in System Settings > Privacy & Security > Photos, then run it again."
                )
                return
            }
            importImages(selection.newImages, skippedCount: selection.skippedImages.count)
        }
    }

    private func startFinderSyncCopy(
        with urls: [URL],
        terminateAfterNotice: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        guard !urls.isEmpty else {
            logImportToPhotos("finder sync copy failed reason=empty-urls")
            showTimedNotice("同步失败", terminateAfterClose: terminateAfterNotice, completion: completion)
            return
        }

        if urls.allSatisfy(hasUploadedMarker) {
            logImportToPhotos("finder sync copy skipped reason=already-marked urls=\(urls.map(\.path).joined(separator: " | "))")
            showTimedNotice("已同步过", terminateAfterClose: terminateAfterNotice, completion: completion)
            return
        }

        let result = prepareFinderSyncCopyJobs(from: urls)
        guard !result.jobs.isEmpty else {
            let details = result.failures.prefix(5)
                .map { "\($0.url.path): \($0.message)" }
                .joined(separator: " | ")
            logImportToPhotos("finder sync copy failed reason=no-jobs failures=\(result.failures.count) details=\(details)")
            showTimedNotice(
                result.failures.isEmpty ? "已同步过" : "同步失败",
                terminateAfterClose: terminateAfterNotice,
                completion: completion
            )
            return
        }

        requestPhotosAccess { allowed in
            guard allowed else {
                logImportToPhotos("finder sync copy failed reason=photos-access-denied")
                showTimedNotice("需要授权", terminateAfterClose: terminateAfterNotice, completion: completion)
                return
            }
            importFinderSyncCopyJobs(
                result.jobs,
                terminateAfterNotice: terminateAfterNotice,
                completion: completion
            )
        }
    }
}

@main
struct ImportToPhotosMain {
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--help") || arguments.contains("-h") {
            printUsage()
            exit(0)
        }

        if arguments.contains("--menu-eligible") {
            let urls = explicitInputURLs(from: arguments)
            if isFinderSyncEligibleSelection(urls) {
                print("ELIGIBLE")
                exit(0)
            }

            print("INELIGIBLE")
            exit(1)
        }

        if arguments.contains("--sync-copy-test-run") {
            let urls = explicitInputURLs(from: arguments)
            exit(runFinderSyncCopyTest(with: urls))
        }

        let launchMode: LaunchMode
        if arguments.contains("--background-agent") {
            launchMode = .backgroundAgent
        } else if arguments.contains("--sync-copy") {
            launchMode = .finderSyncCopy
        } else {
            launchMode = .standardImport
        }

        let inputURLs = launchMode == .finderSyncCopy
            ? explicitInputURLs(from: arguments)
            : normalizedInputURLs(from: arguments)
        if arguments.contains("--dry-run") {
            let images = collectImages(from: inputURLs)
            let selection = partitionUploadedImages(images)
            print("Found \(images.count) supported image(s).")
            print("New images: \(selection.newImages.count)")
            print("Skipped marked images: \(selection.skippedImages.count)")

            if !selection.newImages.isEmpty {
                print("\nNew:")
                for image in selection.newImages {
                    print("NEW \(image.path)")
                }
            }

            if !selection.skippedImages.isEmpty {
                print("\nSkipped:")
                for image in selection.skippedImages {
                    print("SKIPPED \(image.path)")
                }
            }
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate(launchURLs: inputURLs, launchMode: launchMode)
        app.delegate = delegate
        app.run()
    }
}
