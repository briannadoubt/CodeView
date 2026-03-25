import DiffCore
import DiffPlatformAdapters
import DiffState
import DiffUI
import SyntaxCore

#if canImport(SwiftUI)
import SwiftUI
#endif

public enum DemoContent {
    public static let sampleFiles: [DiffFile] = [
        DiffFile(
            id: "swift-file",
            path: "Sources/App/FeatureView.swift",
            hunks: [
                DiffHunk(
                    id: "swift-hunk",
                    header: "@@ -1,7 +1,9 @@",
                    lines: [
                        DiffLine(id: "1", kind: .context, oldLineNumber: 1, newLineNumber: 1, text: "import SwiftUI"),
                        DiffLine(id: "2", kind: .context, oldLineNumber: 2, newLineNumber: 2, text: ""),
                        DiffLine(id: "3", kind: .context, oldLineNumber: 3, newLineNumber: 3, text: "struct FeatureView: View {"),
                        DiffLine(id: "4", kind: .deletion, oldLineNumber: 4, newLineNumber: nil, text: "    let title: String"),
                        DiffLine(id: "5", kind: .addition, oldLineNumber: nil, newLineNumber: 4, text: "    let title: LocalizedStringKey"),
                        DiffLine(id: "6", kind: .context, oldLineNumber: 5, newLineNumber: 5, text: "    var body: some View {"),
                        DiffLine(id: "7", kind: .addition, oldLineNumber: nil, newLineNumber: 6, text: "        VStack(spacing: 12) {"),
                        DiffLine(id: "8", kind: .context, oldLineNumber: 6, newLineNumber: 7, text: "            Text(title)"),
                        DiffLine(id: "9", kind: .addition, oldLineNumber: nil, newLineNumber: 8, text: "            Text(\"Ready\")"),
                        DiffLine(id: "10", kind: .context, oldLineNumber: 7, newLineNumber: 9, text: "    }"),
                        DiffLine(id: "11", kind: .context, oldLineNumber: 8, newLineNumber: 10, text: "}")
                    ]
                )
            ]
        ),
        DiffFile(
            id: "json-file",
            path: "package.json",
            hunks: [
                DiffHunk(
                    id: "json-hunk",
                    header: "@@ -1,5 +1,6 @@",
                    lines: [
                        DiffLine(id: "j1", kind: .context, oldLineNumber: 1, newLineNumber: 1, text: "{"),
                        DiffLine(id: "j2", kind: .context, oldLineNumber: 2, newLineNumber: 2, text: "  \"name\": \"codeview\","),
                        DiffLine(id: "j3", kind: .addition, oldLineNumber: nil, newLineNumber: 3, text: "  \"type\": \"module\","),
                        DiffLine(id: "j4", kind: .context, oldLineNumber: 3, newLineNumber: 4, text: "  \"version\": \"1.0.0\""),
                        DiffLine(id: "j5", kind: .context, oldLineNumber: 4, newLineNumber: 5, text: "}")
                    ]
                )
            ]
        ),
        DiffFile(
            id: "long-context-file",
            path: "Sources/App/LargeContextExample.swift",
            hunks: [
                DiffHunk(
                    id: "long-context-hunk",
                    header: "@@ -1,30 +1,31 @@",
                    lines: [
                        DiffLine(id: "lc1", kind: .context, oldLineNumber: 1, newLineNumber: 1, text: "import Foundation"),
                        DiffLine(id: "lc2", kind: .context, oldLineNumber: 2, newLineNumber: 2, text: ""),
                        DiffLine(id: "lc3", kind: .context, oldLineNumber: 3, newLineNumber: 3, text: "struct Example {"),
                        DiffLine(id: "lc4", kind: .context, oldLineNumber: 4, newLineNumber: 4, text: "    func run() {"),
                        DiffLine(id: "lc5", kind: .context, oldLineNumber: 5, newLineNumber: 5, text: "        print(\"alpha\")"),
                        DiffLine(id: "lc6", kind: .context, oldLineNumber: 6, newLineNumber: 6, text: "        print(\"beta\")"),
                        DiffLine(id: "lc7", kind: .context, oldLineNumber: 7, newLineNumber: 7, text: "        print(\"gamma\")"),
                        DiffLine(id: "lc8", kind: .context, oldLineNumber: 8, newLineNumber: 8, text: "        print(\"delta\")"),
                        DiffLine(id: "lc9", kind: .context, oldLineNumber: 9, newLineNumber: 9, text: "        print(\"epsilon\")"),
                        DiffLine(id: "lc10", kind: .context, oldLineNumber: 10, newLineNumber: 10, text: "        print(\"zeta\")"),
                        DiffLine(id: "lc11", kind: .context, oldLineNumber: 11, newLineNumber: 11, text: "        print(\"eta\")"),
                        DiffLine(id: "lc12", kind: .context, oldLineNumber: 12, newLineNumber: 12, text: "        print(\"theta\")"),
                        DiffLine(id: "lc13", kind: .context, oldLineNumber: 13, newLineNumber: 13, text: "        print(\"iota\")"),
                        DiffLine(id: "lc14", kind: .context, oldLineNumber: 14, newLineNumber: 14, text: "        print(\"kappa\")"),
                        DiffLine(id: "lc15", kind: .context, oldLineNumber: 15, newLineNumber: 15, text: "        print(\"lambda\")"),
                        DiffLine(id: "lc16", kind: .context, oldLineNumber: 16, newLineNumber: 16, text: "        print(\"mu\")"),
                        DiffLine(id: "lc17", kind: .context, oldLineNumber: 17, newLineNumber: 17, text: "        print(\"nu\")"),
                        DiffLine(id: "lc18", kind: .context, oldLineNumber: 18, newLineNumber: 18, text: "        print(\"xi\")"),
                        DiffLine(id: "lc19", kind: .context, oldLineNumber: 19, newLineNumber: 19, text: "        print(\"omicron\")"),
                        DiffLine(id: "lc20", kind: .context, oldLineNumber: 20, newLineNumber: 20, text: "        print(\"pi\")"),
                        DiffLine(id: "lc21", kind: .deletion, oldLineNumber: 21, newLineNumber: nil, text: "        let status = \"old\""),
                        DiffLine(id: "lc22", kind: .addition, oldLineNumber: nil, newLineNumber: 21, text: "        let status = \"new\""),
                        DiffLine(id: "lc23", kind: .context, oldLineNumber: 22, newLineNumber: 22, text: "        print(status)"),
                        DiffLine(id: "lc24", kind: .context, oldLineNumber: 23, newLineNumber: 23, text: "        print(\"rho\")"),
                        DiffLine(id: "lc25", kind: .context, oldLineNumber: 24, newLineNumber: 24, text: "        print(\"sigma\")"),
                        DiffLine(id: "lc26", kind: .context, oldLineNumber: 25, newLineNumber: 25, text: "        print(\"tau\")"),
                        DiffLine(id: "lc27", kind: .context, oldLineNumber: 26, newLineNumber: 26, text: "        print(\"upsilon\")"),
                        DiffLine(id: "lc28", kind: .context, oldLineNumber: 27, newLineNumber: 27, text: "        print(\"phi\")"),
                        DiffLine(id: "lc29", kind: .context, oldLineNumber: 28, newLineNumber: 28, text: "    }"),
                        DiffLine(id: "lc30", kind: .context, oldLineNumber: 29, newLineNumber: 29, text: "}")
                    ]
                )
            ]
        )
    ]

    public static let sampleTree: [FileTreeNode] = [
        FileTreeNode(
            id: "root-sources",
            name: "Sources",
            kind: .directory,
            children: [
                FileTreeNode(id: "app-dir", name: "App", kind: .directory, children: [
                    FileTreeNode(id: "feature-file", name: "FeatureView.swift", kind: .file, fileID: "swift-file")
                ])
            ]
        ),
        FileTreeNode(
            id: "root-package",
            name: "package.json",
            kind: .file,
            fileID: "json-file"
        ),
        FileTreeNode(
            id: "large-context-file",
            name: "LargeContextExample.swift",
            kind: .file,
            fileID: "long-context-file"
        )
    ]
}

#if canImport(SwiftUI)
public struct DemoDiffSurface: View {
    public init() {}

    public var body: some View {
        DiffSurfaceView(
            files: DemoContent.sampleFiles,
            fileTree: DemoContent.sampleTree,
            controller: DiffController(),
            fileContentsProvider: { id in
                DemoContent.sampleFiles.first(where: { $0.id == id })?.flattenedText
            },
            syntaxConfiguration: .default,
            renderer: AnyCodeTextSurfaceRenderer(DefaultCodeTextSurfaceRenderer())
        )
    }
}
#endif
