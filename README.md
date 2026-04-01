[![CI](https://github.com/briannadoubt/CodeView/actions/workflows/ci.yml/badge.svg)](https://github.com/briannadoubt/CodeView/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-black.svg)](LICENSE)

# CodeView

`CodeView` is a Swift package for rendering source diffs with a layered architecture that keeps diff domain logic, syntax analysis, rendering, and SwiftUI hosting decoupled.

## Requirements

- macOS 15+, iOS 18+, visionOS 2+
- Xcode 16.3+ / Swift 6.2+

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/briannadoubt/CodeView.git", from: "0.1.0")
]
```

Add the products your app needs, for example:

```swift
.product(name: "DiffUI", package: "CodeView")
```

`CodeView` resolves `swift-git`, `swift-tree-sitter`, and `TreeSitterLanguages` automatically.

## Quick Start

```swift
import CodeViewDemoSupport
import DiffPlatformAdapters
import DiffUI

let renderer = AnyCodeTextSurfaceRenderer(DefaultCodeTextSurfaceRenderer())

DiffSurfaceView(
    files: DemoContent.sampleFiles,
    fileTree: DemoContent.sampleTree,
    controller: DiffController(),
    fileContentsProvider: { id in
        DemoContent.sampleFiles.first(where: { $0.id == id })?.flattenedText
    },
    syntaxConfiguration: .default,
    renderer: renderer
)
```

## Modules

- `DiffCore`: diff domain models, flattening, and hidden-context expansion
- `DiffState`: controller actions, persistence, and display state
- `SyntaxCore`: language resolution, syntax spans, and runtime seams
- `DiffRendering`: renderable rows and text-surface models
- `DiffAdapters`: adapters for external line-based diff models
- `GitDiffAdapters`: Git-backed diff adapters built on `swift-git`
- `DiffUI`: SwiftUI host views
- `DiffPlatformAdapters`: renderer protocols and default platform adapters
- `CodeViewDemoSupport`: sample data and demo helpers

## Demo

Run the macOS demo target:

```bash
swift run CodeViewDemoMacOS
```

The architecture overview lives in [Docs/Architecture.md](Docs/Architecture.md).

## Testing

```bash
swift test
```

## License

MIT. See [LICENSE](LICENSE).
