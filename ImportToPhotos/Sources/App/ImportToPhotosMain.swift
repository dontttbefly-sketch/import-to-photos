import AppKit
import Foundation

@main
struct ImportToPhotosMain {
    private final class DenyingPhotosImporter: PhotosImporting {
        func currentAddOnlyAccessAllowsImport() -> Bool {
            false
        }

        func requestAddOnlyAccess(completion: @escaping (Bool) -> Void) {
            completion(false)
        }

        func importImage(at url: URL, completion: @escaping (Bool, String?) -> Void) {
            completion(false, "Unexpected import attempt")
        }
    }

    private final class PartiallyFailingPhotosImporter: PhotosImporting {
        func currentAddOnlyAccessAllowsImport() -> Bool {
            true
        }

        func requestAddOnlyAccess(completion: @escaping (Bool) -> Void) {
            completion(true)
        }

        func importImage(at url: URL, completion: @escaping (Bool, String?) -> Void) {
            if url.lastPathComponent.contains("partial-fail") {
                completion(false, "Temporary test failure")
            } else {
                completion(true, nil)
            }
        }
    }

    private static var testHooksEnabled: Bool {
        ProcessInfo.processInfo.environment["IMPORT_TO_PHOTOS_ENABLE_TEST_HOOKS"] == "1"
    }

    private static var requestedTestHook: Bool {
        let arguments = CommandLine.arguments
        return arguments.contains("--sync-copy-test-run")
            || arguments.contains("--sync-copy-partial-test-run")
            || arguments.contains("--sync-copy-denied-test-run")
            || arguments.contains("--queue-recovery-test-run")
            || arguments.contains("--queue-retry-test-run")
            || arguments.contains("--queue-blocked-authorization-test-run")
            || arguments.contains("--queue-release-blocked-test-run")
    }

    static func main() {
        let options = CommandLineOptions(arguments: CommandLine.arguments)

        if options.shouldPrintHelp {
            printUsage()
            exit(0)
        }

        if options.shouldCheckMenuEligibility {
            let urls = CommandLineOptions.explicitInputURLs(from: options.arguments)
            if ImageTypePolicy.isFinderSyncEligibleSelection(urls) {
                print("ELIGIBLE")
                exit(0)
            }

            print("INELIGIBLE")
            exit(1)
        }

        if options.shouldCheckImageSupport {
            let urls = CommandLineOptions.explicitInputURLs(from: options.arguments)
            guard !urls.isEmpty else {
                print("NO_INPUT")
                exit(64)
            }

            var hasUnsupported = false
            for url in urls {
                let summary = ImageTypePolicy.supportSummary(for: url)
                print(summary)
                if summary.hasPrefix("UNSUPPORTED ") {
                    hasUnsupported = true
                }
            }
            exit(hasUnsupported ? 1 : 0)
        }

        if requestedTestHook && !testHooksEnabled {
            print("TEST_HOOKS_DISABLED")
            exit(64)
        }

        if options.arguments.contains("--sync-copy-denied-test-run") {
            let urls = CommandLineOptions.explicitInputURLs(from: options.arguments)
            let copyService = FinderSyncCopyService(importer: DenyingPhotosImporter())
            copyService.synchronize(urls: urls) { outcome in
                print(outcome.noticeKind.message)
                print("IMPORTED \(outcome.imported)")
                print("FAILURES \(outcome.failures.count)")
                switch outcome.queueResolution {
                case .complete:
                    print("RESOLUTION complete")
                case .retryLater:
                    print("RESOLUTION retryLater")
                case .blockedUntilAuthorization:
                    print("RESOLUTION blockedUntilAuthorization")
                case .failedPermanently:
                    print("RESOLUTION failedPermanently")
                }
                exit(outcome.noticeKind == .needsAuthorization ? 0 : 1)
            }
            RunLoop.main.run()
        }

        if options.arguments.contains("--sync-copy-partial-test-run") {
            let urls = CommandLineOptions.explicitInputURLs(from: options.arguments)
            let copyService = FinderSyncCopyService(importer: PartiallyFailingPhotosImporter())
            copyService.synchronize(urls: urls) { outcome in
                print("NOTICE \(outcome.noticeKind.message)")
                print("IMPORTED \(outcome.imported)")
                print("FAILURES \(outcome.failures.count)")
                switch outcome.queueResolution {
                case .complete:
                    print("RESOLUTION complete")
                case .retryLater:
                    print("RESOLUTION retryLater")
                case .blockedUntilAuthorization:
                    print("RESOLUTION blockedUntilAuthorization")
                case .failedPermanently:
                    print("RESOLUTION failedPermanently")
                }
                for path in outcome.retryPaths {
                    print("RETRY_PATH \(path)")
                }
                for path in outcome.retryStagedPaths {
                    print("RETRY_STAGED_PATH \(path)")
                }
                exit(outcome.retryPaths.count == 1 ? 0 : 1)
            }
            RunLoop.main.run()
        }

        if options.arguments.contains("--queue-recovery-test-run") {
            do {
                let queue = FinderSyncJobQueue(staleProcessingInterval: 0)
                try queue.recoverStaleProcessingJobs()
                if let claimedJob = try queue.claimNextJob() {
                    print("CLAIMED \(claimedJob.job.id)")
                    queue.complete(claimedJob)
                    exit(0)
                }
                print("NO_JOB")
                exit(1)
            } catch {
                print("QUEUE_ERROR \(error.localizedDescription)")
                exit(1)
            }
        }

        if options.arguments.contains("--queue-retry-test-run") {
            do {
                let queue = FinderSyncJobQueue(staleProcessingInterval: 0)
                guard let claimedJob = try queue.claimNextJob() else {
                    print("NO_JOB")
                    exit(1)
                }
                let shouldForceRetryWriteFailure = ProcessInfo.processInfo
                    .environment["IMPORT_TO_PHOTOS_FORCE_RETRY_WRITE_FAILURE"] == "1"
                if shouldForceRetryWriteFailure {
                    try FileManager.default.setAttributes(
                        [.posixPermissions: 0o500],
                        ofItemAtPath: AppConfig.finderSyncJobDirectory().path
                    )
                }

                let result = try queue.retryLater(claimedJob, errorMessage: "test retry failure")
                if shouldForceRetryWriteFailure {
                    try? FileManager.default.setAttributes(
                        [.posixPermissions: 0o700],
                        ofItemAtPath: AppConfig.finderSyncJobDirectory().path
                    )
                }
                switch result {
                case .scheduled(let job):
                    print("RETRY_PENDING \(job.id) attempt=\(job.attemptCount)")
                    exit(0)
                case .exhausted(let job):
                    print("RETRY_EXHAUSTED \(job.id) attempt=\(job.attemptCount)")
                    exit(0)
                }
            } catch {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o700],
                    ofItemAtPath: AppConfig.finderSyncJobDirectory().path
                )
                print("QUEUE_ERROR \(error.localizedDescription)")
                exit(1)
            }
        }

        if options.arguments.contains("--queue-blocked-authorization-test-run") {
            do {
                let queue = FinderSyncJobQueue(staleProcessingInterval: 0)
                guard let claimedJob = try queue.claimNextJob() else {
                    print("NO_JOB")
                    exit(1)
                }
                let job = try queue.blockUntilAuthorization(
                    claimedJob,
                    errorMessage: "Photos authorization required"
                )
                print("AUTH_BLOCKED \(job.id)")
                exit(0)
            } catch {
                print("QUEUE_ERROR \(error.localizedDescription)")
                exit(1)
            }
        }

        if options.arguments.contains("--queue-release-blocked-test-run") {
            do {
                let queue = FinderSyncJobQueue(staleProcessingInterval: 0)
                let releasedCount = try queue.requeueBlockedAuthorizationJobs()
                print("AUTH_RELEASED \(releasedCount)")
                exit(releasedCount > 0 ? 0 : 1)
            } catch {
                print("QUEUE_ERROR \(error.localizedDescription)")
                exit(1)
            }
        }

        let importer = PhotosImporter()
        let copyService = FinderSyncCopyService(importer: importer)
        if options.shouldRunSyncCopyTest {
            let urls = CommandLineOptions.explicitInputURLs(from: options.arguments)
            exit(copyService.runCopyTest(with: urls))
        }

        if options.shouldDryRun {
            let scanner = ImageScanner()
            let images = scanner.collectImages(from: options.inputURLs)
            let selection = scanner.partitionUploadedImages(images)
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
        let delegate = AppDelegate(launchURLs: options.inputURLs, launchMode: options.launchMode)
        app.delegate = delegate
        app.run()
    }
}
