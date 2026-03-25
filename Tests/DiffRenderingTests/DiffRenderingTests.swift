import DiffCore
import DiffRendering
import SyntaxCore
import Testing

@Test func unifiedModeCreatesSharedSurfacePerFile() {
    let rows = DiffCoreEngine.rows(for: fixtureFile())
    let output = DiffRendererBridge.render(
        visibleRows: rows,
        fileContents: ["file": fixtureFile().flattenedText],
        displayMode: .unified,
        wrapsLines: false
    )

    #expect(output.surfaces.count == 1)
    #expect(output.surfaces[0].side == .unified)
    #expect(output.surfaces[0].horizontalScrollGroupID == "file-shared")
}

@Test func splitModeCreatesPairedSurfaces() {
    let rows = DiffCoreEngine.rows(for: fixtureFile())
    let output = DiffRendererBridge.render(
        visibleRows: rows,
        fileContents: ["file": fixtureFile().flattenedText],
        displayMode: .split,
        wrapsLines: true
    )

    #expect(output.surfaces.count == 2)
    #expect(Set(output.surfaces.map(\.side)) == [.left, .right])
    #expect(output.surfaces.allSatisfy { $0.wrapsLines })
}

@Test func hiddenContextStaysInlineInsideUnifiedSurface() {
    let rows = DiffCoreEngine.rows(
        for: hiddenContextFixtureFile(),
        configuration: .init(visibleContextRadius: 2, expansionChunkSize: 3)
    )
    let output = DiffRendererBridge.render(
        visibleRows: rows,
        fileContents: ["hidden-file": hiddenContextFixtureFile().flattenedText],
        displayMode: .unified,
        wrapsLines: false,
        expansionChunkSize: 3
    )

    #expect(output.surfaces.count == 1)
    let surface = output.surfaces[0]
    #expect(surface.hiddenContextRows.count == 1)
    #expect(surface.rows.count == 5)
    #expect(surface.selectableCodeRows.count == 4)
    #expect(surface.hiddenContextRows[0].backgroundStyle == .hidden)
    #expect(surface.hiddenContextRows[0].text == "⌃ | 6 unmodified lines | ⌄")
    #expect(surface.hiddenContextRows[0].hiddenContextControls.map(\.title) == [
        "⌃",
        "6 unmodified lines",
        "⌄"
    ])
}

@Test func hiddenContextAppearsInBothSplitSidesWithoutSplittingSurfaceAgain() {
    let rows = DiffCoreEngine.rows(
        for: hiddenContextFixtureFile(),
        configuration: .init(visibleContextRadius: 2, expansionChunkSize: 3)
    )
    let output = DiffRendererBridge.render(
        visibleRows: rows,
        fileContents: ["hidden-file": hiddenContextFixtureFile().flattenedText],
        displayMode: .split,
        wrapsLines: false,
        expansionChunkSize: 3
    )

    #expect(output.surfaces.count == 2)
    #expect(output.surfaces.allSatisfy { $0.hiddenContextRows.count == 1 })
    #expect(output.surfaces.allSatisfy { $0.rows.contains(where: \.isInlineHiddenContextControl) })
}

private func fixtureFile() -> DiffFile {
    DiffFile(
        id: "file",
        path: "file.swift",
        hunks: [
            DiffHunk(
                id: "hunk",
                header: "@@",
                lines: [
                    DiffLine(id: "1", kind: .context, oldLineNumber: 1, newLineNumber: 1, text: "import Foundation"),
                    DiffLine(id: "2", kind: .deletion, oldLineNumber: 2, newLineNumber: nil, text: "let value = 1"),
                    DiffLine(id: "3", kind: .addition, oldLineNumber: nil, newLineNumber: 2, text: "let value = 2")
                ]
            )
        ]
    )
}

private func hiddenContextFixtureFile() -> DiffFile {
    DiffFile(
        id: "hidden-file",
        path: "hidden.swift",
        hunks: [
            DiffHunk(
                id: "hidden-hunk",
                header: "@@",
                lines: [
                    DiffLine(id: "h1", kind: .context, oldLineNumber: 1, newLineNumber: 1, text: "line 1"),
                    DiffLine(id: "h2", kind: .context, oldLineNumber: 2, newLineNumber: 2, text: "line 2"),
                    DiffLine(id: "h3", kind: .context, oldLineNumber: 3, newLineNumber: 3, text: "line 3"),
                    DiffLine(id: "h4", kind: .context, oldLineNumber: 4, newLineNumber: 4, text: "line 4"),
                    DiffLine(id: "h5", kind: .context, oldLineNumber: 5, newLineNumber: 5, text: "line 5"),
                    DiffLine(id: "h6", kind: .context, oldLineNumber: 6, newLineNumber: 6, text: "line 6"),
                    DiffLine(id: "h7", kind: .context, oldLineNumber: 7, newLineNumber: 7, text: "line 7"),
                    DiffLine(id: "h8", kind: .context, oldLineNumber: 8, newLineNumber: 8, text: "line 8"),
                    DiffLine(id: "h9", kind: .context, oldLineNumber: 9, newLineNumber: 9, text: "line 9"),
                    DiffLine(id: "h10", kind: .context, oldLineNumber: 10, newLineNumber: 10, text: "line 10")
                ]
            )
        ]
    )
}
