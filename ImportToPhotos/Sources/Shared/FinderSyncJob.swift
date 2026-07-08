import Foundation

struct FinderSyncQueuedJob: Codable {
    let id: String
    let createdAt: String
    let paths: [String]
    let attemptCount: Int
    let maxAttempts: Int
    let nextAttemptAt: String?
    let lastAttemptAt: String?
    let lastError: String?
    let stagedPaths: [String]

    init(
        id: String,
        createdAt: String,
        paths: [String],
        attemptCount: Int = 0,
        maxAttempts: Int = 3,
        nextAttemptAt: String? = nil,
        lastAttemptAt: String? = nil,
        lastError: String? = nil,
        stagedPaths: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.paths = paths
        self.attemptCount = max(0, attemptCount)
        self.maxAttempts = max(1, maxAttempts)
        self.nextAttemptAt = nextAttemptAt
        self.lastAttemptAt = lastAttemptAt
        self.lastError = lastError
        self.stagedPaths = stagedPaths
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case paths
        case attemptCount
        case maxAttempts
        case nextAttemptAt
        case lastAttemptAt
        case lastError
        case stagedPaths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        paths = try container.decode([String].self, forKey: .paths)
        attemptCount = max(0, try container.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 0)
        maxAttempts = max(1, try container.decodeIfPresent(Int.self, forKey: .maxAttempts) ?? 3)
        nextAttemptAt = try container.decodeIfPresent(String.self, forKey: .nextAttemptAt)
        lastAttemptAt = try container.decodeIfPresent(String.self, forKey: .lastAttemptAt)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        stagedPaths = try container.decodeIfPresent([String].self, forKey: .stagedPaths) ?? []
    }

    func withLastAttempt(at dateString: String) -> FinderSyncQueuedJob {
        FinderSyncQueuedJob(
            id: id,
            createdAt: createdAt,
            paths: paths,
            attemptCount: attemptCount,
            maxAttempts: maxAttempts,
            nextAttemptAt: nextAttemptAt,
            lastAttemptAt: dateString,
            lastError: lastError,
            stagedPaths: stagedPaths
        )
    }

    func withRetry(
        attemptCount nextAttemptCount: Int,
        nextAttemptAt nextAttemptDateString: String?,
        lastError nextLastError: String,
        paths nextPaths: [String]? = nil,
        stagedPaths nextStagedPaths: [String]? = nil
    ) -> FinderSyncQueuedJob {
        FinderSyncQueuedJob(
            id: id,
            createdAt: createdAt,
            paths: nextPaths ?? paths,
            attemptCount: nextAttemptCount,
            maxAttempts: maxAttempts,
            nextAttemptAt: nextAttemptDateString,
            lastAttemptAt: lastAttemptAt,
            lastError: nextLastError,
            stagedPaths: nextStagedPaths ?? stagedPaths
        )
    }

    func withStagedPaths(_ nextStagedPaths: [String]) -> FinderSyncQueuedJob {
        FinderSyncQueuedJob(
            id: id,
            createdAt: createdAt,
            paths: paths,
            attemptCount: attemptCount,
            maxAttempts: maxAttempts,
            nextAttemptAt: nextAttemptAt,
            lastAttemptAt: lastAttemptAt,
            lastError: lastError,
            stagedPaths: nextStagedPaths
        )
    }
}

struct FinderSyncClaimedJob {
    let job: FinderSyncQueuedJob
    let processingURL: URL
}

enum QueueRetryResult {
    case scheduled(FinderSyncQueuedJob)
    case exhausted(FinderSyncQueuedJob)
}
