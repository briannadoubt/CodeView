import DiffCore
import Foundation

public struct DiffDisplayOptions: Hashable, Codable, Sendable {
    public var viewMode: DiffViewMode
    public var wrapsLines: Bool
    public var showsFileTree: Bool

    public init(
        viewMode: DiffViewMode = .unified,
        wrapsLines: Bool = false,
        showsFileTree: Bool = true
    ) {
        self.viewMode = viewMode
        self.wrapsLines = wrapsLines
        self.showsFileTree = showsFileTree
    }
}

public struct DiffSelection: Hashable, Codable, Sendable {
    public var fileID: DiffFile.ID
    public var lineID: String?

    public init(fileID: DiffFile.ID, lineID: String? = nil) {
        self.fileID = fileID
        self.lineID = lineID
    }
}

public struct DiffViewport: Hashable, Codable, Sendable {
    public var fileID: DiffFile.ID?
    public var anchorRowID: String?

    public init(fileID: DiffFile.ID? = nil, anchorRowID: String? = nil) {
        self.fileID = fileID
        self.anchorRowID = anchorRowID
    }
}

public struct DiffScrollTarget: Hashable, Codable, Sendable {
    public var rowID: String

    public init(rowID: String) {
        self.rowID = rowID
    }
}

public struct DiffPersistenceSnapshot: Hashable, Codable, Sendable {
    public var displayOptions: DiffDisplayOptions
    public var collapsedFileIDs: Set<DiffFile.ID>
    public var expandedBlockIDs: Set<String>
    public var hiddenContextExpansionStates: [String: HiddenContextExpansionState]
    public var selection: DiffSelection?
    public var viewport: DiffViewport

    public init(
        displayOptions: DiffDisplayOptions = .init(),
        collapsedFileIDs: Set<DiffFile.ID> = [],
        expandedBlockIDs: Set<String> = [],
        hiddenContextExpansionStates: [String: HiddenContextExpansionState] = [:],
        selection: DiffSelection? = nil,
        viewport: DiffViewport = .init()
    ) {
        self.displayOptions = displayOptions
        self.collapsedFileIDs = collapsedFileIDs
        self.expandedBlockIDs = expandedBlockIDs
        self.hiddenContextExpansionStates = hiddenContextExpansionStates
        self.selection = selection
        self.viewport = viewport
    }
}

public protocol DiffControlling: AnyObject {
    var displayOptions: DiffDisplayOptions { get set }
    var selection: DiffSelection? { get set }
    var viewport: DiffViewport { get set }
    var scrollTarget: DiffScrollTarget? { get set }
    var collapsedFileIDs: Set<DiffFile.ID> { get }
    var expandedBlockIDs: Set<String> { get }
    var hiddenContextExpansionStates: [String: HiddenContextExpansionState] { get }

    func toggleFileCollapsed(_ fileID: DiffFile.ID)
    func markBlockExpanded(_ blockID: String)
    func revealHiddenContext(
        _ block: HiddenContextBlock,
        direction: HiddenContextRevealDirection,
        lineCount: Int
    )
    func select(fileID: DiffFile.ID, lineID: String?)
    func setViewMode(_ mode: DiffViewMode)
    func setWrapsLines(_ wraps: Bool)
    func setShowsFileTree(_ showsFileTree: Bool)
    func restore(from snapshot: DiffPersistenceSnapshot)
    func snapshot() -> DiffPersistenceSnapshot
}

public final class DiffController: DiffControlling, @unchecked Sendable {
    public var displayOptions: DiffDisplayOptions
    public var selection: DiffSelection?
    public var viewport: DiffViewport
    public var scrollTarget: DiffScrollTarget?
    public private(set) var collapsedFileIDs: Set<DiffFile.ID>
    public private(set) var expandedBlockIDs: Set<String>
    public private(set) var hiddenContextExpansionStates: [String: HiddenContextExpansionState]

    public init(
        displayOptions: DiffDisplayOptions = .init(),
        selection: DiffSelection? = nil,
        viewport: DiffViewport = .init(),
        collapsedFileIDs: Set<DiffFile.ID> = [],
        expandedBlockIDs: Set<String> = [],
        hiddenContextExpansionStates: [String: HiddenContextExpansionState] = [:]
    ) {
        self.displayOptions = displayOptions
        self.selection = selection
        self.viewport = viewport
        self.collapsedFileIDs = collapsedFileIDs
        self.expandedBlockIDs = expandedBlockIDs
        self.hiddenContextExpansionStates = hiddenContextExpansionStates
    }

    public func toggleFileCollapsed(_ fileID: DiffFile.ID) {
        if collapsedFileIDs.contains(fileID) {
            collapsedFileIDs.remove(fileID)
        } else {
            collapsedFileIDs.insert(fileID)
        }
    }

    public func markBlockExpanded(_ blockID: String) {
        expandedBlockIDs.insert(blockID)
        hiddenContextExpansionStates.removeValue(forKey: blockID)
    }

    public func revealHiddenContext(
        _ block: HiddenContextBlock,
        direction: HiddenContextRevealDirection,
        lineCount: Int
    ) {
        let nextState = hiddenContextExpansionStates[block.id, default: .init()].applying(
            direction,
            lineCount: lineCount,
            in: block.range
        )

        if nextState.remainingRange(in: block.range) == nil {
            markBlockExpanded(block.id)
        } else {
            hiddenContextExpansionStates[block.id] = nextState
        }
    }

    public func select(fileID: DiffFile.ID, lineID: String?) {
        selection = DiffSelection(fileID: fileID, lineID: lineID)
        if let lineID {
            scrollTarget = DiffScrollTarget(rowID: lineID)
        }
    }

    public func setViewMode(_ mode: DiffViewMode) {
        displayOptions.viewMode = mode
    }

    public func setWrapsLines(_ wraps: Bool) {
        displayOptions.wrapsLines = wraps
    }

    public func setShowsFileTree(_ showsFileTree: Bool) {
        displayOptions.showsFileTree = showsFileTree
    }

    public func restore(from snapshot: DiffPersistenceSnapshot) {
        displayOptions = snapshot.displayOptions
        collapsedFileIDs = snapshot.collapsedFileIDs
        expandedBlockIDs = snapshot.expandedBlockIDs
        hiddenContextExpansionStates = snapshot.hiddenContextExpansionStates
        selection = snapshot.selection
        viewport = snapshot.viewport
    }

    public func snapshot() -> DiffPersistenceSnapshot {
        DiffPersistenceSnapshot(
            displayOptions: displayOptions,
            collapsedFileIDs: collapsedFileIDs,
            expandedBlockIDs: expandedBlockIDs,
            hiddenContextExpansionStates: hiddenContextExpansionStates,
            selection: selection,
            viewport: viewport
        )
    }
}
