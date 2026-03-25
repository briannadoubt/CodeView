# Architecture

## Layering

`DiffCore`, `DiffState`, `SyntaxCore`, and `DiffRendering` are platform-agnostic. They do not import SwiftUI, AppKit, UIKit, or TextKit.

`DiffUI` is the shared SwiftUI composition layer. It builds file sections, hidden-context affordances, and high-level layout around renderer-provided text surfaces.

`DiffPlatformAdapters` is the seam for specialized code rendering. The package exposes `CodeTextSurfaceRenderer` publicly so hosts can swap in TextKit-backed implementations without changing core APIs.

## Why Tree-Sitter Lives In SyntaxCore

Syntax parsing is a document concern rather than a rendering concern. Keeping it inside `SyntaxCore` preserves stable semantic spans while allowing renderers to choose how those spans become visuals.

The first pass in this repository uses a lightweight language resolver and syntax classifier so the package builds cleanly. `SyntaxRuntime` remains the intended insertion point for tree-sitter integration.

## Hidden Context

`DiffCore` identifies large runs of unchanged context lines and replaces the middle region with `HiddenContextBlock` values. Expansion is pure and chunk-based:

- expand up reveals the nearest lines above the hole
- expand down reveals the nearest lines below the hole
- expand middle reveals symmetric chunks

This logic is deterministic and independently testable.

## Shared Horizontal Scrolling

`DiffRendering` groups visible rows into `CodeTextSurfaceModel` instances. Unified mode uses one shared surface per file body when possible; split mode uses one surface per side. The renderer layer is responsible for mapping those shared surface identifiers onto concrete horizontal scroll coordinators.

## SwiftUI-First, Adapter-Oriented

The host-facing API is `DiffSurfaceView`. SwiftUI owns layout, sections, controls, and composition. Specialized text rendering is deliberately boxed behind `CodeTextSurfaceRenderer` so platform code stays replaceable and localized.

## Backport Seams

- `DiffControlling` isolates the state model from any observation mechanism.
- `ViewportTracking` can absorb future visibility API choices.
- `NavigationLayoutStrategy` isolates navigation composition choices.
- `CodeTextSurfaceRenderer` isolates platform text engines.
- `SyntaxRuntimeProviding` and `SyntaxScheduling` isolate parser and scheduler choices.
