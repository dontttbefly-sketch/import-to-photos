import Foundation

final class BackgroundJobAgent: NSObject {
    private static let jobPollingInterval: TimeInterval = 3.0

    private let jobQueue: FinderSyncJobQueue
    private let copyService: FinderSyncCopyService
    private var jobTimer: Timer?
    private var isProcessingJob = false

    init(jobQueue: FinderSyncJobQueue, copyService: FinderSyncCopyService) {
        self.jobQueue = jobQueue
        self.copyService = copyService
    }

    func start() {
        AppLogger.log("background agent started jobDirectory=\(AppConfig.finderSyncJobDirectory().path)")
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(finderSyncJobPosted(_:)),
            name: AppConfig.finderSyncJobNotificationName,
            object: nil
        )
        jobTimer = Timer.scheduledTimer(withTimeInterval: Self.jobPollingInterval, repeats: true) { [weak self] _ in
            self?.processPendingFinderSyncJobs()
        }
        processPendingFinderSyncJobs()
    }

    @objc private func finderSyncJobPosted(_ notification: Notification) {
        processPendingFinderSyncJobs()
    }

    private func processPendingFinderSyncJobs() {
        guard !isProcessingJob else {
            return
        }

        let claimedJob: FinderSyncClaimedJob
        do {
            if copyService.currentAddOnlyAccessAllowsImport() {
                let releasedCount = try jobQueue.requeueBlockedAuthorizationJobs()
                if releasedCount > 0 {
                    AppLogger.log("agent released authorization-blocked jobs count=\(releasedCount)")
                }
            }
            guard let nextJob = try jobQueue.claimNextJob() else {
                return
            }
            claimedJob = nextJob
        } catch {
            AppLogger.log("agent sync job claim failed error=\(error.localizedDescription)")
            NoticePresenter.showTimedNotice(.syncFailed, terminateAfterClose: false) { [weak self] in
                self?.processPendingFinderSyncJobs()
            }
            return
        }

        isProcessingJob = true
        let urls = claimedJob.job.paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
        AppLogger.log("agent processing sync job id=\(claimedJob.job.id) paths=\(claimedJob.job.paths.joined(separator: " | "))")
        copyService.synchronize(urls: urls, stagedPaths: claimedJob.job.stagedPaths) { [weak self] outcome in
            guard let self else {
                return
            }

            switch outcome.queueResolution {
            case .complete:
                self.jobQueue.complete(claimedJob)
            case .retryLater(let paths, let stagedPaths):
                self.enqueueRetryJob(
                    claimedJob,
                    outcome: outcome,
                    paths: paths,
                    stagedPaths: stagedPaths
                )
            case .blockedUntilAuthorization(let paths, let stagedPaths):
                self.blockUntilAuthorization(
                    claimedJob,
                    outcome: outcome,
                    paths: paths,
                    stagedPaths: stagedPaths
                )
            case .failedPermanently:
                self.jobQueue.fail(claimedJob, errorMessage: outcome.failureSummary)
            }

            NoticePresenter.showTimedNotice(outcome.noticeKind, terminateAfterClose: false) { [weak self] in
                self?.isProcessingJob = false
                self?.processPendingFinderSyncJobs()
            }
        }
    }

    private func enqueueRetryJob(
        _ claimedJob: FinderSyncClaimedJob,
        outcome: FinderSyncCopyOutcome,
        paths: [String],
        stagedPaths: [String]
    ) {
        do {
            let retryResult = try jobQueue.retryLater(
                claimedJob,
                errorMessage: outcome.failureSummary,
                paths: paths,
                stagedPaths: stagedPaths
            )
            switch retryResult {
            case .scheduled(let job):
                AppLogger.log("agent sync job scheduled retry id=\(job.id) attempt=\(job.attemptCount) nextAttemptAt=\(job.nextAttemptAt ?? "none") reason=\(job.lastError ?? "unknown")")
            case .exhausted(let job):
                AppLogger.log("agent sync job exhausted retries id=\(job.id) attempt=\(job.attemptCount) reason=\(job.lastError ?? "unknown")")
            }
        } catch {
            AppLogger.log("agent sync job retry write failed id=\(claimedJob.job.id) error=\(error.localizedDescription)")
        }
    }

    private func blockUntilAuthorization(
        _ claimedJob: FinderSyncClaimedJob,
        outcome: FinderSyncCopyOutcome,
        paths: [String],
        stagedPaths: [String]
    ) {
        do {
            let job = try jobQueue.blockUntilAuthorization(
                claimedJob,
                errorMessage: outcome.failureSummary,
                paths: paths,
                stagedPaths: stagedPaths
            )
            AppLogger.log("agent sync job blocked for Photos authorization id=\(job.id) reason=\(job.lastError ?? "unknown")")
        } catch {
            AppLogger.log("agent sync job authorization block write failed id=\(claimedJob.job.id) error=\(error.localizedDescription)")
        }
    }
}
