import Foundation

public struct SessionIndexEntry: Sendable, Equatable {
    public let threadID: String
    public let title: String
    public let updatedAt: Date

    public init(threadID: String, title: String, updatedAt: Date) {
        self.threadID = threadID
        self.title = title
        self.updatedAt = updatedAt
    }
}

public struct ThreadSnapshot: Sendable, Equatable {
    public let threadID: String
    public let title: String
    public let source: String
    public let cwd: String?
    public let updatedAt: Date
    public let firstUserMessage: String?

    public init(threadID: String, title: String, source: String, cwd: String?, updatedAt: Date, firstUserMessage: String? = nil) {
        self.threadID = threadID
        self.title = title
        self.source = source
        self.cwd = cwd
        self.updatedAt = updatedAt
        self.firstUserMessage = firstUserMessage
    }
}

public struct LogRow: Sendable, Equatable {
    public let id: Int64
    public let timestamp: Int64
    public let level: String
    public let target: String
    public let body: String
    public let threadID: String?
    public let processUUID: String?

    public init(id: Int64, timestamp: Int64, level: String, target: String, body: String, threadID: String?, processUUID: String?) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.target = target
        self.body = body
        self.threadID = threadID
        self.processUUID = processUUID
    }
}

public enum CodexLogEventKind: String, Sendable, Equatable {
    case responseCreated
    case responseInProgress
    case responseCompleted
    case toolStarted
    case toolUpdated
    case toolCompleted
}

public struct CodexLogEvent: Sendable, Equatable {
    public let threadID: String
    public let kind: CodexLogEventKind
    public let toolName: String?
    public let summary: String
    public let timestamp: Date

    public init(threadID: String, kind: CodexLogEventKind, toolName: String?, summary: String, timestamp: Date) {
        self.threadID = threadID
        self.kind = kind
        self.toolName = toolName
        self.summary = summary
        self.timestamp = timestamp
    }
}

public struct SessionMessagePreview: Sendable, Equatable {
    public enum Author: String, Sendable, Equatable {
        case user
        case assistant
    }

    public let threadID: String
    public let author: Author
    public let text: String
    public let timestamp: Date

    public init(threadID: String, author: Author, text: String, timestamp: Date) {
        self.threadID = threadID
        self.author = author
        self.text = text
        self.timestamp = timestamp
    }
}

public struct SessionPreview: Sendable, Equatable, Identifiable {
    public let id: String
    public let threadID: String
    public let title: String
    public let statusText: String
    public let sourceLabel: String
    public let userPreview: String?
    public let assistantPreview: String?
    public let latestToolSummary: String?
    public let updatedAt: Date
    public let isPrimary: Bool

    public init(
        threadID: String,
        title: String,
        statusText: String,
        sourceLabel: String,
        userPreview: String?,
        assistantPreview: String?,
        latestToolSummary: String?,
        updatedAt: Date,
        isPrimary: Bool
    ) {
        self.id = threadID
        self.threadID = threadID
        self.title = title
        self.statusText = statusText
        self.sourceLabel = sourceLabel
        self.userPreview = userPreview
        self.assistantPreview = assistantPreview
        self.latestToolSummary = latestToolSummary
        self.updatedAt = updatedAt
        self.isPrimary = isPrimary
    }
}

public struct IslandSnapshot: Sendable, Equatable {
    public let primaryThreadID: String?
    public let threadTitle: String
    public let statusText: String
    public let latestToolSummary: String?
    public let sourceLabel: String
    public let activeSessionCount: Int
    public let sessionPreviews: [SessionPreview]
    public let shouldNotifyCompletion: Bool

    public init(
        primaryThreadID: String?,
        threadTitle: String,
        statusText: String,
        latestToolSummary: String?,
        sourceLabel: String,
        activeSessionCount: Int,
        sessionPreviews: [SessionPreview],
        shouldNotifyCompletion: Bool
    ) {
        self.primaryThreadID = primaryThreadID
        self.threadTitle = threadTitle
        self.statusText = statusText
        self.latestToolSummary = latestToolSummary
        self.sourceLabel = sourceLabel
        self.activeSessionCount = activeSessionCount
        self.sessionPreviews = sessionPreviews
        self.shouldNotifyCompletion = shouldNotifyCompletion
    }
}
