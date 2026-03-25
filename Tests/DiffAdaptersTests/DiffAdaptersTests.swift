import DiffAdapters
import DiffCore
import DiffRendering
import Foundation
import GitDiffAdapters
import SyntaxCore
import Testing

@Test func lineBasedSnapshotBuildsCodeViewFilesIncludingNotes() {
    let files = LineBasedDiffAdapter.makeDiffFiles(from: [fixtureFile()])

    #expect(files.count == 1)
    #expect(files[0].path == "Sources/App/Inspector.swift")
    #expect(files[0].hunks[0].lines[2].kind == .note)
    #expect(files[0].isCollapsed == false)
}

@Test func lineBasedSnapshotBuildsNestedFileTreeFromRelativePaths() {
    let tree = LineBasedDiffAdapter.makeFileTree(from: [
        fixtureFile(),
        LineBasedDiffFile(
            id: "package",
            relativePath: "Package.swift",
            hunks: []
        )
    ])

    #expect(tree.count == 2)
    #expect(tree[0].kind == .directory)
    #expect(tree[0].name == "Sources")
    #expect(tree[0].children.first?.name == "App")
    #expect(tree[1].kind == .file)
    #expect(tree[1].fileID == "package")
}

@Test func lineBasedSnapshotBuildsSurfaceRequestWithFallbackContents() {
    let request = LineBasedDiffAdapter.makeSurfaceModelRequest(
        from: [fixtureFile()],
        displayMode: .unified,
        wrapsLines: false,
        syntaxConfiguration: .default
    )

    #expect(request.files.count == 1)
    #expect(request.fileContents["inspector"]?.contains("struct Inspector") == true)

    let rendered = DiffSurfaceModelBuilder.build(
        request: request,
        languageResolver: { _ in .swift }
    )

    #expect(rendered["inspector"]?.surfaces.count == 1)
    #expect(rendered["inspector"]?.surfaces[0].rows.contains(where: \.isInlineHiddenContextControl) == false)
}

@Test func lineBasedSnapshotReconstructsOmittedContextFromFileContents() {
    let file = LineBasedDiffFile(
        id: "multi-hunk",
        relativePath: "Sources/App/Multi.swift",
        addedLineCount: 1,
        removedLineCount: 1,
        hunks: [
            LineBasedDiffHunk(
                id: "hunk-1",
                header: "@@ -1,4 +1,4 @@",
                oldStart: 1,
                oldCount: 4,
                newStart: 1,
                newCount: 4,
                lines: [
                    LineBasedDiffLine(kind: .context, text: "line1", oldLineNumber: 1, newLineNumber: 1),
                    LineBasedDiffLine(kind: .deletion, text: "line2-old", oldLineNumber: 2, newLineNumber: nil),
                    LineBasedDiffLine(kind: .addition, text: "line2-new", oldLineNumber: nil, newLineNumber: 2),
                    LineBasedDiffLine(kind: .context, text: "line3", oldLineNumber: 3, newLineNumber: 3),
                    LineBasedDiffLine(kind: .context, text: "line4", oldLineNumber: 4, newLineNumber: 4)
                ]
            ),
            LineBasedDiffHunk(
                id: "hunk-2",
                header: "@@ -9,3 +9,3 @@",
                oldStart: 9,
                oldCount: 3,
                newStart: 9,
                newCount: 3,
                lines: [
                    LineBasedDiffLine(kind: .context, text: "line9", oldLineNumber: 9, newLineNumber: 9),
                    LineBasedDiffLine(kind: .deletion, text: "line10-old", oldLineNumber: 10, newLineNumber: nil),
                    LineBasedDiffLine(kind: .addition, text: "line10-new", oldLineNumber: nil, newLineNumber: 10),
                    LineBasedDiffLine(kind: .context, text: "line11", oldLineNumber: 11, newLineNumber: 11)
                ]
            )
        ]
    )

    let request = LineBasedDiffAdapter.makeSurfaceModelRequest(
        from: [file],
        fileContentsByFileID: [
            "multi-hunk": [
                "line1",
                "line2-new",
                "line3",
                "line4",
                "line5",
                "line6",
                "line7",
                "line8",
                "line9",
                "line10-new",
                "line11",
                "line12"
            ].joined(separator: "\n")
        ],
        displayMode: .unified,
        wrapsLines: false
    )

    let rendered = DiffSurfaceModelBuilder.build(
        request: request,
        languageResolver: { _ in .swift }
    )

    let rows = rendered["multi-hunk"]?.surfaces.first?.rows ?? []
    #expect(rows.contains { row in
        row.isInlineHiddenContextControl && row.text.contains("unmodified lines")
    })
}

@Test func stagedScopeLoadsCombinedTrackedDiffs() throws {
    let repoURL = try makeRepository()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let stagedURL = repoURL.appendingPathComponent("Staged.swift")
    try "print(\"base\")\n".write(to: stagedURL, atomically: true, encoding: .utf8)
    try git(["add", "Staged.swift"], in: repoURL)
    try git(["commit", "-m", "Add staged file"], in: repoURL)

    try "print(\"updated\")\n".write(to: stagedURL, atomically: true, encoding: .utf8)
    try git(["add", "Staged.swift"], in: repoURL)

    let snapshot = GitDiffLoader.loadSnapshot(rootPath: repoURL.path, scope: .staged)

    #expect(snapshot.files.count == 1)
    #expect(snapshot.files.first?.relativePath == "Staged.swift")
    #expect(snapshot.files.first?.rawPatch.isEmpty == true)
    #expect(snapshot.files.first?.hunks.contains(where: { hunk in
        hunk.lines.contains(where: { $0.kind == .addition && $0.text.contains("updated") })
    }) == true)
}

@Test func stagedCatalogPreservesRenamePaths() throws {
    let repoURL = try makeRepository()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let oldURL = repoURL.appendingPathComponent("Old Name.swift")
    try "print(\"base\")\n".write(to: oldURL, atomically: true, encoding: .utf8)
    try git(["add", "Old Name.swift"], in: repoURL)
    try git(["commit", "-m", "Initial"], in: repoURL)

    try git(["mv", "Old Name.swift", "New Name.swift"], in: repoURL)

    let catalog = GitDiffLoader.loadCatalog(rootPath: repoURL.path, scope: .staged)

    #expect(catalog.issueMessage == nil)
    #expect(catalog.entries.count == 1)
    #expect(catalog.entries.first?.status == .renamed)
    #expect(catalog.entries.first?.relativePath == "New Name.swift")
    #expect(catalog.entries.first?.originalRelativePath == "Old Name.swift")
}

@Test func selectedFileLoaderHydratesTrackedAndUntrackedFilesIndividually() throws {
    let repoURL = try makeRepository()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let trackedURL = repoURL.appendingPathComponent("Tracked.swift")
    try "print(\"base\")\n".write(to: trackedURL, atomically: true, encoding: .utf8)
    try git(["add", "Tracked.swift"], in: repoURL)
    try git(["commit", "-m", "Initial"], in: repoURL)
    try "print(\"changed\")\n".write(to: trackedURL, atomically: true, encoding: .utf8)

    let untrackedURL = repoURL.appendingPathComponent("Untracked.swift")
    try "print(\"untracked\")\n".write(to: untrackedURL, atomically: true, encoding: .utf8)

    let trackedResult = GitDiffLoader.loadFileDiff(
        rootPath: repoURL.path,
        scope: .unstaged,
        relativePath: "Tracked.swift"
    )
    let untrackedResult = GitDiffLoader.loadFileDiff(
        rootPath: repoURL.path,
        scope: .unstaged,
        relativePath: "Untracked.swift"
    )

    switch trackedResult {
    case let .diff(file):
        #expect(file.relativePath == "Tracked.swift")
        #expect(file.rawPatch.isEmpty)
        #expect(file.plainTextPreviewText.contains("print(\"changed\")"))
    default:
        Issue.record("Expected tracked selected-file diff to load")
    }

    switch untrackedResult {
    case let .diff(file):
        #expect(file.relativePath == "Untracked.swift")
        #expect(file.isUntracked)
    default:
        Issue.record("Expected untracked selected-file diff to load")
    }
}

@Test func selectedFileLoaderReturnsTooLargeUntilForced() throws {
    let repoURL = try makeRepository()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let largeURL = repoURL.appendingPathComponent("Large.txt")
    let largeLine = String(repeating: "x", count: GitDiffLoader.maximumFileBytes + 64)
    try "\(largeLine)\n".write(to: largeURL, atomically: true, encoding: .utf8)

    let initial = GitDiffLoader.loadFileDiff(
        rootPath: repoURL.path,
        scope: .unstaged,
        relativePath: "Large.txt"
    )
    let forced = GitDiffLoader.loadFileDiff(
        rootPath: repoURL.path,
        scope: .unstaged,
        relativePath: "Large.txt",
        forceLargeDiff: true
    )

    switch initial {
    case let .tooLarge(message):
        #expect(message.contains("Large.txt"))
    default:
        Issue.record("Expected large file fallback before force-loading")
    }

    switch forced {
    case let .diff(file):
        #expect(file.relativePath == "Large.txt")
        #expect(file.isUntracked)
    default:
        Issue.record("Expected force-loaded large file diff")
    }
}

@Test func selectedFileLoaderFallsBackToSummaryForExtremeForcedDiff() throws {
    let repoURL = try makeRepository()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let largeURL = repoURL.appendingPathComponent("Huge.txt")
    let largeLine = String(repeating: "x", count: GitDiffLoader.maximumInlinePreviewBytes + 64)
    try "\(largeLine)\n".write(to: largeURL, atomically: true, encoding: .utf8)

    let forced = GitDiffLoader.loadFileDiff(
        rootPath: repoURL.path,
        scope: .unstaged,
        relativePath: "Huge.txt",
        forceLargeDiff: true
    )

    switch forced {
    case let .diff(file):
        #expect(file.relativePath == "Huge.txt")
        #expect(file.hunks.isEmpty)
        #expect(file.rawPatch.contains("Diff preview omitted."))
    default:
        Issue.record("Expected summary fallback for an extreme forced diff")
    }
}

@Test func selectedFileLoaderFallsBackToPlainTextPreviewForRowHeavyDiff() throws {
    let repoURL = try makeRepository()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let tallURL = repoURL.appendingPathComponent("Tall.txt")
    let tallContents = (0..<(LineBasedDiffFile.maximumStructuredPreviewRowCount + 32))
        .map { "line-\($0)" }
        .joined(separator: "\n")
    try "\(tallContents)\n".write(to: tallURL, atomically: true, encoding: .utf8)

    let result = GitDiffLoader.loadFileDiff(
        rootPath: repoURL.path,
        scope: .unstaged,
        relativePath: "Tall.txt"
    )

    switch result {
    case let .diff(file):
        #expect(file.relativePath == "Tall.txt")
        #expect(file.prefersPlainTextPreview)
        #expect(file.hunks.isEmpty)
        #expect(file.rawPatch.contains("diff --git"))
    default:
        Issue.record("Expected row-heavy diff to load as a plain-text preview")
    }
}

@Test func selectedFileLoaderReturnsUnavailableForBinaryFile() throws {
    let repoURL = try makeRepository()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let binaryURL = repoURL.appendingPathComponent("Asset.bin")
    try Data([0x00, 0x01, 0x02]).write(to: binaryURL)

    let result = GitDiffLoader.loadFileDiff(
        rootPath: repoURL.path,
        scope: .unstaged,
        relativePath: "Asset.bin"
    )

    switch result {
    case let .unavailable(message):
        #expect(message.contains("No textual diff"))
    default:
        Issue.record("Expected binary file to return an unavailable state")
    }
}

@Test func branchScopeLoadsTrackedDiffAgainstUpstream() throws {
    let remoteURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let repoURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: remoteURL)
        try? FileManager.default.removeItem(at: repoURL)
    }

    try FileManager.default.createDirectory(at: remoteURL, withIntermediateDirectories: true)
    try git(["init", "--bare"], in: remoteURL)

    try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
    try git(["init"], in: repoURL)
    try git(["config", "user.email", "diffadapters@example.com"], in: repoURL)
    try git(["config", "user.name", "DiffAdapters Tests"], in: repoURL)

    let featureURL = repoURL.appendingPathComponent("Feature.swift")
    try "print(\"base\")\n".write(to: featureURL, atomically: true, encoding: .utf8)
    try git(["add", "Feature.swift"], in: repoURL)
    try git(["commit", "-m", "Initial"], in: repoURL)
    try git(["branch", "-M", "main"], in: repoURL)
    try git(["remote", "add", "origin", remoteURL.path], in: repoURL)
    try git(["push", "-u", "origin", "main"], in: repoURL)

    try "print(\"branch change\")\n".write(to: featureURL, atomically: true, encoding: .utf8)
    try git(["add", "Feature.swift"], in: repoURL)
    try git(["commit", "-m", "Branch change"], in: repoURL)

    let snapshot = GitDiffLoader.loadSnapshot(rootPath: repoURL.path, scope: .branch)

    #expect(snapshot.issueMessage == nil)
    #expect(snapshot.branchLabel == "main -> origin/main")
    #expect(snapshot.files.count == 1)
    #expect(snapshot.files.first?.relativePath == "Feature.swift")
    #expect(snapshot.files.first?.hunks.contains(where: { hunk in
        hunk.lines.contains(where: { $0.kind == .addition && $0.text.contains("branch change") })
    }) == true)
}

@Test func oversizedUnstagedSnapshotReturnsIssueMessage() throws {
    let repoURL = try makeRepository()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let generatedDirectory = repoURL.appendingPathComponent("Generated", isDirectory: true)
    try FileManager.default.createDirectory(at: generatedDirectory, withIntermediateDirectories: true)

    let changeCount = GitDiffLoader.maximumRenderableChangeCount + 1
    for index in 0..<changeCount {
        let fileURL = generatedDirectory.appendingPathComponent("File\(index).txt")
        try "generated\n".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    let snapshot = GitDiffLoader.loadSnapshot(rootPath: repoURL.path, scope: .unstaged)

    #expect(snapshot.files.isEmpty)
    #expect(snapshot.issueMessage == GitDiffLoader.oversizedSnapshotIssueMessage(changedFileCount: changeCount))
}

private func fixtureFile() -> LineBasedDiffFile {
    LineBasedDiffFile(
        id: "inspector",
        relativePath: "Sources/App/Inspector.swift",
        addedLineCount: 1,
        removedLineCount: 1,
        hunks: [
            LineBasedDiffHunk(
                id: "hunk-1",
                header: "@@ -1,3 +1,4 @@",
                oldStart: 1,
                oldCount: 3,
                newStart: 1,
                newCount: 4,
                lines: [
                    LineBasedDiffLine(kind: .context, text: "struct Inspector {", oldLineNumber: 1, newLineNumber: 1),
                    LineBasedDiffLine(kind: .addition, text: "    let isVisible: Bool", oldLineNumber: nil, newLineNumber: 2),
                    LineBasedDiffLine(kind: .note, text: "    // Generated from project metadata", oldLineNumber: nil, newLineNumber: nil),
                    LineBasedDiffLine(kind: .context, text: "}", oldLineNumber: 2, newLineNumber: 3)
                ]
            )
        ],
        rawPatch: "@@ -1,3 +1,4 @@",
        isUntracked: false
    )
}

private func makeRepository() throws -> URL {
    let repoURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
    try git(["init"], in: repoURL)
    try git(["config", "user.email", "diffadapters@example.com"], in: repoURL)
    try git(["config", "user.name", "DiffAdapters Tests"], in: repoURL)
    return repoURL
}

@discardableResult
private func git(_ arguments: [String], in directory: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-C", directory.path] + arguments

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    let stdoutText = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    if process.terminationStatus == 0 {
        return stdoutText
    }

    let stderrText = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    throw GitTestError(
        arguments: arguments,
        output: stderrText.isEmpty ? stdoutText : stderrText
    )
}

private struct GitTestError: Error, CustomStringConvertible {
    let arguments: [String]
    let output: String

    var description: String {
        "git \(arguments.joined(separator: " ")) failed: \(output)"
    }
}
