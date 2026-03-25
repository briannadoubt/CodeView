import Foundation

public struct DiffFile: Identifiable, Hashable, Sendable {
    public typealias ID = String

    public let id: ID
    public var path: String
    public var hunks: [DiffHunk]
    public var isCollapsed: Bool

    public init(
        id: ID,
        path: String,
        hunks: [DiffHunk],
        isCollapsed: Bool = false
    ) {
        self.id = id
        self.path = path
        self.hunks = hunks
        self.isCollapsed = isCollapsed
    }

    public var flattenedText: String {
        hunks
            .flatMap(\.lines)
            .map(\.text)
            .joined(separator: "\n")
    }
}

public struct DiffHunk: Identifiable, Hashable, Sendable {
    public let id: String
    public var header: String
    public var lines: [DiffLine]

    public init(id: String, header: String, lines: [DiffLine]) {
        self.id = id
        self.header = header
        self.lines = lines
    }
}

public struct DiffLine: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case context
        case addition
        case deletion
        case note
    }

    public let id: String
    public var kind: Kind
    public var oldLineNumber: Int?
    public var newLineNumber: Int?
    public var text: String

    public init(
        id: String,
        kind: Kind,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        text: String
    ) {
        self.id = id
        self.kind = kind
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.text = text
    }
}

public struct FileTreeNode: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case directory
        case file
    }

    public let id: String
    public var name: String
    public var kind: Kind
    public var children: [FileTreeNode]
    public var fileID: DiffFile.ID?

    public init(
        id: String,
        name: String,
        kind: Kind,
        children: [FileTreeNode] = [],
        fileID: DiffFile.ID? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.children = children
        self.fileID = fileID
    }

    public var optionalChildren: [FileTreeNode]? {
        children.isEmpty ? nil : children
    }
}

public enum DiffViewMode: String, Hashable, Codable, Sendable {
    case unified
    case split
}

public enum HiddenContextRevealDirection: String, Hashable, Codable, Sendable {
    case up
    case down
    case middle
}

public struct HiddenContextExpansionState: Hashable, Codable, Sendable {
    public var revealedUpperLineCount: Int
    public var revealedLowerLineCount: Int

    public init(revealedUpperLineCount: Int = 0, revealedLowerLineCount: Int = 0) {
        self.revealedUpperLineCount = revealedUpperLineCount
        self.revealedLowerLineCount = revealedLowerLineCount
    }

    public func clamped(to hiddenLineCount: Int) -> HiddenContextExpansionState {
        let upper = max(0, min(revealedUpperLineCount, hiddenLineCount))
        let lower = max(0, min(revealedLowerLineCount, hiddenLineCount - upper))
        return HiddenContextExpansionState(revealedUpperLineCount: upper, revealedLowerLineCount: lower)
    }

    public func remainingRange(in originalRange: Range<Int>) -> Range<Int>? {
        let clampedState = clamped(to: originalRange.count)
        let start = originalRange.lowerBound + clampedState.revealedUpperLineCount
        let end = originalRange.upperBound - clampedState.revealedLowerLineCount
        guard start < end else { return nil }
        return start ..< end
    }

    public func applying(
        _ direction: HiddenContextRevealDirection,
        lineCount: Int,
        in originalRange: Range<Int>
    ) -> HiddenContextExpansionState {
        let clampedState = clamped(to: originalRange.count)
        let revealCount = max(0, lineCount)

        switch direction {
        case .up:
            let nextUpper = min(
                originalRange.count - clampedState.revealedLowerLineCount,
                clampedState.revealedUpperLineCount + revealCount
            )
            return HiddenContextExpansionState(
                revealedUpperLineCount: nextUpper,
                revealedLowerLineCount: clampedState.revealedLowerLineCount
            )
        case .down:
            let nextLower = min(
                originalRange.count - clampedState.revealedUpperLineCount,
                clampedState.revealedLowerLineCount + revealCount
            )
            return HiddenContextExpansionState(
                revealedUpperLineCount: clampedState.revealedUpperLineCount,
                revealedLowerLineCount: nextLower
            )
        case .middle:
            return clampedState
        }
    }
}

public struct HiddenContextBlock: Identifiable, Hashable, Sendable {
    public let id: String
    public let fileID: DiffFile.ID
    public let hunkID: DiffHunk.ID
    public let range: Range<Int>
    public let hiddenLineCount: Int

    public init(id: String, fileID: DiffFile.ID, hunkID: DiffHunk.ID, range: Range<Int>) {
        self.id = id
        self.fileID = fileID
        self.hunkID = hunkID
        self.range = range
        self.hiddenLineCount = range.count
    }
}

public struct VisibleDiffRow: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case fileHeader(path: String, isCollapsed: Bool)
        case hunkHeader(text: String)
        case line(DiffLine)
        case hiddenContext(HiddenContextBlock)
    }

    public let id: String
    public let fileID: DiffFile.ID
    public let hunkID: DiffHunk.ID?
    public let kind: Kind

    public init(id: String, fileID: DiffFile.ID, hunkID: DiffHunk.ID? = nil, kind: Kind) {
        self.id = id
        self.fileID = fileID
        self.hunkID = hunkID
        self.kind = kind
    }
}

public struct DiffFlatteningConfiguration: Hashable, Sendable {
    public var visibleContextRadius: Int
    public var expansionChunkSize: Int

    public init(visibleContextRadius: Int = 3, expansionChunkSize: Int = 20) {
        self.visibleContextRadius = visibleContextRadius
        self.expansionChunkSize = expansionChunkSize
    }
}

public enum DiffCoreEngine {
    public static func makeVisibleRows(
        files: [DiffFile],
        fullyExpandedBlockIDs: Set<String> = [],
        partiallyExpandedBlocks: [String: HiddenContextExpansionState] = [:],
        configuration: DiffFlatteningConfiguration = .init()
    ) -> [VisibleDiffRow] {
        files.flatMap { file in
            rows(
                for: file,
                fullyExpandedBlockIDs: fullyExpandedBlockIDs,
                partiallyExpandedBlocks: partiallyExpandedBlocks,
                configuration: configuration
            )
        }
    }

    public static func rows(
        for file: DiffFile,
        fullyExpandedBlockIDs: Set<String> = [],
        partiallyExpandedBlocks: [String: HiddenContextExpansionState] = [:],
        configuration: DiffFlatteningConfiguration = .init()
    ) -> [VisibleDiffRow] {
        var rows: [VisibleDiffRow] = [
            VisibleDiffRow(
                id: "\(file.id)-header",
                fileID: file.id,
                kind: .fileHeader(path: file.path, isCollapsed: file.isCollapsed)
            )
        ]

        guard file.isCollapsed == false else {
            return rows
        }

        for hunk in file.hunks {
            rows.append(
                VisibleDiffRow(
                    id: "\(file.id)-\(hunk.id)-header",
                    fileID: file.id,
                    hunkID: hunk.id,
                    kind: .hunkHeader(text: hunk.header)
                )
            )

            rows.append(contentsOf:
                contentsRows(
                    fileID: file.id,
                    hunk: hunk,
                    fullyExpandedBlockIDs: fullyExpandedBlockIDs,
                    partiallyExpandedBlocks: partiallyExpandedBlocks,
                    configuration: configuration
                )
            )
        }

        return rows
    }

    public static func expand(
        block: HiddenContextBlock,
        in hunk: DiffHunk,
        direction: HiddenContextRevealDirection,
        configuration: DiffFlatteningConfiguration = .init()
    ) -> Range<Int>? {
        guard block.range.lowerBound >= 0, block.range.upperBound <= hunk.lines.count else {
            return nil
        }

        let chunk = min(configuration.expansionChunkSize, block.range.count)
        switch direction {
        case .up:
            return block.range.lowerBound ..< (block.range.lowerBound + chunk)
        case .down:
            return max(block.range.upperBound - chunk, block.range.lowerBound) ..< block.range.upperBound
        case .middle:
            let upperCount = chunk / 2
            let lowerCount = chunk - upperCount
            let start = block.range.lowerBound + max((block.range.count / 2) - upperCount, 0)
            let end = min(start + lowerCount + upperCount, block.range.upperBound)
            return start ..< end
        }
    }

    private static func contentsRows(
        fileID: DiffFile.ID,
        hunk: DiffHunk,
        fullyExpandedBlockIDs: Set<String>,
        partiallyExpandedBlocks: [String: HiddenContextExpansionState],
        configuration: DiffFlatteningConfiguration
    ) -> [VisibleDiffRow] {
        let hiddenRanges = hiddenContextRanges(
            in: hunk.lines,
            visibleContextRadius: configuration.visibleContextRadius
        )

        var rows: [VisibleDiffRow] = []
        var lineIndex = 0

        for hiddenRange in hiddenRanges {
            while lineIndex < hiddenRange.lowerBound {
                let line = hunk.lines[lineIndex]
                rows.append(
                    VisibleDiffRow(
                        id: line.id,
                        fileID: fileID,
                        hunkID: hunk.id,
                        kind: .line(line)
                    )
                )
                lineIndex += 1
            }

            let blockID = "\(fileID)-\(hunk.id)-hidden-\(hiddenRange.lowerBound)-\(hiddenRange.upperBound)"
            if fullyExpandedBlockIDs.contains(blockID) {
                for hiddenIndex in hiddenRange {
                    let line = hunk.lines[hiddenIndex]
                    rows.append(
                        VisibleDiffRow(
                            id: line.id,
                            fileID: fileID,
                            hunkID: hunk.id,
                            kind: .line(line)
                        )
                    )
                }
            } else {
                let expansionState = partiallyExpandedBlocks[blockID]?.clamped(to: hiddenRange.count) ?? .init()
                let remainingRange = expansionState.remainingRange(in: hiddenRange)
                let revealedUpperEnd = remainingRange?.lowerBound ?? hiddenRange.upperBound

                if lineIndex < revealedUpperEnd {
                    for revealedIndex in lineIndex ..< revealedUpperEnd {
                        let line = hunk.lines[revealedIndex]
                        rows.append(
                            VisibleDiffRow(
                                id: line.id,
                                fileID: fileID,
                                hunkID: hunk.id,
                                kind: .line(line)
                            )
                        )
                    }
                }

                if let remainingRange {
                    let block = HiddenContextBlock(
                        id: blockID,
                        fileID: fileID,
                        hunkID: hunk.id,
                        range: remainingRange
                    )
                    rows.append(
                        VisibleDiffRow(
                            id: block.id,
                            fileID: fileID,
                            hunkID: hunk.id,
                            kind: .hiddenContext(block)
                        )
                    )
                }

                let revealedLowerStart = remainingRange?.upperBound ?? hiddenRange.upperBound
                if revealedLowerStart < hiddenRange.upperBound {
                    for revealedIndex in revealedLowerStart ..< hiddenRange.upperBound {
                        let line = hunk.lines[revealedIndex]
                        rows.append(
                            VisibleDiffRow(
                                id: line.id,
                                fileID: fileID,
                                hunkID: hunk.id,
                                kind: .line(line)
                            )
                        )
                    }
                }

            }
            lineIndex = hiddenRange.upperBound
        }

        while lineIndex < hunk.lines.count {
            let line = hunk.lines[lineIndex]
            rows.append(
                VisibleDiffRow(
                    id: line.id,
                    fileID: fileID,
                    hunkID: hunk.id,
                    kind: .line(line)
                )
            )
            lineIndex += 1
        }

        return rows
    }

    static func hiddenContextRanges(
        in lines: [DiffLine],
        visibleContextRadius: Int
    ) -> [Range<Int>] {
        guard visibleContextRadius >= 0 else { return [] }

        var ranges: [Range<Int>] = []
        var index = 0

        while index < lines.count {
            guard lines[index].kind == .context else {
                index += 1
                continue
            }

            let start = index
            while index < lines.count, lines[index].kind == .context {
                index += 1
            }
            let end = index
            let contextCount = end - start
            let hiddenCount = contextCount - (visibleContextRadius * 2)

            guard hiddenCount > 0 else {
                continue
            }

            let hiddenStart = start + visibleContextRadius
            let hiddenEnd = end - visibleContextRadius
            ranges.append(hiddenStart ..< hiddenEnd)
        }

        return ranges
    }
}
