import DiffAdapters
import Foundation
import SwiftGit

public enum GitDiffScope: String, CaseIterable, Identifiable, Sendable {
    case unstaged
    case staged
    case branch

    public var id: String { rawValue }
}

public enum GitDiffChangeKind: String, Hashable, Codable, Sendable {
    case added
    case modified
    case deleted
    case renamed
    case copied
    case untracked
    case typeChanged
    case unmerged
    case unknown
}

public struct GitDiffCatalogEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public var status: GitDiffChangeKind
    public var relativePath: String
    public var originalRelativePath: String?

    public init(
        id: String,
        status: GitDiffChangeKind,
        relativePath: String,
        originalRelativePath: String? = nil
    ) {
        self.id = id
        self.status = status
        self.relativePath = relativePath
        self.originalRelativePath = originalRelativePath
    }
}

public struct GitDiffCatalog: Hashable, Sendable {
    public var entries: [GitDiffCatalogEntry]
    public var totalAddedLineCount: Int
    public var totalRemovedLineCount: Int
    public var issueMessage: String?
    public var branchLabel: String?

    public init(
        entries: [GitDiffCatalogEntry],
        totalAddedLineCount: Int = 0,
        totalRemovedLineCount: Int = 0,
        issueMessage: String? = nil,
        branchLabel: String? = nil
    ) {
        self.entries = entries
        self.totalAddedLineCount = totalAddedLineCount
        self.totalRemovedLineCount = totalRemovedLineCount
        self.issueMessage = issueMessage
        self.branchLabel = branchLabel
    }
}

public enum GitDiffFileLoadResult: Hashable, Sendable {
    case diff(LineBasedDiffFile)
    case tooLarge(message: String)
    case unavailable(message: String)
}

public enum GitDiffLoader {
    public static let maximumFileBytes = 512_000
    package static let maximumInlinePreviewBytes = 2_000_000
    package static let maximumRenderableChangeCount = 5_000
    package static let maximumSimilarityDetectionDeltaCount = 1_000

    private struct RepositoryContext {
        let repository: Repository
        let rootPath: String
        let repositoryRootPath: String
        let relativeBasePath: String?
    }

    private struct ScopedDiff {
        let diff: SwiftGit.Diff
        let branchLabel: String?
    }

    private enum CatalogContext {
        case available(branchLabel: String?)
        case unavailable(message: String)
    }

    private enum LoaderError: Error {
        case bareRepository
        case missingUpstream
    }

    private enum DiffLoadDetail {
        case catalog
        case full
        case selectedFile(relativePath: String)

        var requiresFullUntrackedContent: Bool {
            switch self {
            case .catalog:
                return false
            case .full, .selectedFile:
                return true
            }
        }

        func pathspecs(context: RepositoryContext) -> [String]? {
            switch self {
            case .catalog, .full:
                return nil
            case let .selectedFile(relativePath):
                return [GitDiffLoader.repositoryRelativePath(for: relativePath, context: context)]
            }
        }
    }

    public static func loadCatalog(
        rootPath: String,
        scope: GitDiffScope
    ) -> GitDiffCatalog {
        do {
            let context = try repositoryContext(rootPath: rootPath)
            switch try catalogContext(context: context, scope: scope) {
            case let .unavailable(message):
                return GitDiffCatalog(entries: [], issueMessage: message)
            case let .available(branchLabel):
                let scopedDiff = try loadScopedDiff(
                    context: context,
                    scope: scope,
                    branchLabelOverride: branchLabel,
                    detail: .catalog
                )
                let stats = try scopedDiff.diff.stats()
                return GitDiffCatalog(
                    entries: makeCatalogEntries(from: scopedDiff.diff, context: context),
                    totalAddedLineCount: stats.insertions,
                    totalRemovedLineCount: stats.deletions,
                    issueMessage: nil,
                    branchLabel: scopedDiff.branchLabel
                )
            }
        } catch {
            return GitDiffCatalog(
                entries: [],
                issueMessage: "Git changes are unavailable because this directory is not a Git repository."
            )
        }
    }

    public static func loadFileDiff(
        rootPath: String,
        scope: GitDiffScope,
        relativePath: String,
        forceLargeDiff: Bool = false
    ) -> GitDiffFileLoadResult {
        do {
            let context = try repositoryContext(rootPath: rootPath)
            switch try catalogContext(context: context, scope: scope) {
            case let .unavailable(message):
                return .unavailable(message: message)
            case let .available(branchLabel):
                let scopedDiff = try loadScopedDiff(
                    context: context,
                    scope: scope,
                    branchLabelOverride: branchLabel,
                    detail: .selectedFile(relativePath: relativePath)
                )

                if let fileResult = try selectedFileResult(
                    in: scopedDiff.diff,
                    context: context,
                    relativePath: relativePath,
                    forceLargeDiff: forceLargeDiff
                ) {
                    return fileResult
                }

                let fallbackDiff = try loadScopedDiff(
                    context: context,
                    scope: scope,
                    branchLabelOverride: branchLabel,
                    detail: .full
                )

                guard let fallbackResult = try selectedFileResult(
                    in: fallbackDiff.diff,
                    context: context,
                    relativePath: relativePath,
                    forceLargeDiff: forceLargeDiff
                ) else {
                    return .unavailable(message: "The selected file is no longer part of the current change set.")
                }

                return fallbackResult
            }
        } catch let error as GitError where error.knownCode == .notFound {
            return .unavailable(message: "Git changes are unavailable because this directory is not a Git repository.")
        } catch {
            return .unavailable(message: "The diff for this file could not be loaded.")
        }
    }

    public static func loadSnapshot(
        rootPath: String,
        scope: GitDiffScope
    ) -> LineBasedDiffSnapshot {
        do {
            let context = try repositoryContext(rootPath: rootPath)
            switch try catalogContext(context: context, scope: scope) {
            case let .unavailable(message):
                return LineBasedDiffSnapshot(
                    files: [],
                    totalAddedLineCount: 0,
                    totalRemovedLineCount: 0,
                    issueMessage: message,
                    branchLabel: nil
                )
            case let .available(branchLabel):
                let scopedDiff = try loadScopedDiff(
                    context: context,
                    scope: scope,
                    branchLabelOverride: branchLabel,
                    detail: .full
                )
                let entries = makeCatalogEntries(from: scopedDiff.diff, context: context)
                let stats = try scopedDiff.diff.stats()

                if entries.count > maximumRenderableChangeCount {
                    return LineBasedDiffSnapshot(
                        files: [],
                        totalAddedLineCount: stats.insertions,
                        totalRemovedLineCount: stats.deletions,
                        issueMessage: oversizedSnapshotIssueMessage(changedFileCount: entries.count),
                        branchLabel: scopedDiff.branchLabel
                    )
                }

                let files = (0..<scopedDiff.diff.deltaCount).compactMap { index in
                    do {
                        let patch = try scopedDiff.diff.structuredPatch(at: index)
                        return snapshotFile(from: patch, context: context)
                    } catch {
                        return nil
                    }
                }

                return LineBasedDiffSnapshot(
                    files: files,
                    totalAddedLineCount: stats.insertions,
                    totalRemovedLineCount: stats.deletions,
                    issueMessage: nil,
                    branchLabel: scopedDiff.branchLabel
                )
            }
        } catch {
            return LineBasedDiffSnapshot(
                files: [],
                totalAddedLineCount: 0,
                totalRemovedLineCount: 0,
                issueMessage: "Git changes are unavailable because this directory is not a Git repository.",
                branchLabel: nil
            )
        }
    }

    package static func oversizedSnapshotIssueMessage(changedFileCount: Int) -> String {
        "This scope has \(changedFileCount) changed files. Reduce generated build output or narrow the change set to inspect diffs."
    }

    private static func repositoryContext(rootPath: String) throws -> RepositoryContext {
        let normalizedRoot = normalizedPath(rootPath)
        let discoveredPath = try Git.discoverRepository(startingAt: normalizedRoot)
        let repository = try Git.open(discoveredPath)

        guard let workingDirectoryPath = repository.workingDirectoryPath else {
            throw LoaderError.bareRepository
        }

        let repositoryRootPath = normalizedPath(workingDirectoryPath)
        let relativeBasePath: String?
        if normalizedRoot == repositoryRootPath {
            relativeBasePath = nil
        } else if normalizedRoot.hasPrefix(repositoryRootPath + "/") {
            relativeBasePath = String(normalizedRoot.dropFirst(repositoryRootPath.count + 1))
        } else {
            relativeBasePath = nil
        }

        return RepositoryContext(
            repository: repository,
            rootPath: normalizedRoot,
            repositoryRootPath: repositoryRootPath,
            relativeBasePath: relativeBasePath
        )
    }

    private static func catalogContext(
        context: RepositoryContext,
        scope: GitDiffScope
    ) throws -> CatalogContext {
        switch scope {
        case .unstaged, .staged:
            return .available(branchLabel: nil)
        case .branch:
            guard let branchInfo = try branchComparisonInfo(repository: context.repository) else {
                return .unavailable(
                    message: "Branch comparison is unavailable because this branch does not track an upstream branch."
                )
            }
            return .available(branchLabel: branchInfo.label)
        }
    }

    private static func loadScopedDiff(
        context: RepositoryContext,
        scope: GitDiffScope,
        branchLabelOverride: String?,
        detail: DiffLoadDetail
    ) throws -> ScopedDiff {
        switch scope {
        case .unstaged:
            let diff = try context.repository.diffIndexToWorkingDirectory(
                options: diffOptions(
                    context: context,
                    includeUntracked: true,
                    showUntrackedContent: detail.requiresFullUntrackedContent,
                    additionalPathspecs: detail.pathspecs(context: context)
                )
            )
            try finalizeScopedDiff(diff)
            return ScopedDiff(diff: diff, branchLabel: nil)
        case .staged:
            let diff = try context.repository.diffTreeToIndex(
                from: try headTreeIfAvailable(repository: context.repository),
                options: diffOptions(
                    context: context,
                    additionalPathspecs: detail.pathspecs(context: context)
                )
            )
            try finalizeScopedDiff(diff)
            return ScopedDiff(diff: diff, branchLabel: nil)
        case .branch:
            guard let branchInfo = try branchComparisonInfo(repository: context.repository) else {
                throw LoaderError.missingUpstream
            }

            let mergeBase = try context.repository.mergeBase(
                between: branchInfo.headCommit.id,
                and: branchInfo.upstreamCommit.id
            )
            let diff = try context.repository.diff(
                between: try context.repository.commit(mergeBase).tree(),
                and: try branchInfo.headCommit.tree(),
                options: diffOptions(
                    context: context,
                    additionalPathspecs: detail.pathspecs(context: context)
                )
            )
            try finalizeScopedDiff(diff)
            return ScopedDiff(diff: diff, branchLabel: branchLabelOverride ?? branchInfo.label)
        }
    }

    private static func makeCatalogEntries(
        from diff: SwiftGit.Diff,
        context: RepositoryContext
    ) -> [GitDiffCatalogEntry] {
        diff.deltas()
            .compactMap { delta in
                guard
                    let status = changeKind(for: delta.kind),
                    let relativePath = projectedPath(for: delta.path, context: context)
                else {
                    return nil
                }

                let originalRelativePath: String?
                switch delta.kind {
                case .renamed, .copied:
                    originalRelativePath = projectedPath(for: delta.oldFile.path, context: context)
                default:
                    originalRelativePath = nil
                }

                return GitDiffCatalogEntry(
                    id: relativePath,
                    status: status,
                    relativePath: relativePath,
                    originalRelativePath: originalRelativePath
                )
            }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private static func fileLoadResult(
        diff: SwiftGit.Diff,
        patchMetadata: DiffPatchMetadata,
        context: RepositoryContext,
        forceLargeDiff: Bool
    ) -> GitDiffFileLoadResult {
        guard let relativePath = projectedPath(for: patchMetadata.delta.path, context: context) else {
            return .unavailable(message: "The selected file is no longer part of the current change set.")
        }

        let isLargePatch = patchIsTooLarge(patchMetadata)
        let prefersPlainTextPreview = estimatedStructuredDisplayRowCount(for: patchMetadata) >= LineBasedDiffFile.maximumStructuredPreviewRowCount
        if forceLargeDiff == false, isLargePatch {
            return .tooLarge(message: fileTooLargeMessage(relativePath: relativePath))
        }

        if isLargePatch || prefersPlainTextPreview {
            if patchMetadata.byteCount > maximumInlinePreviewBytes {
                return .diff(
                    makeOversizedPreviewSummaryFile(
                        relativePath: relativePath,
                        patchMetadata: patchMetadata
                    )
                )
            }

            do {
                let rawPatch = try diff.patchText(at: patchMetadata.index)
                guard patchTextIsBinary(rawPatch) == false else {
                    return .unavailable(message: "No textual diff is available for this file.")
                }
                return .diff(
                    makeLargePreviewDiffFile(
                        relativePath: relativePath,
                        patchMetadata: patchMetadata,
                        rawPatch: rawPatch
                    )
                )
            } catch {
                return .unavailable(message: "The diff for this file could not be loaded.")
            }
        }

        do {
            let patch = try diff.structuredPatch(at: patchMetadata.index)
            guard patch.isBinary == false else {
                return .unavailable(message: "No textual diff is available for this file.")
            }

            let file = makeLineBasedDiffFile(from: patch, relativePath: relativePath)
            guard file.hunks.isEmpty == false else {
                return .unavailable(message: "No textual diff is available for this file.")
            }

            return .diff(file)
        } catch {
            return .unavailable(message: "The diff for this file could not be loaded.")
        }
    }

    private static func selectedFileResult(
        in diff: SwiftGit.Diff,
        context: RepositoryContext,
        relativePath: String,
        forceLargeDiff: Bool
    ) throws -> GitDiffFileLoadResult? {
        guard let patchMetadata = try diff.firstPatchMetadata(where: {
            projectedPath(for: $0.path, context: context) == relativePath
        }) else {
            return nil
        }

        return fileLoadResult(
            diff: diff,
            patchMetadata: patchMetadata,
            context: context,
            forceLargeDiff: forceLargeDiff
        )
    }

    private static func snapshotFile(
        from patch: DiffPatch,
        context: RepositoryContext
    ) -> LineBasedDiffFile? {
        guard
            let relativePath = projectedPath(for: patch.delta.path, context: context),
            patch.isBinary == false
        else {
            return nil
        }

        let file = makeLineBasedDiffFile(from: patch, relativePath: relativePath)
        return file.hunks.isEmpty ? nil : file
    }

    private static func makeLineBasedDiffFile(
        from patch: DiffPatch,
        relativePath: String
    ) -> LineBasedDiffFile {
        let hunks = patch.hunks.enumerated().map { hunkOffset, hunk in
            LineBasedDiffHunk(
                id: "\(relativePath):\(hunkOffset)",
                header: hunk.header,
                oldStart: hunk.oldStart,
                oldCount: hunk.oldLineCount,
                newStart: hunk.newStart,
                newCount: hunk.newLineCount,
                lines: hunk.lines.map(makeLineBasedDiffLine)
            )
        }

        return LineBasedDiffFile(
            id: relativePath,
            relativePath: relativePath,
            addedLineCount: patch.addedLineCount,
            removedLineCount: patch.removedLineCount,
            hunks: hunks,
            rawPatch: "",
            isUntracked: patch.delta.kind == .untracked
        )
    }

    private static func makeOversizedPreviewSummaryFile(
        relativePath: String,
        patchMetadata: DiffPatchMetadata
    ) -> LineBasedDiffFile {
        let isUntracked = patchMetadata.delta.kind == .untracked
        let previewText = oversizedPreviewSummaryText(
            relativePath: relativePath,
            patchMetadata: patchMetadata
        )

        return LineBasedDiffFile(
            id: relativePath,
            relativePath: relativePath,
            addedLineCount: patchMetadata.addedLineCount,
            removedLineCount: patchMetadata.removedLineCount,
            hunks: [],
            rawPatch: previewText,
            isUntracked: isUntracked
        )
    }

    private static func makeLargePreviewDiffFile(
        relativePath: String,
        patchMetadata: DiffPatchMetadata,
        rawPatch: String
    ) -> LineBasedDiffFile {
        let isUntracked = patchMetadata.delta.kind == .untracked
        return LineBasedDiffFile(
            id: relativePath,
            relativePath: relativePath,
            addedLineCount: patchMetadata.addedLineCount,
            removedLineCount: patchMetadata.removedLineCount,
            hunks: [],
            rawPatch: rawPatch,
            isUntracked: isUntracked
        )
    }

    private static func makeLineBasedDiffLine(_ line: DiffPatchLine) -> LineBasedDiffLine {
        switch line.origin {
        case .addition?:
            return LineBasedDiffLine(
                kind: .addition,
                text: line.text,
                oldLineNumber: nil,
                newLineNumber: line.newLineNumber
            )
        case .deletion?:
            return LineBasedDiffLine(
                kind: .deletion,
                text: line.text,
                oldLineNumber: line.oldLineNumber,
                newLineNumber: nil
            )
        case .context?:
            return LineBasedDiffLine(
                kind: .context,
                text: line.text,
                oldLineNumber: line.oldLineNumber,
                newLineNumber: line.newLineNumber
            )
        default:
            return LineBasedDiffLine(
                kind: .note,
                text: line.text,
                oldLineNumber: nil,
                newLineNumber: nil
            )
        }
    }

    private static func patchIsTooLarge(_ patchMetadata: DiffPatchMetadata) -> Bool {
        if max(patchMetadata.delta.oldFile.size, patchMetadata.delta.newFile.size) > maximumFileBytes {
            return true
        }

        return patchMetadata.byteCount > maximumFileBytes
    }

    private static func fileTooLargeMessage(relativePath: String) -> String {
        "\(relativePath) is too large to display by default."
    }

    private static func oversizedPreviewSummaryText(
        relativePath: String,
        patchMetadata: DiffPatchMetadata
    ) -> String {
        let byteCount = ByteCountFormatter.string(
            fromByteCount: Int64(patchMetadata.byteCount),
            countStyle: .file
        )

        return """
        Diff preview omitted.

        \(relativePath)
        Patch size: \(byteCount)
        Added lines: \(patchMetadata.addedLineCount)
        Removed lines: \(patchMetadata.removedLineCount)

        The patch exceeds Nea's inline preview limit, so the app is showing a summary instead of materializing the full diff text.
        """
    }

    private static func patchTextIsBinary(_ text: String) -> Bool {
        text.contains("Binary files ") || text.contains("GIT binary patch")
    }

    private static func estimatedStructuredDisplayRowCount(
        for patchMetadata: DiffPatchMetadata
    ) -> Int {
        patchMetadata.contextLineCount + patchMetadata.addedLineCount + patchMetadata.removedLineCount
    }

    private static func projectedPath(
        for repositoryRelativePath: String?,
        context: RepositoryContext
    ) -> String? {
        guard let repositoryRelativePath else {
            return nil
        }

        guard let relativeBasePath = context.relativeBasePath else {
            return repositoryRelativePath
        }

        let prefix = relativeBasePath + "/"
        guard repositoryRelativePath.hasPrefix(prefix) else {
            return nil
        }

        return String(repositoryRelativePath.dropFirst(prefix.count))
    }

    private static func diffOptions(
        context: RepositoryContext,
        includeUntracked: Bool = false,
        showUntrackedContent: Bool? = nil,
        additionalPathspecs: [String]? = nil
    ) -> DiffOptions {
        let pathspecs = additionalPathspecs ?? context.relativeBasePath.map { [$0] } ?? []
        return DiffOptions(
            contextLines: 3,
            includeUntracked: includeUntracked,
            recurseUntrackedDirectories: includeUntracked,
            showUntrackedContent: showUntrackedContent ?? includeUntracked,
            pathspecs: pathspecs
        )
    }

    private static func finalizeScopedDiff(_ diff: SwiftGit.Diff) throws {
        guard diff.deltaCount <= maximumSimilarityDetectionDeltaCount else {
            return
        }

        try diff.findSimilar()
    }

    private static func repositoryRelativePath(
        for projectedRelativePath: String,
        context: RepositoryContext
    ) -> String {
        if let relativeBasePath = context.relativeBasePath {
            return relativeBasePath + "/" + projectedRelativePath
        }

        return projectedRelativePath
    }

    private static func headTreeIfAvailable(repository: Repository) throws -> Tree? {
        do {
            return try repository.headCommit().tree()
        } catch let error as GitError where error.knownCode == .unbornBranch || error.knownCode == .notFound {
            return nil
        }
    }

    private static func branchComparisonInfo(
        repository: Repository
    ) throws -> (label: String, headCommit: Commit, upstreamCommit: Commit)? {
        let headReference = try repository.headReference()
        guard headReference.isBranch else {
            return nil
        }

        let branch = try repository.branch(named: headReference.shorthand)
        guard let upstreamBranch = try branch.upstream() else {
            return nil
        }
        guard let upstreamTarget = upstreamBranch.target else {
            return nil
        }

        return (
            label: "\(branch.name) -> \(upstreamBranch.name)",
            headCommit: try repository.headCommit(),
            upstreamCommit: try repository.commit(upstreamTarget)
        )
    }

    private static func changeKind(for status: DiffDeltaStatus) -> GitDiffChangeKind? {
        switch status {
        case .added:
            return .added
        case .deleted:
            return .deleted
        case .modified:
            return .modified
        case .renamed:
            return .renamed
        case .copied:
            return .copied
        case .untracked:
            return .untracked
        case .typeChanged:
            return .typeChanged
        case .conflicted:
            return .unmerged
        case .ignored, .unmodified, .unreadable:
            return nil
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
