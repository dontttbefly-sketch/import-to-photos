import AppKit
import Darwin
import FinderSync
import Foundation
import OSLog

@objc(FinderSyncExtension)
final class FinderSyncExtension: FIFinderSync {
    private static let syncMenuTitle = "★ 同步进相册"
    private static let eligibleBadgeIdentifier = "eligible-image"
    private static let logger = Logger(
        subsystem: "local.import-to-photos.finder-sync",
        category: "FinderSync"
    )

    override init() {
        super.init()
        registerBadges()
        let directories = monitoredDirectories()
        FIFinderSyncController.default().directoryURLs = directories
        logFinderSync("init directories=\(directories.map(\.path).sorted().joined(separator: " | "))")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        logFinderSync("menu(for:) kind=\(menuKind.rawValue) name=\(menuKindDescription(menuKind))")

        switch menuKind {
        case .contextualMenuForItems:
            return contextualMenuForItems()
        case .contextualMenuForContainer:
            return contextualMenuForItems()
        case .toolbarItemMenu:
            return toolbarItemMenu()
        default:
            logFinderSync("menu hidden reason=unsupported-kind kind=\(menuKind.rawValue)")
            return nil
        }
    }

    override var toolbarItemName: String {
        Self.syncMenuTitle
    }

    override var toolbarItemToolTip: String {
        Self.syncMenuTitle
    }

    override var toolbarItemImage: NSImage {
        let image = NSImage(systemSymbolName: "photo", accessibilityDescription: Self.syncMenuTitle)
            ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }

    override func beginObservingDirectory(at url: URL) {
        logFinderSync("beginObservingDirectory url=\(url.path)")
        refreshEligibleBadges(in: url)
    }

    override func endObservingDirectory(at url: URL) {
        logFinderSync("endObservingDirectory url=\(url.path)")
    }

    override func requestBadgeIdentifier(for url: URL) {
        let isEligible = isFinderSyncEligibleImage(url)
        let badgeIdentifier = isEligible ? Self.eligibleBadgeIdentifier : ""
        FIFinderSyncController.default().setBadgeIdentifier(badgeIdentifier, for: url)
        logFinderSync("requestBadgeIdentifierForURL url=\(url.path) eligible=\(isEligible) badge=\(badgeIdentifier.isEmpty ? "cleared" : badgeIdentifier)")
    }

    private func contextualMenuForItems() -> NSMenu? {
        let selectedURLs = selectedItemURLsForMenu()
        guard isFinderSyncEligibleSelection(selectedURLs) else {
            logEligibility("contextualMenuForItems", selectedURLs)
            return nil
        }

        logFinderSync("menu shown source=contextualMenuForItems urls=\(selectedURLs.map(\.path).joined(separator: " | "))")
        return syncMenu(for: selectedURLs)
    }

    private func toolbarItemMenu() -> NSMenu {
        let selectedURLs = selectedItemURLsForMenu()
        guard isFinderSyncEligibleSelection(selectedURLs) else {
            logEligibility("toolbarItemMenu", selectedURLs)
            let menu = NSMenu(title: "")
            let item = NSMenuItem(title: "未选中图片", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return menu
        }

        logFinderSync("menu shown source=toolbarItemMenu urls=\(selectedURLs.map(\.path).joined(separator: " | "))")
        return syncMenu(for: selectedURLs)
    }

    private func syncMenu(for urls: [URL]) -> NSMenu {
        let menu = NSMenu(title: "")
        let item = NSMenuItem(title: Self.syncMenuTitle, action: #selector(syncSelectedItems(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = urls.map(\.path)
        menu.addItem(item)
        return menu
    }

    private func registerBadges() {
        let badgeImage = NSImage(size: NSSize(width: 1, height: 1))
        FIFinderSyncController.default().setBadgeImage(
            badgeImage,
            label: "可同步",
            forBadgeIdentifier: Self.eligibleBadgeIdentifier
        )
        logFinderSync("badge registered id=\(Self.eligibleBadgeIdentifier)")
    }

    private func refreshEligibleBadges(in directoryURL: URL) {
        let resourceKeys: Set<URLResourceKey> = [.contentTypeKey, .isDirectoryKey]
        let items: [URL]
        do {
            items = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )
        } catch {
            logFinderSync("badge refresh skipped directory=\(directoryURL.path) error=\(error.localizedDescription)")
            return
        }

        var refreshedCount = 0
        for itemURL in items.prefix(500) {
            let values = try? itemURL.resourceValues(forKeys: resourceKeys)
            if values?.isDirectory == true {
                continue
            }
            guard isSupportedImage(itemURL, contentType: values?.contentType) else {
                continue
            }

            if isFinderSyncEligibleImage(itemURL) {
                FIFinderSyncController.default().setBadgeIdentifier(Self.eligibleBadgeIdentifier, for: itemURL)
                refreshedCount += 1
            }
        }
        logFinderSync("badge refresh directory=\(directoryURL.path) scanned=\(min(items.count, 500)) eligible=\(refreshedCount)")
    }

    @objc private func syncSelectedItems(_ sender: Any?) {
        let representedPaths = (sender as? NSMenuItem)?.representedObject as? [String]
        let fallbackPaths = selectedItemURLsForMenu().map(\.path)
        let paths = representedPaths?.isEmpty == false ? representedPaths ?? [] : fallbackPaths

        guard !paths.isEmpty else {
            logFinderSync("sync click ignored reason=missing-paths")
            return
        }

        logFinderSync("sync click paths=\(paths.joined(separator: " | "))")
        enqueueSyncJob(paths: paths)
    }

    private func enqueueSyncJob(paths: [String]) {
        let job = FinderSyncQueuedJob(
            id: UUID().uuidString,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            paths: paths
        )
        let directory = finderSyncJobDirectory()
        let jobURL = directory.appendingPathComponent("\(job.id).json", isDirectory: false)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(job)
            try data.write(to: jobURL, options: [.atomic])
            DistributedNotificationCenter.default().post(name: finderSyncJobNotificationName, object: nil)
            logFinderSync("sync job queued id=\(job.id) url=\(jobURL.path) paths=\(paths.joined(separator: " | "))")
        } catch {
            logFinderSync("sync job enqueue failed paths=\(paths.joined(separator: " | ")) error=\(error.localizedDescription)")
        }
    }

    private func monitoredDirectories() -> Set<URL> {
        let home = realUserHomeDirectory()
        return Set([
            home.appendingPathComponent("Pictures", isDirectory: true).standardizedFileURL,
            home.appendingPathComponent("Desktop", isDirectory: true).standardizedFileURL,
            home.appendingPathComponent("Downloads", isDirectory: true).standardizedFileURL,
            home
                .appendingPathComponent("Pictures", isDirectory: true)
                .appendingPathComponent("上传", isDirectory: true)
                .standardizedFileURL
        ])
    }

    private func realUserHomeDirectory() -> URL {
        if let passwordRecord = getpwuid(getuid()),
           let homeDirectory = passwordRecord.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: homeDirectory), isDirectory: true)
                .standardizedFileURL
        }

        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .standardizedFileURL
    }

    private func selectedItemURLsForMenu() -> [URL] {
        let controller = FIFinderSyncController.default()
        if let selectedURLs = controller.selectedItemURLs(), !selectedURLs.isEmpty {
            logFinderSync("url source=selectedItemURLs count=\(selectedURLs.count) urls=\(selectedURLs.map(\.path).joined(separator: " | "))")
            return selectedURLs
        }
        if let targetedURL = controller.targetedURL() {
            logFinderSync("url source=targetedURL count=1 urls=\(targetedURL.path)")
            return [targetedURL]
        }
        logFinderSync("url source=none")
        return []
    }

    private func logEligibility(_ source: String, _ urls: [URL]) {
        if urls.isEmpty {
            logFinderSync("eligibility source=\(source) result=false reason=no-urls")
            return
        }

        let details = urls.map { url -> String in
            let isImage = isSupportedImage(
                url,
                contentType: try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
            )
            let isMarked = hasUploadedMarker(url)
            let isEligible = isFinderSyncEligibleImage(url)
            return "\(url.path) image=\(isImage) marked=\(isMarked) eligible=\(isEligible)"
        }
        logFinderSync("eligibility source=\(source) result=false details=\(details.joined(separator: " | "))")
    }

    private func logFinderSync(_ message: String) {
        Self.logger.info("\(message, privacy: .public)")

        guard let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            Self.logger.error("container log unavailable: missing application support directory")
            return
        }

        let logDirectory = supportDirectory
            .appendingPathComponent("ImportToPhotos", isDirectory: true)
        let logURL = logDirectory.appendingPathComponent("finder-sync.log")

        do {
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] \(message)\n"
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logURL.path),
                   let handle = try? FileHandle(forWritingTo: logURL) {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: logURL)
                }
            }
        } catch {
            Self.logger.error("container log failed: \(String(describing: error), privacy: .public)")
            return
        }
    }

    private func menuKindDescription(_ kind: FIMenuKind) -> String {
        switch kind {
        case .contextualMenuForItems:
            return "contextualMenuForItems"
        case .contextualMenuForContainer:
            return "contextualMenuForContainer"
        case .contextualMenuForSidebar:
            return "contextualMenuForSidebar"
        case .toolbarItemMenu:
            return "toolbarItemMenu"
        @unknown default:
            return "unknown"
        }
    }

}
