import AppKit

enum NoticeKind: Equatable {
    case synced
    case alreadySynced
    case needsAuthorization
    case syncFailed
    case partialFailure

    var message: String {
        switch self {
        case .synced:
            return "已同步相册"
        case .alreadySynced:
            return "已同步过"
        case .needsAuthorization:
            return "需要授权"
        case .syncFailed:
            return "同步失败"
        case .partialFailure:
            return "部分失败"
        }
    }

    var symbolName: String {
        switch self {
        case .synced, .alreadySynced:
            return "checkmark.circle"
        case .needsAuthorization:
            return "lock"
        case .syncFailed, .partialFailure:
            return "xmark.circle"
        }
    }

    var tintColor: NSColor {
        return .white
    }
}
