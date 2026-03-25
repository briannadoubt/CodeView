import DiffCore
import Testing

@Test func unifiedFlatteningIncludesHeadersAndLines() {
    let file = fixtureFile()
    let rows = DiffCoreEngine.rows(for: file)

    #expect(rows.count == 7)
    #expect({
        if case .fileHeader = rows[0].kind { return true }
        return false
    }())
    #expect({
        if case .hunkHeader = rows[1].kind { return true }
        return false
    }())
}

@Test func hiddenContextCreationReplacesMiddleOfLongRuns() {
    let lines = (0..<10).map { index in
        let lineNumber: Int = index
        return DiffLine(id: String(lineNumber), kind: .context, oldLineNumber: lineNumber, newLineNumber: lineNumber, text: "line \(lineNumber)")
    }
    let hunk = DiffHunk(id: "h", header: "@@", lines: lines)
    let file = DiffFile(id: "f", path: "file.swift", hunks: [hunk])

    let rows = DiffCoreEngine.rows(for: file, configuration: .init(visibleContextRadius: 2, expansionChunkSize: 3))
    let hiddenRows = rows.filter {
        if case .hiddenContext = $0.kind { return true }
        return false
    }

    #expect(hiddenRows.count == 1)
    #expect({
        guard case let .hiddenContext(block) = hiddenRows[0].kind else { return false }
        return block.range == 2..<8
    }())
}

@Test func expandUpDownAndMiddleRevealNearestLines() {
    let hunk = DiffHunk(
        id: "h",
        header: "@@",
        lines: (0..<30).map { index in
            let lineNumber: Int = index
            return DiffLine(id: String(lineNumber), kind: .context, oldLineNumber: lineNumber, newLineNumber: lineNumber, text: "line \(lineNumber)")
        }
    )
    let block = HiddenContextBlock(id: "b", fileID: "f", hunkID: "h", range: 5..<25)
    let config = DiffFlatteningConfiguration(visibleContextRadius: 3, expansionChunkSize: 4)

    #expect(DiffCoreEngine.expand(block: block, in: hunk, direction: .up, configuration: config) == 5..<9)
    #expect(DiffCoreEngine.expand(block: block, in: hunk, direction: .down, configuration: config) == 21..<25)
    #expect(DiffCoreEngine.expand(block: block, in: hunk, direction: .middle, configuration: config) == 13..<17)
}

@Test func partialExpansionKeepsHiddenBlockInlineWhileRevealingNearestLines() {
    let lines = (0..<10).map { index in
        let lineNumber: Int = index
        return DiffLine(id: String(lineNumber), kind: .context, oldLineNumber: lineNumber, newLineNumber: lineNumber, text: "line \(lineNumber)")
    }
    let hunk = DiffHunk(id: "h", header: "@@", lines: lines)
    let file = DiffFile(id: "f", path: "file.swift", hunks: [hunk])
    let blockID = "f-h-hidden-2-8"

    let rows = DiffCoreEngine.rows(
        for: file,
        partiallyExpandedBlocks: [
            blockID: HiddenContextExpansionState(revealedUpperLineCount: 2, revealedLowerLineCount: 1)
        ],
        configuration: .init(visibleContextRadius: 2, expansionChunkSize: 20)
    )

    let visibleLineIDs = rows.compactMap { row -> String? in
        guard case let .line(line) = row.kind else { return nil }
        return line.id
    }
    #expect(visibleLineIDs == ["0", "1", "2", "3", "7", "8", "9"])
    #expect({
        guard let hiddenRow = rows.first(where: {
            if case .hiddenContext = $0.kind { return true }
            return false
        }) else { return false }
        guard case let .hiddenContext(block) = hiddenRow.kind else { return false }
        return block.range == 4..<7
    }())
}

@Test func collapsedFilesOnlyExposeFileHeader() {
    var file = fixtureFile()
    file.isCollapsed = true

    let rows = DiffCoreEngine.rows(for: file)
    #expect(rows.count == 1)
}

private func fixtureFile() -> DiffFile {
    DiffFile(
        id: "f",
        path: "file.swift",
        hunks: [
            DiffHunk(
                id: "h",
                header: "@@ -1,3 +1,3 @@",
                lines: [
                    DiffLine(id: "1", kind: .context, oldLineNumber: 1, newLineNumber: 1, text: "import Foundation"),
                    DiffLine(id: "2", kind: .deletion, oldLineNumber: 2, newLineNumber: nil, text: "let oldValue = 1"),
                    DiffLine(id: "3", kind: .addition, oldLineNumber: nil, newLineNumber: 2, text: "let newValue = 2"),
                    DiffLine(id: "4", kind: .context, oldLineNumber: 3, newLineNumber: 3, text: "print(newValue)"),
                    DiffLine(id: "5", kind: .context, oldLineNumber: 4, newLineNumber: 4, text: "return")
                ]
            )
        ]
    )
}
