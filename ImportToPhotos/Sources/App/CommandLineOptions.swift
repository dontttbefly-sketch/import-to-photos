import Foundation

enum LaunchMode {
    case standardImport
    case finderSyncCopy
    case backgroundAgent
}

struct CommandLineOptions {
    private static let knownOptions: Set<String> = [
        "--help",
        "-h",
        "--menu-eligible",
        "--image-support-check",
        "--sync-copy-test-run",
        "--sync-copy-partial-test-run",
        "--sync-copy-denied-test-run",
        "--queue-recovery-test-run",
        "--queue-retry-test-run",
        "--queue-blocked-authorization-test-run",
        "--queue-release-blocked-test-run",
        "--dry-run",
        "--sync-import",
        "--sync-copy",
        "--background-agent"
    ]

    let arguments: [String]
    let launchMode: LaunchMode
    let inputURLs: [URL]

    var shouldPrintHelp: Bool {
        arguments.contains("--help") || arguments.contains("-h")
    }

    var shouldCheckMenuEligibility: Bool {
        arguments.contains("--menu-eligible")
    }

    var shouldCheckImageSupport: Bool {
        arguments.contains("--image-support-check")
    }

    var shouldRunSyncCopyTest: Bool {
        arguments.contains("--sync-copy-test-run")
    }

    var shouldDryRun: Bool {
        arguments.contains("--dry-run")
    }

    init(arguments: [String]) {
        self.arguments = arguments
        if arguments.contains("--background-agent") {
            launchMode = .backgroundAgent
        } else if arguments.contains("--sync-import") || arguments.contains("--sync-copy") {
            launchMode = .finderSyncCopy
        } else {
            launchMode = .standardImport
        }

        inputURLs = launchMode == .finderSyncCopy
            ? Self.explicitInputURLs(from: arguments)
            : Self.normalizedInputURLs(from: arguments)
    }

    static func normalizedInputURLs(from arguments: [String]) -> [URL] {
        let urls = explicitInputURLs(from: arguments)
        if urls.isEmpty {
            return [AppConfig.defaultImportFolder()]
        }
        return urls
    }

    static func explicitInputURLs(from arguments: [String]) -> [URL] {
        pathArguments(from: arguments)
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
    }

    static func pathArguments(from arguments: [String]) -> [String] {
        var paths: [String] = []
        var treatsRemainingAsPaths = false

        for argument in arguments.dropFirst() {
            if treatsRemainingAsPaths {
                paths.append(argument)
                continue
            }

            if argument == "--" {
                treatsRemainingAsPaths = true
                continue
            }

            if knownOptions.contains(argument) {
                continue
            }

            paths.append(argument)
        }

        return paths
    }
}

func printUsage() {
    print("""
    ImportToPhotos

    Usage:
      ImportToPhotos [folder-or-image ...]
      ImportToPhotos --dry-run [folder-or-image ...]
      ImportToPhotos --image-support-check [image ...]
      ImportToPhotos --sync-import [image ...]
      ImportToPhotos --background-agent

    If no path is provided, the app uses the configured default folder or ~/Pictures/ImportToPhotos.
    Finder right-click mode imports selected source files directly without staging copies.
    Successfully imported files are marked with the \(AppConfig.uploadedMarkerAttributeName) extended attribute.
    """)
}
