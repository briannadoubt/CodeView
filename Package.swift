// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodeView",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        .library(name: "DiffCore", targets: ["DiffCore"]),
        .library(name: "DiffState", targets: ["DiffState"]),
        .library(name: "SyntaxCore", targets: ["SyntaxCore"]),
        .library(name: "DiffRendering", targets: ["DiffRendering"]),
        .library(name: "DiffAdapters", targets: ["DiffAdapters"]),
        .library(name: "GitDiffAdapters", targets: ["GitDiffAdapters"]),
        .library(name: "DiffUI", targets: ["DiffUI"]),
        .library(name: "DiffPlatformAdapters", targets: ["DiffPlatformAdapters"]),
        .library(name: "CodeViewDemoSupport", targets: ["CodeViewDemoSupport"]),
        .executable(name: "CodeViewDemoMacOS", targets: ["CodeViewDemoMacOS"])
    ],
    dependencies: [
        .package(url: "https://github.com/briannadoubt/swift-git.git", exact: "0.1.1"),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.9.0"),
        .package(url: "https://github.com/simonbs/TreeSitterLanguages", from: "0.1.10")
    ],
    targets: [
        .target(
            name: "DiffCore"
        ),
        .target(
            name: "DiffState",
            dependencies: ["DiffCore"]
        ),
        .target(
            name: "SyntaxCore",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "SwiftTreeSitterLayer", package: "swift-tree-sitter"),
                .product(name: "TreeSitterBash", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterBashQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterCSS", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterCSSQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterHTML", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterHTMLQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterJavaScript", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterJavaScriptQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterJSON", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterJSONQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterMarkdown", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterMarkdownQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterMarkdownInline", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterMarkdownInlineQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterSwift", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterSwiftQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterTSX", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterTSXQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterTypeScript", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterTypeScriptQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterYAML", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterYAMLQueries", package: "TreeSitterLanguages")
            ],
            linkerSettings: [
                .linkedFramework("Carbon", .when(platforms: [.macOS])),
                .linkedLibrary("c++")
            ]
        ),
        .target(
            name: "DiffRendering",
            dependencies: ["DiffCore", "SyntaxCore"]
        ),
        .target(
            name: "DiffAdapters",
            dependencies: ["DiffCore", "DiffRendering", "SyntaxCore"]
        ),
        .target(
            name: "GitDiffAdapters",
            dependencies: [
                "DiffAdapters",
                .product(name: "SwiftGit", package: "swift-git")
            ]
        ),
        .target(
            name: "DiffPlatformAdapters",
            dependencies: ["DiffRendering"]
        ),
        .target(
            name: "DiffUI",
            dependencies: ["DiffCore", "DiffState", "SyntaxCore", "DiffRendering", "DiffPlatformAdapters"]
        ),
        .target(
            name: "CodeViewDemoSupport",
            dependencies: ["DiffCore", "DiffState", "SyntaxCore", "DiffPlatformAdapters", "DiffUI"]
        ),
        .executableTarget(
            name: "CodeViewDemoMacOS",
            dependencies: [
                .target(name: "CodeViewDemoSupport", condition: .when(platforms: [.macOS]))
            ],
            path: "Demo/CodeViewDemo-macOS/Sources"
        ),
        .testTarget(
            name: "DiffCoreTests",
            dependencies: ["DiffCore"]
        ),
        .testTarget(
            name: "DiffStateTests",
            dependencies: ["DiffState"]
        ),
        .testTarget(
            name: "SyntaxCoreTests",
            dependencies: ["SyntaxCore"]
        ),
        .testTarget(
            name: "DiffRenderingTests",
            dependencies: ["DiffRendering", "DiffCore", "SyntaxCore"]
        ),
        .testTarget(
            name: "DiffAdaptersTests",
            dependencies: ["DiffAdapters", "GitDiffAdapters", "DiffCore", "DiffRendering", "SyntaxCore"]
        )
    ]
)
