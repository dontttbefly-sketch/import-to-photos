import Foundation

struct FinderSyncCopyJob {
    let sourceURL: URL
    let backupURL: URL
}

struct FinderSyncCopyPreparation {
    let jobs: [FinderSyncCopyJob]
    let failures: [ImportFailure]
}

struct FinderSyncCopyOutcome {
    let noticeKind: NoticeKind
    let imported: Int
    let failures: [ImportFailure]
    let queueResolution: QueueResolution
    let stagedPaths: [String]
    let retryPaths: [String]
    let retryStagedPaths: [String]

    var failureSummary: String {
        let details = failures.prefix(3)
            .map { "\($0.url.lastPathComponent): \($0.message)" }
            .joined(separator: " | ")
        return details.isEmpty ? noticeKind.message : details
    }
}

enum QueueResolution {
    case complete
    case retryLater(paths: [String], stagedPaths: [String])
    case blockedUntilAuthorization(paths: [String], stagedPaths: [String])
    case failedPermanently
}

final class FinderSyncCopyService {
    private let importer: PhotosImporting
    private let fileManager: FileManager

    init(importer: PhotosImporting, fileManager: FileManager = .default) {
        self.importer = importer
        self.fileManager = fileManager
    }

    func currentAddOnlyAccessAllowsImport() -> Bool {
        importer.currentAddOnlyAccessAllowsImport()
    }

    func synchronize(
        urls: [URL],
        stagedPaths: [String] = [],
        completion: @escaping (FinderSyncCopyOutcome) -> Void
    ) {
        guard !urls.isEmpty else {
            AppLogger.log("finder sync copy failed reason=empty-urls")
            completion(FinderSyncCopyOutcome(
                noticeKind: .syncFailed,
                imported: 0,
                failures: [],
                queueResolution: .failedPermanently,
                stagedPaths: [],
                retryPaths: [],
                retryStagedPaths: []
            ))
            return
        }

        if urls.allSatisfy(UploadedMarkerStore.hasMarker) {
            AppLogger.log("finder sync copy skipped reason=already-marked urls=\(urls.map(\.path).joined(separator: " | "))")
            completion(FinderSyncCopyOutcome(
                noticeKind: .alreadySynced,
                imported: 0,
                failures: [],
                queueResolution: .complete,
                stagedPaths: [],
                retryPaths: [],
                retryStagedPaths: []
            ))
            return
        }

        importer.requestAddOnlyAccess { [weak self] allowed in
            guard let self else {
                return
            }
            guard allowed else {
                AppLogger.log("finder sync copy failed reason=photos-access-denied")
                completion(FinderSyncCopyOutcome(
                    noticeKind: .needsAuthorization,
                    imported: 0,
                    failures: [],
                    queueResolution: .blockedUntilAuthorization(paths: urls.map(\.path), stagedPaths: []),
                    stagedPaths: [],
                    retryPaths: urls.map(\.path),
                    retryStagedPaths: []
                ))
                return
            }

            let preparation = self.prepareCopyJobs(from: urls, stagedPaths: stagedPaths)
            guard !preparation.jobs.isEmpty else {
                let details = preparation.failures.prefix(5)
                    .map { "\($0.url.path): \($0.message)" }
                    .joined(separator: " | ")
                let retry = self.retryTargets(from: preparation.failures)
                AppLogger.log("finder sync copy failed reason=no-jobs failures=\(preparation.failures.count) details=\(details)")
                completion(FinderSyncCopyOutcome(
                    noticeKind: preparation.failures.isEmpty ? .alreadySynced : .syncFailed,
                    imported: 0,
                    failures: preparation.failures,
                    queueResolution: self.queueResolution(
                        imported: 0,
                        failures: preparation.failures,
                        retryPaths: retry.paths,
                        retryStagedPaths: retry.stagedPaths
                    ),
                    stagedPaths: [],
                    retryPaths: retry.paths,
                    retryStagedPaths: retry.stagedPaths
                ))
                return
            }

            self.importCopyJobs(
                preparation.jobs,
                failures: preparation.failures,
                completion: completion
            )
        }
    }

    func prepareCopyJobs(from sourceURLs: [URL], stagedPaths: [String] = []) -> FinderSyncCopyPreparation {
        var jobs: [FinderSyncCopyJob] = []
        var failures: [ImportFailure] = []

        guard AppConfig.finderSyncKeepCopyEnabled() else {
            for sourceURL in sourceURLs {
                let source = sourceURL.standardizedFileURL
                if UploadedMarkerStore.hasMarker(source) {
                    AppLogger.log("finder sync copy skipped marked source=\(source.path)")
                    continue
                }
                if let failureMessage = ImageTypePolicy.importExecutionFailureMessage(for: source) {
                    failures.append(ImportFailure(url: source, message: failureMessage, kind: .permanent))
                    continue
                }

                jobs.append(FinderSyncCopyJob(sourceURL: source, backupURL: source))
            }

            return FinderSyncCopyPreparation(jobs: jobs, failures: failures)
        }

        let uploadFolder = AppConfig.defaultImportFolder()
        do {
            try fileManager.createDirectory(at: uploadFolder, withIntermediateDirectories: true)
        } catch {
            return FinderSyncCopyPreparation(
                jobs: [],
                failures: sourceURLs.map {
                    ImportFailure(
                        url: $0,
                        message: error.localizedDescription,
                        kind: .temporary,
                        retrySourceURL: $0
                    )
                }
            )
        }

        for (index, sourceURL) in sourceURLs.enumerated() {
            let source = sourceURL.standardizedFileURL
            if UploadedMarkerStore.hasMarker(source) {
                AppLogger.log("finder sync copy skipped marked source=\(source.path)")
                continue
            }
            if let failureMessage = ImageTypePolicy.importExecutionFailureMessage(for: source) {
                failures.append(ImportFailure(url: source, message: failureMessage, kind: .permanent))
                continue
            }

            let stagedBackup = stagedBackupURL(at: index, stagedPaths: stagedPaths)
            let backup = stagedBackup ?? nextAvailableBackupURL(for: source, in: uploadFolder)
            if backup.path != source.path, !fileManager.fileExists(atPath: backup.path) {
                do {
                    try fileManager.copyItem(at: source, to: backup)
                } catch {
                    AppLogger.log("prepare copy failed source=\(source.path) backup=\(backup.path) error=\(error.localizedDescription)")
                    failures.append(ImportFailure(
                        url: source,
                        message: error.localizedDescription,
                        kind: .temporary,
                        retrySourceURL: source,
                        retryStagedURL: backup
                    ))
                    continue
                }
            }

            jobs.append(FinderSyncCopyJob(sourceURL: source, backupURL: backup))
        }

        return FinderSyncCopyPreparation(jobs: jobs, failures: failures)
    }

    func runCopyTest(with sourceURLs: [URL]) -> Int32 {
        let result = prepareCopyJobs(from: sourceURLs)

        for job in result.jobs {
            if job.sourceURL.path == job.backupURL.path {
                print("USING_SOURCE \(job.sourceURL.path)")
            } else {
                print("COPIED \(job.backupURL.path)")
            }

            if let error = UploadedMarkerStore.writeMarker(to: job.sourceURL) {
                print("MARK_SOURCE_FAILED \(job.sourceURL.path): \(error)")
            } else {
                print("MARKED_SOURCE \(job.sourceURL.path)")
            }

            if job.sourceURL.path != job.backupURL.path {
                if let error = UploadedMarkerStore.writeMarker(to: job.backupURL) {
                    print("MARK_BACKUP_FAILED \(job.backupURL.path): \(error)")
                } else {
                    print("MARKED_BACKUP \(job.backupURL.path)")
                }
            }
        }

        for failure in result.failures {
            print("FAILED \(failure.url.path): \(failure.message)")
        }

        return result.failures.isEmpty && !result.jobs.isEmpty ? 0 : 1
    }

    private func importCopyJobs(
        _ jobs: [FinderSyncCopyJob],
        index: Int = 0,
        imported: Int = 0,
        failures: [ImportFailure] = [],
        completion: @escaping (FinderSyncCopyOutcome) -> Void
    ) {
        guard index < jobs.count else {
            let noticeKind: NoticeKind
            if failures.isEmpty && imported > 0 {
                noticeKind = .synced
            } else if imported > 0 {
                noticeKind = .partialFailure
            } else {
                noticeKind = .syncFailed
            }

            if !failures.isEmpty {
                let details = failures.prefix(5)
                    .map { "\($0.url.path): \($0.message)" }
                    .joined(separator: " | ")
                AppLogger.log("finder sync import finished message=\(noticeKind.message) imported=\(imported) failures=\(failures.count) details=\(details)")
            } else {
                AppLogger.log("finder sync import finished message=\(noticeKind.message) imported=\(imported) failures=0")
            }

            let stagedPaths = jobs
                .filter { $0.sourceURL.path != $0.backupURL.path }
                .map(\.backupURL.path)
            let retry = retryTargets(from: failures)

            completion(FinderSyncCopyOutcome(
                noticeKind: noticeKind,
                imported: imported,
                failures: failures,
                queueResolution: queueResolution(
                    imported: imported,
                    failures: failures,
                    retryPaths: retry.paths,
                    retryStagedPaths: retry.stagedPaths
                ),
                stagedPaths: stagedPaths,
                retryPaths: retry.paths,
                retryStagedPaths: retry.stagedPaths
            ))
            return
        }

        let job = jobs[index]
        importer.importImage(at: job.backupURL) { [weak self] success, errorMessage in
            guard let self else {
                return
            }

            var nextFailures = failures
            var nextImported = imported

            if success {
                nextImported += 1
                if let markerError = UploadedMarkerStore.writeMarker(to: job.backupURL) {
                    nextFailures.append(ImportFailure(
                        url: job.backupURL,
                        message: markerError,
                        kind: .marker
                    ))
                }
                if job.sourceURL.path != job.backupURL.path,
                   let markerError = UploadedMarkerStore.writeMarker(to: job.sourceURL) {
                    nextFailures.append(ImportFailure(
                        url: job.sourceURL,
                        message: markerError,
                        kind: .marker
                    ))
                }
            } else {
                nextFailures.append(ImportFailure(
                    url: job.backupURL,
                    message: errorMessage ?? "Unknown error",
                    kind: .temporary,
                    retrySourceURL: job.sourceURL,
                    retryStagedURL: job.sourceURL.path == job.backupURL.path ? nil : job.backupURL
                ))
            }

            self.importCopyJobs(
                jobs,
                index: index + 1,
                imported: nextImported,
                failures: nextFailures,
                completion: completion
            )
        }
    }

    private func queueResolution(
        imported: Int,
        failures: [ImportFailure],
        retryPaths: [String],
        retryStagedPaths: [String]
    ) -> QueueResolution {
        if !retryPaths.isEmpty {
            return .retryLater(paths: retryPaths, stagedPaths: retryStagedPaths)
        }

        if imported > 0 || failures.isEmpty {
            return .complete
        }

        if failures.allSatisfy({ $0.kind == .permanent || $0.kind == .marker }) {
            return .failedPermanently
        }

        return .complete
    }

    private func retryTargets(from failures: [ImportFailure]) -> (paths: [String], stagedPaths: [String]) {
        var paths: [String] = []
        var stagedPaths: [String] = []

        for failure in failures where failure.kind == .temporary {
            guard let retrySourceURL = failure.retrySourceURL else {
                continue
            }
            paths.append(retrySourceURL.path)
            if let retryStagedURL = failure.retryStagedURL {
                stagedPaths.append(retryStagedURL.path)
            }
        }

        return (paths, stagedPaths)
    }

    private func nextAvailableBackupURL(for sourceURL: URL, in uploadFolder: URL) -> URL {
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
            if fileManager.contentsEqual(atPath: source.path, andPath: candidate.path) {
                return candidate.standardizedFileURL
            }

            let fileName = fileExtension.isEmpty
                ? "\(baseName) \(suffix)"
                : "\(baseName) \(suffix).\(fileExtension)"
            candidate = folder.appendingPathComponent(fileName)
            suffix += 1
        }

        return candidate.standardizedFileURL
    }

    private func stagedBackupURL(at index: Int, stagedPaths: [String]) -> URL? {
        guard stagedPaths.indices.contains(index) else {
            return nil
        }

        let path = stagedPaths[index].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path).standardizedFileURL
    }
}
