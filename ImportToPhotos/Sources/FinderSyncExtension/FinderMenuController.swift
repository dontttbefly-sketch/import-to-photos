import AppKit

struct FinderMenuController {
    let syncMenuTitle: String

    func contextualMenuForItems(
        selectedURLs: [URL],
        target: AnyObject,
        action: Selector
    ) -> NSMenu? {
        guard ImageTypePolicy.isFinderSyncEligibleSelection(selectedURLs) else {
            logEligibility("contextualMenuForItems", selectedURLs)
            return nil
        }

        FinderSyncLogger.log("menu shown source=contextualMenuForItems urls=\(selectedURLs.map(\.path).joined(separator: " | "))")
        return syncMenu(for: selectedURLs, target: target, action: action)
    }

    func toolbarItemMenu(
        selectedURLs: [URL],
        target: AnyObject,
        action: Selector
    ) -> NSMenu {
        guard ImageTypePolicy.isFinderSyncEligibleSelection(selectedURLs) else {
            logEligibility("toolbarItemMenu", selectedURLs)
            let menu = NSMenu(title: "")
            let item = NSMenuItem(title: "未选中图片", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return menu
        }

        FinderSyncLogger.log("menu shown source=toolbarItemMenu urls=\(selectedURLs.map(\.path).joined(separator: " | "))")
        return syncMenu(for: selectedURLs, target: target, action: action)
    }

    private func syncMenu(for urls: [URL], target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu(title: "")
        let item = NSMenuItem(title: syncMenuTitle, action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = urls.map(\.path)
        menu.addItem(item)
        return menu
    }

    private func logEligibility(_ source: String, _ urls: [URL]) {
        if urls.isEmpty {
            FinderSyncLogger.log("eligibility source=\(source) result=false reason=no-urls")
            return
        }

        let details = urls.map { url -> String in
            let isExcluded = ImageTypePolicy.isFinderSyncExcludedPath(url)
            let hasImageExtension = ImageTypePolicy.hasSupportedImageExtension(url)
            let isMarked = hasImageExtension && !isExcluded && UploadedMarkerStore.hasMarker(url)
            let isEligible = ImageTypePolicy.isFinderSyncEligibleImage(url)
            return "\(url.path) imageExtension=\(hasImageExtension) excluded=\(isExcluded) marked=\(isMarked) eligible=\(isEligible)"
        }
        FinderSyncLogger.log("eligibility source=\(source) result=false details=\(details.joined(separator: " | "))")
    }
}
