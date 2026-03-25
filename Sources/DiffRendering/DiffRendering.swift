import DiffCore
import Foundation
import SyntaxCore

public enum DiffBackgroundStyle: String, Hashable, Codable, Sendable {
    case neutral
    case addition
    case deletion
    case hidden
}

public enum HiddenContextAction: String, Hashable, Codable, Sendable {
    case expandUp
    case expandAll
    case expandDown
}

public struct HiddenContextControl: Hashable, Codable, Sendable {
    public let title: String
    public let action: HiddenContextAction

    public init(title: String, action: HiddenContextAction) {
        self.title = title
        self.action = action
    }
}

public struct DiffRenderableRow: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case code
        case hiddenContext(HiddenContextBlock)
    }

    public let id: String
    public let fileID: DiffFile.ID
    public let text: String
    public let oldLineNumber: Int?
    public let newLineNumber: Int?
    public let backgroundStyle: DiffBackgroundStyle
    public let syntaxSpans: [SyntaxSpan]
    public let hiddenContextControls: [HiddenContextControl]
    public let kind: Kind

    public init(
        id: String,
        fileID: DiffFile.ID,
        text: String,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        backgroundStyle: DiffBackgroundStyle,
        syntaxSpans: [SyntaxSpan],
        hiddenContextControls: [HiddenContextControl] = [],
        kind: Kind
    ) {
        self.id = id
        self.fileID = fileID
        self.text = text
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.backgroundStyle = backgroundStyle
        self.syntaxSpans = syntaxSpans
        self.hiddenContextControls = hiddenContextControls
        self.kind = kind
    }

    public var hiddenContextBlock: HiddenContextBlock? {
        guard case let .hiddenContext(block) = kind else { return nil }
        return block
    }

    public var isInlineHiddenContextControl: Bool {
        hiddenContextBlock != nil
    }
}

public struct DiffRenderableBlock: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case header(String)
        case textSurface
    }

    public let id: String
    public let fileID: DiffFile.ID
    public let kind: Kind

    public init(id: String, fileID: DiffFile.ID, kind: Kind) {
        self.id = id
        self.fileID = fileID
        self.kind = kind
    }
}

public struct CodeTextSurfaceModel: Identifiable, Hashable, Sendable {
    public enum Side: String, Hashable, Codable, Sendable {
        case unified
        case left
        case right
    }

    public let id: String
    public let fileID: DiffFile.ID
    public let side: Side
    public let rows: [DiffRenderableRow]
    public let wrapsLines: Bool
    public let horizontalScrollGroupID: String

    public init(
        id: String,
        fileID: DiffFile.ID,
        side: Side,
        rows: [DiffRenderableRow],
        wrapsLines: Bool,
        horizontalScrollGroupID: String
    ) {
        self.id = id
        self.fileID = fileID
        self.side = side
        self.rows = rows
        self.wrapsLines = wrapsLines
        self.horizontalScrollGroupID = horizontalScrollGroupID
    }

    public var hiddenContextRows: [DiffRenderableRow] {
        rows.filter(\.isInlineHiddenContextControl)
    }

    public var selectableCodeRows: [DiffRenderableRow] {
        rows.filter { $0.hiddenContextBlock == nil }
    }
}

public struct DiffRenderOutput: Hashable, Sendable {
    public var blocks: [DiffRenderableBlock]
    public var surfaces: [CodeTextSurfaceModel]

    public init(blocks: [DiffRenderableBlock], surfaces: [CodeTextSurfaceModel]) {
        self.blocks = blocks
        self.surfaces = surfaces
    }
}

public struct DiffSurfaceModelRequest: Sendable {
    public var files: [DiffFile]
    public var fileContents: [DiffFile.ID: String]
    public var displayMode: DiffViewMode
    public var wrapsLines: Bool
    public var expandedBlockIDs: Set<String>
    public var hiddenContextExpansionStates: [String: HiddenContextExpansionState]
    public var flatteningConfiguration: DiffFlatteningConfiguration
    public var syntaxConfiguration: SyntaxConfiguration

    public init(
        files: [DiffFile],
        fileContents: [DiffFile.ID: String],
        displayMode: DiffViewMode,
        wrapsLines: Bool,
        expandedBlockIDs: Set<String> = [],
        hiddenContextExpansionStates: [String: HiddenContextExpansionState] = [:],
        flatteningConfiguration: DiffFlatteningConfiguration = .init(),
        syntaxConfiguration: SyntaxConfiguration = .default
    ) {
        self.files = files
        self.fileContents = fileContents
        self.displayMode = displayMode
        self.wrapsLines = wrapsLines
        self.expandedBlockIDs = expandedBlockIDs
        self.hiddenContextExpansionStates = hiddenContextExpansionStates
        self.flatteningConfiguration = flatteningConfiguration
        self.syntaxConfiguration = syntaxConfiguration
    }
}

public enum DiffSurfaceModelBuilder {
    public static func build(
        request: DiffSurfaceModelRequest,
        languageResolver: (DiffFile) -> SyntaxLanguage = { _ in .plainText },
        syntaxRuntime: any SyntaxRuntimeProviding = CachingSyntaxRuntimeProvider.shared
    ) -> [DiffFile.ID: DiffRenderOutput] {
        Dictionary(uniqueKeysWithValues: request.files.map { file in
            let rows = DiffCoreEngine.rows(
                for: file,
                fullyExpandedBlockIDs: request.expandedBlockIDs,
                partiallyExpandedBlocks: request.hiddenContextExpansionStates,
                configuration: request.flatteningConfiguration
            )
            let output = DiffRendererBridge.render(
                visibleRows: rows,
                fileContents: [file.id: request.fileContents[file.id] ?? file.flattenedText],
                displayMode: request.displayMode,
                wrapsLines: request.wrapsLines,
                expansionChunkSize: request.flatteningConfiguration.expansionChunkSize,
                syntaxConfiguration: request.syntaxConfiguration,
                languageResolver: { _ in languageResolver(file) },
                syntaxRuntime: syntaxRuntime
            )
            return (file.id, output)
        })
    }
}

public enum DiffRendererBridge {
    public static func render(
        visibleRows: [VisibleDiffRow],
        fileContents: [DiffFile.ID: String],
        displayMode: DiffViewMode,
        wrapsLines: Bool,
        expansionChunkSize: Int = 20,
        syntaxConfiguration: SyntaxConfiguration = .default,
        languageResolver: (DiffFile.ID) -> SyntaxLanguage = { _ in .plainText },
        syntaxRuntime: any SyntaxRuntimeProviding = CachingSyntaxRuntimeProvider.shared
    ) -> DiffRenderOutput {
        let syntaxByFile = fileContents.map { fileID, text in
            (
                fileID,
                syntaxRuntime.highlight(text: text, language: languageResolver(fileID)).spans
            )
        }
        let syntaxMap = Dictionary(uniqueKeysWithValues: syntaxByFile)

        var blocks: [DiffRenderableBlock] = []
        var rowsByFile: [DiffFile.ID: [DiffRenderableRow]] = [:]
        var lineIndexesByFile: [DiffFile.ID: Int] = [:]

        for row in visibleRows {
            switch row.kind {
            case let .fileHeader(path, _):
                blocks.append(DiffRenderableBlock(id: row.id, fileID: row.fileID, kind: .header(path)))
            case let .hunkHeader(text):
                blocks.append(DiffRenderableBlock(id: row.id, fileID: row.fileID, kind: .header(text)))
            case let .hiddenContext(block):
                let controls = hiddenContextControls(
                    for: block,
                    chunkSize: expansionChunkSize
                )
                rowsByFile[row.fileID, default: []].append(
                    DiffRenderableRow(
                        id: row.id,
                        fileID: row.fileID,
                        text: controls.map(\.title).joined(separator: " | "),
                        oldLineNumber: nil,
                        newLineNumber: nil,
                        backgroundStyle: .hidden,
                        syntaxSpans: [],
                        hiddenContextControls: controls,
                        kind: .hiddenContext(block)
                    )
                )
            case let .line(line):
                let lineIndex = lineIndexesByFile[row.fileID, default: 0]
                let syntaxSpans = syntaxMap[row.fileID, default: []].filter { $0.lineIndex == lineIndex }
                let renderRow = DiffRenderableRow(
                    id: row.id,
                    fileID: row.fileID,
                    text: line.text,
                    oldLineNumber: line.oldLineNumber,
                    newLineNumber: line.newLineNumber,
                    backgroundStyle: background(for: line.kind),
                    syntaxSpans: syntaxSpans,
                    hiddenContextControls: [],
                    kind: .code
                )
                rowsByFile[row.fileID, default: []].append(renderRow)
                lineIndexesByFile[row.fileID] = lineIndex + 1
            }
        }

        for fileID in rowsByFile.keys {
            blocks.append(DiffRenderableBlock(id: "\(fileID)-surface", fileID: fileID, kind: .textSurface))
        }

        let surfaces = rowsByFile.keys.sorted().flatMap { fileID -> [CodeTextSurfaceModel] in
            let rows = rowsByFile[fileID, default: []]
            switch displayMode {
            case .unified:
                return [
                    CodeTextSurfaceModel(
                        id: "\(fileID)-unified",
                        fileID: fileID,
                        side: .unified,
                        rows: rows,
                        wrapsLines: wrapsLines,
                        horizontalScrollGroupID: "\(fileID)-shared"
                    )
                ]
            case .split:
                let leftRows = rows.filter {
                    if case .hiddenContext = $0.kind { return true }
                    return $0.backgroundStyle != .addition
                }
                let rightRows = rows.filter {
                    if case .hiddenContext = $0.kind { return true }
                    return $0.backgroundStyle != .deletion
                }
                return [
                    CodeTextSurfaceModel(
                        id: "\(fileID)-left",
                        fileID: fileID,
                        side: .left,
                        rows: leftRows,
                        wrapsLines: wrapsLines,
                        horizontalScrollGroupID: "\(fileID)-shared"
                    ),
                    CodeTextSurfaceModel(
                        id: "\(fileID)-right",
                        fileID: fileID,
                        side: .right,
                        rows: rightRows,
                        wrapsLines: wrapsLines,
                        horizontalScrollGroupID: "\(fileID)-shared"
                    )
                ]
            }
        }

        return DiffRenderOutput(blocks: blocks, surfaces: surfaces)
    }

    private static func background(for kind: DiffLine.Kind) -> DiffBackgroundStyle {
        switch kind {
        case .context:
            return .neutral
        case .addition:
            return .addition
        case .deletion:
            return .deletion
        case .note:
            return .neutral
        }
    }

    private static func hiddenContextControls(
        for block: HiddenContextBlock,
        chunkSize: Int
    ) -> [HiddenContextControl] {
        return [
            HiddenContextControl(title: "⌃", action: .expandUp),
            HiddenContextControl(title: "\(block.hiddenLineCount) unmodified lines", action: .expandAll),
            HiddenContextControl(title: "⌄", action: .expandDown)
        ]
    }

}
