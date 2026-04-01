import DiffCore
import DiffState
import Foundation
import Testing

@Test func controllerTogglesAndPersistsDisplayOptions() throws {
    let controller = DiffController()
    controller.setViewMode(.split)
    controller.setWrapsLines(true)
    controller.setShowsFileTree(false)
    controller.toggleFileCollapsed("file-1")
    controller.markBlockExpanded("block-1")
    controller.select(fileID: "file-1", lineID: "line-7")

    let snapshot = controller.snapshot()

    #expect(snapshot.displayOptions.viewMode == .split)
    #expect(snapshot.displayOptions.wrapsLines)
    #expect(snapshot.displayOptions.showsFileTree == false)
    #expect(snapshot.collapsedFileIDs.contains("file-1"))
    #expect(snapshot.expandedBlockIDs.contains("block-1"))
    #expect(snapshot.selection?.lineID == "line-7")
}

@Test func restoreRoundTripsSnapshot() {
    let controller = DiffController()
    let snapshot = DiffPersistenceSnapshot(
        displayOptions: .init(viewMode: .split, wrapsLines: true, showsFileTree: false),
        collapsedFileIDs: ["file-1"],
        expandedBlockIDs: ["block-1"],
        selection: DiffSelection(fileID: "file-1", lineID: "line-2"),
        viewport: DiffViewport(fileID: "file-1", anchorRowID: "line-2")
    )

    controller.restore(from: snapshot)

    #expect(controller.displayOptions == snapshot.displayOptions)
    #expect(controller.collapsedFileIDs == snapshot.collapsedFileIDs)
    #expect(controller.expandedBlockIDs == snapshot.expandedBlockIDs)
    #expect(controller.selection == snapshot.selection)
    #expect(controller.viewport == snapshot.viewport)
}

@Test func selectionDefaultsLineIDFromTextSelectionAnchor() {
    let selection = DiffSelection(
        fileID: "file-1",
        textSelection: DiffTextSelection(
            surface: .right,
            anchor: .init(rowID: "line-4", utf16Offset: 2),
            focus: .init(rowID: "line-5", utf16Offset: 1)
        )
    )

    #expect(selection.lineID == "line-4")
    #expect(selection.textSelection?.surface == .right)
}

@Test func persistenceSnapshotDecodesLegacySelectionPayload() throws {
    let json = #"""
    {
      "displayOptions": {
        "viewMode": "unified",
        "wrapsLines": false,
        "showsFileTree": true
      },
      "collapsedFileIDs": [],
      "expandedBlockIDs": [],
      "hiddenContextExpansionStates": {},
      "selection": {
        "fileID": "file-1",
        "lineID": "line-2"
      },
      "viewport": {
        "fileID": "file-1",
        "anchorRowID": "line-2"
      }
    }
    """#

    let snapshot = try JSONDecoder().decode(
        DiffPersistenceSnapshot.self,
        from: Data(json.utf8)
    )

    #expect(snapshot.selection?.fileID == "file-1")
    #expect(snapshot.selection?.lineID == "line-2")
    #expect(snapshot.selection?.textSelection == nil)
}

@Test func persistenceSnapshotRoundTripsRichSelectionPayload() throws {
    let snapshot = DiffPersistenceSnapshot(
        selection: DiffSelection(
            fileID: "file-1",
            lineID: "line-7",
            textSelection: DiffTextSelection(
                surface: .left,
                anchor: .init(rowID: "line-7", utf16Offset: 1),
                focus: .init(rowID: "line-9", utf16Offset: 3)
            )
        )
    )

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(DiffPersistenceSnapshot.self, from: data)

    #expect(decoded.selection == snapshot.selection)
}

@Test func controllerRevealsHiddenContextInChunks() {
    let controller = DiffController()
    let block = HiddenContextBlock(id: "block-1", fileID: "file-1", hunkID: "hunk-1", range: 10..<40)

    controller.revealHiddenContext(block, direction: .up, lineCount: 20)
    #expect(controller.hiddenContextExpansionStates["block-1"] == HiddenContextExpansionState(
        revealedUpperLineCount: 20,
        revealedLowerLineCount: 0
    ))

    controller.revealHiddenContext(block, direction: .down, lineCount: 20)
    #expect(controller.expandedBlockIDs.contains("block-1"))
    #expect(controller.hiddenContextExpansionStates["block-1"] == nil)
}
