import Foundation

/// Ported from: lib/core/domain/entities/provider_entity.dart
public enum TicketProviderEntity: Codable, Hashable, Sendable {
    case zentaoBug(ZenTaoBugEntity)
    case zentaoTask(ZenTaoTaskEntity)
    case gitlabItem(GitLabItemEntity)
    case githubItem(GitHubItemEntity)
}

/// One subtask of a parent task (any level below it), as listed on the parent.
public struct TicketSubtask: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var status: UnifiedStatus
    public var priority: Int?
    public var assignee: String?
    /// The subtask's own parent: ZenTao lists every descendant of a task flat, so this is what nests a grandchild under
    /// its parent. Nil in items stored before it was kept (they show as direct subtasks).
    public var parentId: String?
    public init(id: String, title: String, status: UnifiedStatus, priority: Int? = nil, assignee: String? = nil,
                parentId: String? = nil) {
        self.id = id; self.title = title; self.status = status; self.priority = priority; self.assignee = assignee
        self.parentId = parentId
    }
}

public struct TicketAttachment: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var url: String
    public var `extension`: String?
    public var size: Int?
    public var addedBy: String?
    public var addedDate: Date?
    public var streamUrl: String?
    public init(id: String, title: String, url: String, extension ext: String? = nil, size: Int? = nil,
                addedBy: String? = nil, addedDate: Date? = nil, streamUrl: String? = nil) {
        self.id = id; self.title = title; self.url = url; self.extension = ext; self.size = size
        self.addedBy = addedBy; self.addedDate = addedDate; self.streamUrl = streamUrl
    }
}

public struct ZenTaoBugEntity: Codable, Hashable, Sendable {
    public var product, project, execution, branch, module, story, task, plan: String?
    public var productName, projectName, executionName, storyTitle, taskName, planName: String?
    public var bugType, os, browser: String?
    public var confirmed, severity, activatedCount: Int?
    public var resolution: String?
    public var openedBy, openedByHandle: String?
    public var openedDate: Date?
    public var openedBuild, assignedTo: String?
    public var assignedDate: Date?
    public var deadline, resolvedBy, resolvedByHandle: String?
    public var resolvedDate: Date?
    public var resolvedBuild, closedBy: String?
    public var closedDate: Date?
    public var lastEditedBy: String?
    public var lastEditedDate: Date?
    public var attachments: [TicketAttachment]

    public init(product: String? = nil, project: String? = nil, execution: String? = nil, branch: String? = nil,
                module: String? = nil, story: String? = nil, task: String? = nil, plan: String? = nil,
                productName: String? = nil, projectName: String? = nil, executionName: String? = nil,
                storyTitle: String? = nil, taskName: String? = nil, planName: String? = nil,
                bugType: String? = nil, os: String? = nil, browser: String? = nil, confirmed: Int? = nil,
                severity: Int? = nil, activatedCount: Int? = nil, resolution: String? = nil,
                openedBy: String? = nil, openedByHandle: String? = nil, openedDate: Date? = nil,
                openedBuild: String? = nil, assignedTo: String? = nil, assignedDate: Date? = nil,
                deadline: String? = nil, resolvedBy: String? = nil, resolvedByHandle: String? = nil,
                resolvedDate: Date? = nil, resolvedBuild: String? = nil, closedBy: String? = nil,
                closedDate: Date? = nil, lastEditedBy: String? = nil, lastEditedDate: Date? = nil,
                attachments: [TicketAttachment] = []) {
        self.product = product; self.project = project; self.execution = execution; self.branch = branch
        self.module = module; self.story = story; self.task = task; self.plan = plan
        self.productName = productName; self.projectName = projectName; self.executionName = executionName
        self.storyTitle = storyTitle; self.taskName = taskName; self.planName = planName
        self.bugType = bugType; self.os = os; self.browser = browser; self.confirmed = confirmed
        self.severity = severity; self.activatedCount = activatedCount; self.resolution = resolution
        self.openedBy = openedBy; self.openedByHandle = openedByHandle; self.openedDate = openedDate
        self.openedBuild = openedBuild; self.assignedTo = assignedTo; self.assignedDate = assignedDate
        self.deadline = deadline; self.resolvedBy = resolvedBy; self.resolvedByHandle = resolvedByHandle
        self.resolvedDate = resolvedDate; self.resolvedBuild = resolvedBuild; self.closedBy = closedBy
        self.closedDate = closedDate; self.lastEditedBy = lastEditedBy; self.lastEditedDate = lastEditedDate
        self.attachments = attachments
    }
    private enum CodingKeys: String, CodingKey {
        case product, project, execution, branch, module, story, task, plan, productName, projectName
        case executionName, storyTitle, taskName, planName, bugType, os, browser, confirmed, severity
        case activatedCount, resolution, openedBy, openedByHandle, openedDate, openedBuild, assignedTo
        case assignedDate, deadline, resolvedBy, resolvedByHandle, resolvedDate, resolvedBuild, closedBy
        case closedDate, lastEditedBy, lastEditedDate, attachments
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String? { try? c.decodeIfPresent(String.self, forKey: k) }
        func i(_ k: CodingKeys) -> Int? { try? c.decodeIfPresent(Int.self, forKey: k) }
        func dt(_ k: CodingKeys) -> Date? { try? c.decodeIfPresent(Date.self, forKey: k) }
        product = s(.product); project = s(.project); execution = s(.execution); branch = s(.branch)
        module = s(.module); story = s(.story); task = s(.task); plan = s(.plan)
        productName = s(.productName); projectName = s(.projectName); executionName = s(.executionName)
        storyTitle = s(.storyTitle); taskName = s(.taskName); planName = s(.planName)
        bugType = s(.bugType); os = s(.os); browser = s(.browser); confirmed = i(.confirmed)
        severity = i(.severity); activatedCount = i(.activatedCount); resolution = s(.resolution)
        openedBy = s(.openedBy); openedByHandle = s(.openedByHandle); openedDate = dt(.openedDate)
        openedBuild = s(.openedBuild); assignedTo = s(.assignedTo); assignedDate = dt(.assignedDate)
        deadline = s(.deadline); resolvedBy = s(.resolvedBy); resolvedByHandle = s(.resolvedByHandle)
        resolvedDate = dt(.resolvedDate); resolvedBuild = s(.resolvedBuild); closedBy = s(.closedBy)
        closedDate = dt(.closedDate); lastEditedBy = s(.lastEditedBy); lastEditedDate = dt(.lastEditedDate)
        attachments = c.value(.attachments, default: [])
    }
}

public struct ZenTaoTaskEntity: Codable, Hashable, Sendable {
    public var parentId, parentName: String?
    public var subtasks: [TicketSubtask]
    public var execution, project, module: String?
    public var isParent: Bool
    public var estimate, consumed, left: Double?
    public var realStarted: Date?
    public var openedByHandle, taskType, executionName, story, storyTitle, fromBug: String?
    public var estStarted, deadline, openedBy: String?
    public var openedDate: Date?
    public var finishedBy, finishedByHandle: String?
    public var finishedDate: Date?
    public var closedBy: String?
    public var closedDate, lastEditedDate: Date?

    public init(parentId: String? = nil, parentName: String? = nil, subtasks: [TicketSubtask] = [],
                execution: String? = nil, project: String? = nil, module: String? = nil, isParent: Bool = false,
                estimate: Double? = nil, consumed: Double? = nil, left: Double? = nil, realStarted: Date? = nil,
                openedByHandle: String? = nil, taskType: String? = nil, executionName: String? = nil,
                story: String? = nil, storyTitle: String? = nil, fromBug: String? = nil, estStarted: String? = nil,
                deadline: String? = nil, openedBy: String? = nil, openedDate: Date? = nil,
                finishedBy: String? = nil, finishedByHandle: String? = nil, finishedDate: Date? = nil,
                closedBy: String? = nil, closedDate: Date? = nil, lastEditedDate: Date? = nil) {
        self.parentId = parentId; self.parentName = parentName; self.subtasks = subtasks
        self.execution = execution; self.project = project; self.module = module; self.isParent = isParent
        self.estimate = estimate; self.consumed = consumed; self.left = left; self.realStarted = realStarted
        self.openedByHandle = openedByHandle; self.taskType = taskType; self.executionName = executionName
        self.story = story; self.storyTitle = storyTitle; self.fromBug = fromBug; self.estStarted = estStarted
        self.deadline = deadline; self.openedBy = openedBy; self.openedDate = openedDate
        self.finishedBy = finishedBy; self.finishedByHandle = finishedByHandle; self.finishedDate = finishedDate
        self.closedBy = closedBy; self.closedDate = closedDate; self.lastEditedDate = lastEditedDate
    }
    private enum CodingKeys: String, CodingKey {
        case parentId, parentName, subtasks, execution, project, module, isParent, estimate, consumed, left
        case realStarted, openedByHandle, taskType, executionName, story, storyTitle, fromBug, estStarted
        case deadline, openedBy, openedDate, finishedBy, finishedByHandle, finishedDate, closedBy
        case closedDate, lastEditedDate
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String? { try? c.decodeIfPresent(String.self, forKey: k) }
        func n(_ k: CodingKeys) -> Double? { try? c.decodeIfPresent(Double.self, forKey: k) }
        func dt(_ k: CodingKeys) -> Date? { try? c.decodeIfPresent(Date.self, forKey: k) }
        parentId = s(.parentId); parentName = s(.parentName); subtasks = c.value(.subtasks, default: [])
        execution = s(.execution); project = s(.project); module = s(.module)
        isParent = c.value(.isParent, default: false)
        estimate = n(.estimate); consumed = n(.consumed); left = n(.left); realStarted = dt(.realStarted)
        openedByHandle = s(.openedByHandle); taskType = s(.taskType); executionName = s(.executionName)
        story = s(.story); storyTitle = s(.storyTitle); fromBug = s(.fromBug); estStarted = s(.estStarted)
        deadline = s(.deadline); openedBy = s(.openedBy); openedDate = dt(.openedDate)
        finishedBy = s(.finishedBy); finishedByHandle = s(.finishedByHandle); finishedDate = dt(.finishedDate)
        closedBy = s(.closedBy); closedDate = dt(.closedDate); lastEditedDate = dt(.lastEditedDate)
    }
}

public struct GitLabItemEntity: Codable, Hashable, Sendable {
    public var projectPath: String?
    public var projectId: Int?
    public var author, authorAvatarUrl, sourceBranch, targetBranch, mergeStatus: String?
    public var commitsBehind: Int?
    public var draft: Bool?
    public var upvotes, additions, deletions, changedFiles, milestoneId: Int?
    public var milestoneTitle, humanTimeEstimate, humanTotalTimeSpent, mergedBy: String?
    public var mergedAt: Date?
    public var closedBy: String?
    public var closedAt: Date?
    public var mergeCommitSha, squashCommitSha: String?
    public var squash, removeSourceBranch: Bool?
    public var approvedBy: [String]
    public var approvalsRequired, approvalsLeft: Int?
    public var userHasApproved, userCanApprove: Bool?
    public var reviewers, assignees, assigneeLogins: [String]
    public var userAvatarUrls, labelColors, labelTextColors: [String: String]

    public init(projectPath: String? = nil, projectId: Int? = nil, author: String? = nil, authorAvatarUrl: String? = nil,
                sourceBranch: String? = nil, targetBranch: String? = nil, mergeStatus: String? = nil,
                commitsBehind: Int? = nil, draft: Bool? = nil, upvotes: Int? = nil, additions: Int? = nil,
                deletions: Int? = nil, changedFiles: Int? = nil, milestoneId: Int? = nil, milestoneTitle: String? = nil,
                humanTimeEstimate: String? = nil, humanTotalTimeSpent: String? = nil, mergedBy: String? = nil,
                mergedAt: Date? = nil, closedBy: String? = nil, closedAt: Date? = nil, mergeCommitSha: String? = nil,
                squashCommitSha: String? = nil, squash: Bool? = nil, removeSourceBranch: Bool? = nil,
                approvedBy: [String] = [], approvalsRequired: Int? = nil, approvalsLeft: Int? = nil,
                userHasApproved: Bool? = nil, userCanApprove: Bool? = nil, reviewers: [String] = [],
                assignees: [String] = [], assigneeLogins: [String] = [], userAvatarUrls: [String: String] = [:],
                labelColors: [String: String] = [:], labelTextColors: [String: String] = [:]) {
        self.projectPath = projectPath; self.projectId = projectId; self.author = author
        self.authorAvatarUrl = authorAvatarUrl; self.sourceBranch = sourceBranch; self.targetBranch = targetBranch
        self.mergeStatus = mergeStatus; self.commitsBehind = commitsBehind; self.draft = draft
        self.upvotes = upvotes; self.additions = additions; self.deletions = deletions
        self.changedFiles = changedFiles; self.milestoneId = milestoneId; self.milestoneTitle = milestoneTitle
        self.humanTimeEstimate = humanTimeEstimate; self.humanTotalTimeSpent = humanTotalTimeSpent
        self.mergedBy = mergedBy; self.mergedAt = mergedAt; self.closedBy = closedBy; self.closedAt = closedAt
        self.mergeCommitSha = mergeCommitSha; self.squashCommitSha = squashCommitSha; self.squash = squash
        self.removeSourceBranch = removeSourceBranch; self.approvedBy = approvedBy
        self.approvalsRequired = approvalsRequired; self.approvalsLeft = approvalsLeft
        self.userHasApproved = userHasApproved; self.userCanApprove = userCanApprove
        self.reviewers = reviewers; self.assignees = assignees; self.assigneeLogins = assigneeLogins
        self.userAvatarUrls = userAvatarUrls; self.labelColors = labelColors; self.labelTextColors = labelTextColors
    }
    private enum CodingKeys: String, CodingKey {
        case projectPath, projectId, author, authorAvatarUrl, sourceBranch, targetBranch, mergeStatus
        case commitsBehind, draft, upvotes, additions, deletions, changedFiles, milestoneId, milestoneTitle
        case humanTimeEstimate, humanTotalTimeSpent, mergedBy, mergedAt, closedBy, closedAt, mergeCommitSha
        case squashCommitSha, squash, removeSourceBranch, approvedBy, approvalsRequired, approvalsLeft
        case userHasApproved, userCanApprove, reviewers, assignees, assigneeLogins, userAvatarUrls
        case labelColors, labelTextColors
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String? { try? c.decodeIfPresent(String.self, forKey: k) }
        func i(_ k: CodingKeys) -> Int? { try? c.decodeIfPresent(Int.self, forKey: k) }
        func b(_ k: CodingKeys) -> Bool? { try? c.decodeIfPresent(Bool.self, forKey: k) }
        func dt(_ k: CodingKeys) -> Date? { try? c.decodeIfPresent(Date.self, forKey: k) }
        projectPath = s(.projectPath); projectId = i(.projectId); author = s(.author)
        authorAvatarUrl = s(.authorAvatarUrl); sourceBranch = s(.sourceBranch); targetBranch = s(.targetBranch)
        mergeStatus = s(.mergeStatus); commitsBehind = i(.commitsBehind); draft = b(.draft)
        upvotes = i(.upvotes); additions = i(.additions); deletions = i(.deletions)
        changedFiles = i(.changedFiles); milestoneId = i(.milestoneId); milestoneTitle = s(.milestoneTitle)
        humanTimeEstimate = s(.humanTimeEstimate); humanTotalTimeSpent = s(.humanTotalTimeSpent)
        mergedBy = s(.mergedBy); mergedAt = dt(.mergedAt); closedBy = s(.closedBy); closedAt = dt(.closedAt)
        mergeCommitSha = s(.mergeCommitSha); squashCommitSha = s(.squashCommitSha); squash = b(.squash)
        removeSourceBranch = b(.removeSourceBranch); approvedBy = c.value(.approvedBy, default: [])
        approvalsRequired = i(.approvalsRequired); approvalsLeft = i(.approvalsLeft)
        userHasApproved = b(.userHasApproved); userCanApprove = b(.userCanApprove)
        reviewers = c.value(.reviewers, default: []); assignees = c.value(.assignees, default: [])
        assigneeLogins = c.value(.assigneeLogins, default: [])
        userAvatarUrls = c.value(.userAvatarUrls, default: [:]); labelColors = c.value(.labelColors, default: [:])
        labelTextColors = c.value(.labelTextColors, default: [:])
    }
}

public struct GitHubItemEntity: Codable, Hashable, Sendable {
    public var repo, author, authorAvatarUrl, headBranch, baseBranch, mergeableState: String?
    public var draft, merged: Bool?
    public var comments, additions, deletions, changedFiles: Int?
    public var reviewers, assignees, assigneeLogins, reviewerLogins: [String]

    public init(repo: String? = nil, author: String? = nil, authorAvatarUrl: String? = nil, headBranch: String? = nil,
                baseBranch: String? = nil, mergeableState: String? = nil, draft: Bool? = nil, merged: Bool? = nil,
                comments: Int? = nil, additions: Int? = nil, deletions: Int? = nil, changedFiles: Int? = nil,
                reviewers: [String] = [], assignees: [String] = [], assigneeLogins: [String] = [],
                reviewerLogins: [String] = []) {
        self.repo = repo; self.author = author; self.authorAvatarUrl = authorAvatarUrl
        self.headBranch = headBranch; self.baseBranch = baseBranch; self.mergeableState = mergeableState
        self.draft = draft; self.merged = merged; self.comments = comments; self.additions = additions
        self.deletions = deletions; self.changedFiles = changedFiles; self.reviewers = reviewers
        self.assignees = assignees; self.assigneeLogins = assigneeLogins; self.reviewerLogins = reviewerLogins
    }
    private enum CodingKeys: String, CodingKey {
        case repo, author, authorAvatarUrl, headBranch, baseBranch, mergeableState, draft, merged
        case comments, additions, deletions, changedFiles, reviewers, assignees, assigneeLogins, reviewerLogins
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String? { try? c.decodeIfPresent(String.self, forKey: k) }
        func i(_ k: CodingKeys) -> Int? { try? c.decodeIfPresent(Int.self, forKey: k) }
        func b(_ k: CodingKeys) -> Bool? { try? c.decodeIfPresent(Bool.self, forKey: k) }
        repo = s(.repo); author = s(.author); authorAvatarUrl = s(.authorAvatarUrl); headBranch = s(.headBranch)
        baseBranch = s(.baseBranch); mergeableState = s(.mergeableState); draft = b(.draft); merged = b(.merged)
        comments = i(.comments); additions = i(.additions); deletions = i(.deletions); changedFiles = i(.changedFiles)
        reviewers = c.value(.reviewers, default: []); assignees = c.value(.assignees, default: [])
        assigneeLogins = c.value(.assigneeLogins, default: []); reviewerLogins = c.value(.reviewerLogins, default: [])
    }
}
