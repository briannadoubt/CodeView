import DiffCore
import DiffState
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
