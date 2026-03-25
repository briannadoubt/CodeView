import DiffCore
import DiffRendering
import Foundation
import SyntaxCore

public struct LineBasedDiffLine: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case context
        case addition
        case deletion
        case note
    }

    public var kind: Kind
    public var text: String
    public var oldLineNumber: Int?
    public var newLineNumber: Int?

    public init(
        kind: Kind,
        text: String,
        oldLineNumber: Int?,
        newLineNumber: Int?
    ) {
        self.kind = kind
        self.text = text
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
    }
}

public struct LineBasedDiffHunk: Identifiable, Hashable, Sendable {
    public let id: String
    public var header: String
    public var oldStart: Int
    public var oldCount: Int
    public var newStart: Int
    public var newCount: Int
    public var lines: [LineBasedDiffLine]

    public init(
        id: String,
        header: String,
        oldStart: Int,
        oldCount: Int,
        newStart: Int,
        newCount: Int,
        lines: [LineBasedDiffLine]
    ) {
        self.id = id
        self.header = header
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
    }
}

public struct LineBasedDiffFile: Identifiable, Hashable, Sendable {
    public static let maximumStructuredPreviewRowCount = 8_000

    public let id: String
    public var relativePath: String
    public var addedLineCount: Int
    public var removedLineCount: Int
    public var hunks: [LineBasedDiffHunk]
    public var rawPatch: String
    public var isUntracked: Bool
    public var contentSignature: Int

    public init(
        id: String,
        relativePath: String,
        addedLineCount: Int = 0,
        removedLineCount: Int = 0,
        hunks: [LineBasedDiffHunk],
        rawPatch: String = "",
        isUntracked: Bool = false,
        contentSignature: Int? = nil
    ) {
        self.id = id
        self.relativePath = relativePath
        self.addedLineCount = addedLineCount
        self.removedLineCount = removedLineCount
        self.hunks = hunks
        self.rawPatch = rawPatch
        self.isUntracked = isUntracked
        self.contentSignature = contentSignature ?? Self.makeContentSignature(
            relativePath: relativePath,
            addedLineCount: addedLineCount,
            removedLineCount: removedLineCount,
            hunks: hunks,
            rawPatch: rawPatch,
            isUntracked: isUntracked
        )
    }

    public var flattenedText: String {
        hunks
            .flatMap(\.lines)
            .map(\.text)
            .joined(separator: "\n")
    }

    public var totalDisplayRowCount: Int {
        hunks.reduce(0) { partial, hunk in
            partial + hunk.lines.count + 1
        }
    }

    public var usesRawTextPreview: Bool {
        hunks.isEmpty && rawPatch.isEmpty == false
    }

    public var prefersPlainTextPreview: Bool {
        usesRawTextPreview || totalDisplayRowCount > Self.maximumStructuredPreviewRowCount
    }

    public var plainTextPreviewText: String {
        if rawPatch.isEmpty == false {
            return rawPatch
        }

        guard hunks.isEmpty == false else {
            return ""
        }

        var previewLines: [String] = []
        previewLines.reserveCapacity(totalDisplayRowCount)

        for hunk in hunks {
            previewLines.append(hunk.header)
            for line in hunk.lines {
                previewLines.append(Self.previewText(for: line))
            }
        }

        return previewLines.joined(separator: "\n")
    }

    private static func makeContentSignature(
        relativePath: String,
        addedLineCount: Int,
        removedLineCount: Int,
        hunks: [LineBasedDiffHunk],
        rawPatch: String,
        isUntracked: Bool
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(relativePath)
        hasher.combine(addedLineCount)
        hasher.combine(removedLineCount)
        hasher.combine(isUntracked)

        if rawPatch.isEmpty == false {
            hasher.combine(rawPatch)
        }

        for hunk in hunks {
            hasher.combine(hunk.id)
            hasher.combine(hunk.header)
            hasher.combine(hunk.oldStart)
            hasher.combine(hunk.oldCount)
            hasher.combine(hunk.newStart)
            hasher.combine(hunk.newCount)
            for line in hunk.lines {
                hasher.combine(line.kind)
                hasher.combine(line.text)
                hasher.combine(line.oldLineNumber)
                hasher.combine(line.newLineNumber)
            }
        }

        return hasher.finalize()
    }

    private static func previewText(for line: LineBasedDiffLine) -> String {
        switch line.kind {
        case .context:
            return " \(line.text)"
        case .addition:
            return "+\(line.text)"
        case .deletion:
            return "-\(line.text)"
        case .note:
            return line.text
        }
    }
}

public struct LineBasedDiffSnapshot: Hashable, Sendable {
    public var files: [LineBasedDiffFile]
    public var totalAddedLineCount: Int
    public var totalRemovedLineCount: Int
    public var issueMessage: String?
    public var branchLabel: String?

    public init(
        files: [LineBasedDiffFile],
        totalAddedLineCount: Int = 0,
        totalRemovedLineCount: Int = 0,
        issueMessage: String? = nil,
        branchLabel: String? = nil
    ) {
        self.files = files
        self.totalAddedLineCount = totalAddedLineCount
        self.totalRemovedLineCount = totalRemovedLineCount
        self.issueMessage = issueMessage
        self.branchLabel = branchLabel
    }
}

public enum LineBasedDiffAdapter {
    public static func makeDiffFiles(
        from files: [LineBasedDiffFile],
        collapsedFileIDs: Set<DiffFile.ID> = []
    ) -> [DiffFile] {
        files.map { file in
            DiffFile(
                id: file.id,
                path: file.relativePath,
                hunks: file.hunks.enumerated().map { hunkOffset, hunk in
                    DiffHunk(
                        id: hunk.id,
                        header: hunk.header,
                        lines: hunk.lines.enumerated().map { lineOffset, line in
                            DiffLine(
                                id: "\(file.id)-\(hunk.id)-line-\(lineOffset)",
                                kind: DiffLine.Kind(line.kind),
                                oldLineNumber: line.oldLineNumber,
                                newLineNumber: line.newLineNumber,
                                text: line.text
                            )
                        }
                    )
                },
                isCollapsed: collapsedFileIDs.contains(file.id)
            )
        }
    }

    public static func makeDiffFiles(
        from snapshot: LineBasedDiffSnapshot,
        collapsedFileIDs: Set<DiffFile.ID> = []
    ) -> [DiffFile] {
        makeDiffFiles(from: snapshot.files, collapsedFileIDs: collapsedFileIDs)
    }

    public static func makeRenderableDiffFiles(
        from files: [LineBasedDiffFile],
        fileContentsByFileID: [DiffFile.ID: String] = [:],
        collapsedFileIDs: Set<DiffFile.ID> = []
    ) -> [DiffFile] {
        files.map { file in
            let contents = fileContentsByFileID[file.id] ?? file.flattenedText
            return makeRenderableDiffFile(
                from: file,
                fileContents: contents,
                isCollapsed: collapsedFileIDs.contains(file.id)
            )
        }
    }

    public static func makeRenderableDiffFiles(
        from snapshot: LineBasedDiffSnapshot,
        fileContentsByFileID: [DiffFile.ID: String] = [:],
        collapsedFileIDs: Set<DiffFile.ID> = []
    ) -> [DiffFile] {
        makeRenderableDiffFiles(
            from: snapshot.files,
            fileContentsByFileID: fileContentsByFileID,
            collapsedFileIDs: collapsedFileIDs
        )
    }

    public static func makeFileTree(from files: [LineBasedDiffFile]) -> [FileTreeNode] {
        let root = MutableTreeNode(id: "", name: "", kind: .directory)

        for file in files.sorted(by: { $0.relativePath < $1.relativePath }) {
            let components = normalizedComponents(for: file.relativePath)
            guard let leafName = components.last else { continue }

            var cursor = root
            var partialPath: [String] = []

            for directoryName in components.dropLast() {
                partialPath.append(directoryName)
                let pathID = partialPath.joined(separator: "/")
                if let existing = cursor.children[directoryName] {
                    cursor = existing
                } else {
                    let directory = MutableTreeNode(
                        id: pathID,
                        name: directoryName,
                        kind: .directory
                    )
                    cursor.children[directoryName] = directory
                    cursor = directory
                }
            }

            partialPath.append(leafName)
            cursor.children[leafName] = MutableTreeNode(
                id: partialPath.joined(separator: "/"),
                name: leafName,
                kind: .file,
                fileID: file.id
            )
        }

        return root.makeChildren()
    }

    public static func makeFileTree(from snapshot: LineBasedDiffSnapshot) -> [FileTreeNode] {
        makeFileTree(from: snapshot.files)
    }

    public static func makeSurfaceModelRequest(
        from files: [LineBasedDiffFile],
        fileContentsByFileID: [DiffFile.ID: String] = [:],
        displayMode: DiffViewMode,
        wrapsLines: Bool,
        collapsedFileIDs: Set<DiffFile.ID> = [],
        expandedBlockIDs: Set<String> = [],
        flatteningConfiguration: DiffFlatteningConfiguration = .init(),
        syntaxConfiguration: SyntaxConfiguration = .default
    ) -> DiffSurfaceModelRequest {
        let diffFiles = makeRenderableDiffFiles(
            from: files,
            fileContentsByFileID: fileContentsByFileID,
            collapsedFileIDs: collapsedFileIDs
        )
        let fallbackContents = Dictionary(uniqueKeysWithValues: files.map { file in
            (file.id, fileContentsByFileID[file.id] ?? file.flattenedText)
        })

        return DiffSurfaceModelRequest(
            files: diffFiles,
            fileContents: fallbackContents,
            displayMode: displayMode,
            wrapsLines: wrapsLines,
            expandedBlockIDs: expandedBlockIDs,
            flatteningConfiguration: flatteningConfiguration,
            syntaxConfiguration: syntaxConfiguration
        )
    }

    public static func makeSurfaceModelRequest(
        from snapshot: LineBasedDiffSnapshot,
        fileContentsByFileID: [DiffFile.ID: String] = [:],
        displayMode: DiffViewMode,
        wrapsLines: Bool,
        collapsedFileIDs: Set<DiffFile.ID> = [],
        expandedBlockIDs: Set<String> = [],
        flatteningConfiguration: DiffFlatteningConfiguration = .init(),
        syntaxConfiguration: SyntaxConfiguration = .default
    ) -> DiffSurfaceModelRequest {
        makeSurfaceModelRequest(
            from: snapshot.files,
            fileContentsByFileID: fileContentsByFileID,
            displayMode: displayMode,
            wrapsLines: wrapsLines,
            collapsedFileIDs: collapsedFileIDs,
            expandedBlockIDs: expandedBlockIDs,
            flatteningConfiguration: flatteningConfiguration,
            syntaxConfiguration: syntaxConfiguration
        )
    }

    private static func normalizedComponents(for relativePath: String) -> [String] {
        relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private static func makeRenderableDiffFile(
        from file: LineBasedDiffFile,
        fileContents: String,
        isCollapsed: Bool
    ) -> DiffFile {
        DiffFile(
            id: file.id,
            path: file.relativePath,
            hunks: [
                DiffHunk(
                    id: "\(file.id)-merged",
                    header: file.hunks.first?.header ?? "@@",
                    lines: mergedLines(for: file, fileContents: fileContents)
                )
            ],
            isCollapsed: isCollapsed
        )
    }

    private static func mergedLines(
        for file: LineBasedDiffFile,
        fileContents: String
    ) -> [DiffLine] {
        let fileLines = fileContents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let oldFileLineCount = max(fileLines.count - file.addedLineCount + file.removedLineCount, 0)

        var mergedLines: [DiffLine] = []
        var nextOldLine = 1
        var nextNewLine = 1

        for hunk in file.hunks {
            mergedLines.append(contentsOf:
                contentsOfUnchangedRegion(
                    fileID: file.id,
                    fileLines: fileLines,
                    oldStart: nextOldLine,
                    oldEnd: hunk.oldStart,
                    newStart: nextNewLine,
                    newEnd: hunk.newStart
                )
            )
            mergedLines.append(contentsOf: hunk.renderableLines(fileID: file.id))

            nextOldLine = hunk.oldStart + hunk.oldCount
            nextNewLine = hunk.newStart + hunk.newCount
        }

        mergedLines.append(contentsOf:
            contentsOfUnchangedRegion(
                fileID: file.id,
                fileLines: fileLines,
                oldStart: nextOldLine,
                oldEnd: oldFileLineCount + 1,
                newStart: nextNewLine,
                newEnd: fileLines.count + 1
            )
        )

        return mergedLines
    }

    private static func contentsOfUnchangedRegion(
        fileID: String,
        fileLines: [String],
        oldStart: Int,
        oldEnd: Int,
        newStart: Int,
        newEnd: Int
    ) -> [DiffLine] {
        guard oldEnd > oldStart, newEnd > newStart else { return [] }

        let oldRange = oldStart..<oldEnd
        let newRange = newStart..<newEnd
        let count = min(oldRange.count, newRange.count)
        guard count > 0 else { return [] }

        return (0..<count).map { offset in
            let oldLineNumber = oldRange.lowerBound + offset
            let newLineNumber = newRange.lowerBound + offset
            let text = fileLines.indices.contains(newLineNumber - 1) ? fileLines[newLineNumber - 1] : ""
            return DiffLine(
                id: "\(fileID)-context-\(oldLineNumber)-\(newLineNumber)",
                kind: .context,
                oldLineNumber: oldLineNumber,
                newLineNumber: newLineNumber,
                text: text
            )
        }
    }
}

private final class MutableTreeNode {
    let id: String
    let name: String
    let kind: FileTreeNode.Kind
    let fileID: DiffFile.ID?
    var children: [String: MutableTreeNode]

    init(
        id: String,
        name: String,
        kind: FileTreeNode.Kind,
        fileID: DiffFile.ID? = nil,
        children: [String: MutableTreeNode] = [:]
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.fileID = fileID
        self.children = children
    }

    func makeChildren() -> [FileTreeNode] {
        children.values
            .sorted(by: Self.sort)
            .map { child in
                FileTreeNode(
                    id: child.id,
                    name: child.name,
                    kind: child.kind,
                    children: child.makeChildren(),
                    fileID: child.fileID
                )
            }
    }

    private static func sort(_ lhs: MutableTreeNode, _ rhs: MutableTreeNode) -> Bool {
        if lhs.kind != rhs.kind {
            return lhs.kind == .directory
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

private extension DiffLine.Kind {
    init(_ kind: LineBasedDiffLine.Kind) {
        switch kind {
        case .context:
            self = .context
        case .addition:
            self = .addition
        case .deletion:
            self = .deletion
        case .note:
            self = .note
        }
    }
}

private extension LineBasedDiffHunk {
    func renderableLines(fileID: String) -> [DiffLine] {
        lines.enumerated().map { index, line in
            DiffLine(
                id: "\(fileID)-\(id)-line-\(index)",
                kind: DiffLine.Kind(line.kind),
                oldLineNumber: line.oldLineNumber,
                newLineNumber: line.newLineNumber,
                text: line.text
            )
        }
    }
}
