@testable import DiffPlatformAdapters
import DiffCore
import DiffRendering
import DiffState
import Foundation
import Testing

@Test func segmentSelectionMapsAcrossMultipleVisibleLines() throws {
    let surface = makeSurface(
        side: .unified,
        wrapsLines: false,
        rows: [
            makeCodeRow(id: "line-1", text: "alpha", old: 1, new: 1),
            makeCodeRow(id: "line-2", text: "beta", old: 2, new: 2)
        ]
    )

    let segment = try #require(firstSegment(in: surface))
    let selection = try #require(segment.selection(for: NSRange(location: 1, length: 7)))

    #expect(selection.surface == .unified)
    #expect(selection.anchor == .init(rowID: "line-1", utf16Offset: 1))
    #expect(selection.focus == .init(rowID: "line-2", utf16Offset: 2))
}

@Test func segmentCopyTextStripsPlaceholderCharactersForBlankRows() throws {
    let surface = makeSurface(
        side: .unified,
        wrapsLines: false,
        rows: [
            makeCodeRow(id: "line-1", text: "", old: 1, new: 1),
            makeCodeRow(id: "line-2", text: "beta", old: 2, new: 2)
        ]
    )

    let segment = try #require(firstSegment(in: surface))

    #expect(segment.text == " \nbeta")
    #expect(segment.sanitizedText(in: NSRange(location: 0, length: segment.totalUTF16Length)) == "\nbeta")
}

@Test func splitSurfaceSelectionPreservesActivePane() throws {
    let surface = makeSurface(
        side: .left,
        wrapsLines: false,
        rows: [
            makeCodeRow(id: "line-1", text: "alpha", old: 1, new: nil),
            makeCodeRow(id: "line-2", text: "beta", old: 2, new: nil)
        ]
    )

    let segment = try #require(firstSegment(in: surface))
    let selection = try #require(segment.selection(for: NSRange(location: 0, length: 3)))

    #expect(selection.surface == .left)
}

@Test func hiddenContextRowsSplitSelectableSegments() {
    let hiddenBlock = HiddenContextBlock(
        id: "block-1",
        fileID: "file-1",
        hunkID: "hunk-1",
        range: 4..<8
    )
    let surface = makeSurface(
        side: .unified,
        wrapsLines: false,
        rows: [
            makeCodeRow(id: "line-1", text: "alpha", old: 1, new: 1),
            DiffRenderableRow(
                id: "hidden-1",
                fileID: "file-1",
                text: "show more",
                oldLineNumber: nil,
                newLineNumber: nil,
                backgroundStyle: .hidden,
                syntaxSpans: [],
                hiddenContextControls: [.init(title: "20", action: .expandAll)],
                kind: .hiddenContext(hiddenBlock)
            ),
            makeCodeRow(id: "line-2", text: "beta", old: 9, new: 9)
        ]
    )

    let layout = CodeTextSurfaceLayout(surface: surface)

    #expect(layout.items.count == 3)
    #expect(layout.items[0].id == "file-1-unified-segment-0")
    #expect(layout.items[1].id == "hidden-1")
    #expect(layout.items[2].id == "file-1-unified-segment-1")
}

@Test func wrappedAndUnwrappedSegmentsShareLogicalSelectionMapping() throws {
    let rows = [
        makeCodeRow(id: "line-1", text: "alpha", old: 1, new: 1),
        makeCodeRow(id: "line-2", text: "beta", old: 2, new: 2)
    ]
    let wrapped = try #require(firstSegment(in: makeSurface(side: .unified, wrapsLines: true, rows: rows)))
    let unwrapped = try #require(firstSegment(in: makeSurface(side: .unified, wrapsLines: false, rows: rows)))

    let range = NSRange(location: 2, length: 5)

    #expect(wrapped.selection(for: range) == unwrapped.selection(for: range))
}

private func firstSegment(in surface: CodeTextSurfaceModel) -> CodeTextSegment? {
    let layout = CodeTextSurfaceLayout(surface: surface)
    for item in layout.items {
        if case let .segment(segment) = item {
            return segment
        }
    }
    return nil
}

private func makeSurface(
    side: CodeTextSurfaceModel.Side,
    wrapsLines: Bool,
    rows: [DiffRenderableRow]
) -> CodeTextSurfaceModel {
    CodeTextSurfaceModel(
        id: "file-1-\(side.rawValue)",
        fileID: "file-1",
        side: side,
        rows: rows,
        wrapsLines: wrapsLines,
        horizontalScrollGroupID: "file-1-shared"
    )
}

private func makeCodeRow(
    id: String,
    text: String,
    old: Int?,
    new: Int?
) -> DiffRenderableRow {
    DiffRenderableRow(
        id: id,
        fileID: "file-1",
        text: text,
        oldLineNumber: old,
        newLineNumber: new,
        backgroundStyle: .neutral,
        syntaxSpans: [],
        hiddenContextControls: [],
        kind: .code
    )
}
