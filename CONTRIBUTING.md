# Contributing to CodeView

## Setup

- Use Xcode 16.3 or newer with Swift 6.2 support.
- On macOS, install `libgit2` and `pkgconf` with Homebrew because the Git adapter stack depends on `swift-git`.
- Keep changes inside the existing module boundaries unless there is a clear reason to move a seam.

## Local Checks

- Run `swift build`
- Run `swift test`
- Run `swift run CodeViewDemoMacOS` when touching user-facing rendering or demo support

## Change Guidelines

- Add or update tests in the affected module test target.
- Keep renderer, syntax, and diff-domain responsibilities separated.
- Document new public products or architecture shifts in `README.md` or `Docs/Architecture.md`.

## Pull Requests

- Explain the user-visible behavior change.
- Call out performance implications for large diffs or syntax prewarming when relevant.
- Include screenshots or recordings for rendering changes that are easier to review visually.
