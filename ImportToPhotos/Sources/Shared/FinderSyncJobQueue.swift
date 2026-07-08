import Foundation

final class FinderSyncJobQueue {
    private let directory: URL
    private let fileManager: FileManager
    private let staleProcessingInterval: TimeInterval
    private let dateFormatter = ISO8601DateFormatter()

    init(
        directory: URL = AppConfig.finderSyncJobDirectory(),
        fileManager: FileManager = .default,
        staleProcessingInterval: TimeInterval = 600
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.staleProcessingInterval = staleProcessingInterval
    }

    @discardableResult
    func enqueue(paths: [String]) throws -> FinderSyncQueuedJob {
        let job = FinderSyncQueuedJob(
            id: UUID().uuidString,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            paths: paths
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let jobURL = directory.appendingPathComponent("\(job.id).json", isDirectory: false)
        let data = try JSONEncoder().encode(job)
        try data.write(to: jobURL, options: [.atomic])
        return job
    }

    func claimNextJob() throws -> FinderSyncClaimedJob? {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try recoverStaleProcessingJobs()
        let jobURLs = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
            .filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate < rhsDate
            }

        for jobURL in jobURLs {
            let data: Data
            let queuedJob: FinderSyncQueuedJob
            do {
                data = try Data(contentsOf: jobURL)
                queuedJob = try JSONDecoder().decode(FinderSyncQueuedJob.self, from: data)
            } catch {
                markFileFailed(jobURL)
                throw error
            }

            guard isDue(queuedJob, referenceDate: Date()) else {
                continue
            }

            let processingURL = jobURL
                .deletingPathExtension()
                .appendingPathExtension("processing")
            try? fileManager.removeItem(at: processingURL)
            try fileManager.moveItem(at: jobURL, to: processingURL)

            let claimedJob = queuedJob.withLastAttempt(at: dateFormatter.string(from: Date()))
            try write(claimedJob, to: processingURL)
            return FinderSyncClaimedJob(job: claimedJob, processingURL: processingURL)
        }

        return nil
    }

    func complete(_ claimedJob: FinderSyncClaimedJob) {
        try? fileManager.removeItem(at: claimedJob.processingURL)
    }

    func fail(_ claimedJob: FinderSyncClaimedJob, errorMessage: String = "Permanent failure") {
        let failedJob = claimedJob.job.withRetry(
            attemptCount: claimedJob.job.attemptCount,
            nextAttemptAt: nil,
            lastError: errorMessage
        )
        markProcessingFileFailed(claimedJob.processingURL, job: failedJob)
    }

    @discardableResult
    func retryLater(_ claimedJob: FinderSyncClaimedJob,
        errorMessage: String = "Retryable failure",
        paths: [String]? = nil,
        stagedPaths: [String]? = nil,
        referenceDate: Date = Date()
    ) throws -> QueueRetryResult {
        let nextAttemptCount = claimedJob.job.attemptCount + 1
        let nextPaths = paths ?? claimedJob.job.paths
        let nextStagedPaths = stagedPaths ?? claimedJob.job.stagedPaths
        let retryJob: FinderSyncQueuedJob
        if nextAttemptCount >= claimedJob.job.maxAttempts {
            retryJob = claimedJob.job.withRetry(
                attemptCount: nextAttemptCount,
                nextAttemptAt: nil,
                lastError: errorMessage,
                paths: nextPaths,
                stagedPaths: nextStagedPaths
            )
            markProcessingFileFailed(claimedJob.processingURL, job: retryJob)
            return .exhausted(retryJob)
        }

        let nextAttemptAt = referenceDate.addingTimeInterval(retryBackoff(afterAttempt: nextAttemptCount))
        retryJob = claimedJob.job.withRetry(
            attemptCount: nextAttemptCount,
            nextAttemptAt: dateFormatter.string(from: nextAttemptAt),
            lastError: errorMessage,
            paths: nextPaths,
            stagedPaths: nextStagedPaths
        )
        try replaceProcessingFileWithRetryJob(retryJob, processingURL: claimedJob.processingURL)
        return .scheduled(retryJob)
    }

    func recoverStaleProcessingJobs(referenceDate: Date = Date()) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let processingURLs = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
            .filter { $0.pathExtension == "processing" }

        for processingURL in processingURLs {
            let modifiedAt = (try? processingURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            guard referenceDate.timeIntervalSince(modifiedAt) >= staleProcessingInterval else {
                continue
            }

            let retryURL = processingURL
                .deletingPathExtension()
                .appendingPathExtension("json")
            try? fileManager.removeItem(at: retryURL)
            try fileManager.moveItem(at: processingURL, to: retryURL)
        }
    }

    private func retryBackoff(afterAttempt attemptCount: Int) -> TimeInterval {
        let schedule: [TimeInterval] = [30, 120, 600, 1_800]
        return schedule[min(max(0, attemptCount - 1), schedule.count - 1)]
    }

    private func isDue(_ job: FinderSyncQueuedJob, referenceDate: Date) -> Bool {
        guard let nextAttemptAt = job.nextAttemptAt,
              let retryDate = dateFormatter.date(from: nextAttemptAt) else {
            return true
        }

        return retryDate <= referenceDate
    }

    private func write(_ job: FinderSyncQueuedJob, to url: URL) throws {
        let data = try JSONEncoder().encode(job)
        try data.write(to: url, options: [.atomic])
    }

    private func replaceProcessingFileWithRetryJob(
        _ job: FinderSyncQueuedJob,
        processingURL: URL
    ) throws {
        let retryURL = processingURL
            .deletingPathExtension()
            .appendingPathExtension("json")
        let temporaryURL = directory
            .appendingPathComponent(".\(job.id)-\(UUID().uuidString)", isDirectory: false)
            .appendingPathExtension("tmp")

        do {
            try write(job, to: temporaryURL)
            try? fileManager.removeItem(at: retryURL)
            try fileManager.moveItem(at: temporaryURL, to: retryURL)
            try fileManager.removeItem(at: processingURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func markFileFailed(_ url: URL) {
        let failedURL = url
            .deletingPathExtension()
            .appendingPathExtension("failed")
        try? fileManager.removeItem(at: failedURL)
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.moveItem(at: url, to: failedURL)
        }
    }

    private func markProcessingFileFailed(_ processingURL: URL, job: FinderSyncQueuedJob? = nil) {
        let failedURL = processingURL
            .deletingPathExtension()
            .appendingPathExtension("failed")
        try? fileManager.removeItem(at: failedURL)
        if let job {
            do {
                try write(job, to: failedURL)
                try fileManager.removeItem(at: processingURL)
            } catch {
                try? fileManager.removeItem(at: failedURL)
            }
        } else if fileManager.fileExists(atPath: processingURL.path) {
            try? fileManager.moveItem(at: processingURL, to: failedURL)
        }
    }
}
