import AppKit
import FinderSync
import Foundation

@objc(FinderSyncExtension)
final class FinderSyncExtension: FIFinderSync {
    private static let syncMenuTitle = "★ 同步进相册"
    private let menuController = FinderMenuController(syncMenuTitle: FinderSyncExtension.syncMenuTitle)
    private let jobQueue = FinderSyncJobQueue()

    override init() {
        super.init()
        FinderBadgeController.registerBadges()
        let directories = monitoredDirectories()
        FIFinderSyncController.default().directoryURLs = directories
        FinderSyncLogger.log("init directories=\(directories.map(\.path).sorted().joined(separator: " | "))")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        FinderSyncLogger.log("menu(for:) kind=\(menuKind.rawValue) name=\(menuKindDescription(menuKind))")
        let selectedURLs = selectedItemURLsForMenu()

        switch menuKind {
        case .contextualMenuForItems, .contextualMenuForContainer:
            return menuController.contextualMenuForItems(
                selectedURLs: selectedURLs,
                target: self,
                action: #selector(syncSelectedItems(_:))
            )
        case .toolbarItemMenu:
            return menuController.toolbarItemMenu(
                selectedURLs: selectedURLs,
                target: self,
                action: #selector(syncSelectedItems(_:))
            )
        default:
            FinderSyncLogger.log("menu hidden reason=unsupported-kind kind=\(menuKind.rawValue)")
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
        FinderSyncLogger.log("beginObservingDirectory url=\(url.path)")
    }

    override func endObservingDirectory(at url: URL) {
        FinderSyncLogger.log("endObservingDirectory url=\(url.path)")
    }

    override func requestBadgeIdentifier(for url: URL) {
        FinderBadgeController.updateBadge(for: url)
    }

    @objc private func syncSelectedItems(_ sender: Any?) {
        let representedPaths = (sender as? NSMenuItem)?.representedObject as? [String]
        let fallbackPaths = selectedItemURLsForMenu().map(\.path)
        let paths = representedPaths?.isEmpty == false ? representedPaths ?? [] : fallbackPaths

        guard !paths.isEmpty else {
            FinderSyncLogger.log("sync click ignored reason=missing-paths")
            return
        }

        FinderSyncLogger.log("sync click paths=\(paths.joined(separator: " | "))")
        enqueueSyncJob(paths: paths)
    }

    private func enqueueSyncJob(paths: [String]) {
        do {
            let job = try jobQueue.enqueue(paths: paths)
            DistributedNotificationCenter.default().post(name: AppConfig.finderSyncJobNotificationName, object: nil)
            FinderSyncLogger.log("sync job queued id=\(job.id) paths=\(paths.joined(separator: " | "))")
        } catch {
            FinderSyncLogger.log("sync job enqueue failed paths=\(paths.joined(separator: " | ")) error=\(error.localizedDescription)")
        }
    }

    private func monitoredDirectories() -> Set<URL> {
        let home = AppConfig.realUserHomeDirectory().standardizedFileURL
        return Set([
            home,
            standardHomeChild("Desktop", under: home),
            standardHomeChild("Downloads", under: home),
            standardHomeChild("Pictures", under: home),
            standardHomeChild("Documents", under: home)
        ])
    }

    private func standardHomeChild(_ name: String, under home: URL) -> URL {
        home.appendingPathComponent(name, isDirectory: true).standardizedFileURL
    }

    private func selectedItemURLsForMenu() -> [URL] {
        let controller = FIFinderSyncController.default()
        if let selectedURLs = controller.selectedItemURLs(), !selectedURLs.isEmpty {
            FinderSyncLogger.log("url source=selectedItemURLs count=\(selectedURLs.count) urls=\(selectedURLs.map(\.path).joined(separator: " | "))")
            return selectedURLs
        }
        if let targetedURL = controller.targetedURL() {
            FinderSyncLogger.log("url source=targetedURL count=1 urls=\(targetedURL.path)")
            return [targetedURL]
        }
        FinderSyncLogger.log("url source=none")
        return []
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
