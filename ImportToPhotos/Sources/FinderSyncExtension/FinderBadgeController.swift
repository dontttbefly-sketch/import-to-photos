import AppKit
import FinderSync

enum FinderBadgeController {
    static let eligibleBadgeIdentifier = "eligible-image"

    static func registerBadges() {
        let badgeImage = NSImage(size: NSSize(width: 1, height: 1))
        FIFinderSyncController.default().setBadgeImage(
            badgeImage,
            label: "可同步",
            forBadgeIdentifier: eligibleBadgeIdentifier
        )
        FinderSyncLogger.log("badge registered id=\(eligibleBadgeIdentifier)")
    }

    static func updateBadge(for url: URL) {
        let isEligible = ImageTypePolicy.isFinderSyncEligibleImage(url)
        let badgeIdentifier = isEligible ? eligibleBadgeIdentifier : ""
        FIFinderSyncController.default().setBadgeIdentifier(badgeIdentifier, for: url)
        if isEligible || FinderSyncLogger.isVerbose {
            FinderSyncLogger.log("requestBadgeIdentifierForURL url=\(url.path) eligible=\(isEligible) badge=\(badgeIdentifier.isEmpty ? "cleared" : badgeIdentifier)")
        }
    }
}
