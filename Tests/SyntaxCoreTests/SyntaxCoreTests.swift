import SyntaxCore
import Foundation
import Testing

@Test func resolvesLanguagesByExtensionAliasAndShebang() {
    #expect(SyntaxRuntime.resolveLanguage(path: "FeatureView.swift") == .swift)
    #expect(SyntaxRuntime.resolveLanguage(path: "README", alias: "markdown") == .markdown)
    #expect(SyntaxRuntime.resolveLanguage(path: "script", shebang: "#!/bin/bash") == .shell)
}

@Test func highlightProducesKeywordStringAndNumberSpans() {
    let result = SyntaxRuntime.highlight(
        text: "func greet() {\n    let value = \"hi\" // note\n    return 42\n}",
        language: .swift
    )

    #expect(result.metrics.language == .swift)
    #expect(result.spans.contains(where: { $0.role == .keyword }))
    #expect(result.spans.contains(where: { $0.role == .string }))
    #expect(result.spans.contains(where: { $0.role == .number }))
    #expect(result.spans.contains(where: { $0.role == .comment }))
}

@Test func cachingSyntaxRuntimeProviderReusesCachedResultsByLanguageAndText() {
    let runtime = CountingSyntaxRuntime()
    let cachedRuntime = CachingSyntaxRuntimeProvider(base: runtime)

    let swiftResult = cachedRuntime.highlight(text: "let value = 1", language: .swift)
    let repeatedSwiftResult = cachedRuntime.highlight(text: "let value = 1", language: .swift)
    let jsonResult = cachedRuntime.highlight(text: "let value = 1", language: .json)

    #expect(swiftResult == repeatedSwiftResult)
    #expect(swiftResult != jsonResult)
    #expect(runtime.highlightCallCount == 2)
}

private final class CountingSyntaxRuntime: @unchecked Sendable, SyntaxRuntimeProviding {
    private let lock = NSLock()
    private(set) var highlightCallCount = 0

    func resolveLanguage(
        path: String,
        alias: String?,
        shebang: String?,
        configuration: SyntaxConfiguration
    ) -> SyntaxLanguage {
        .plainText
    }

    func highlight(text: String, language: SyntaxLanguage) -> SyntaxHighlightResult {
        lock.lock()
        highlightCallCount += 1
        let currentCount = highlightCallCount
        lock.unlock()

        return SyntaxHighlightResult(
            spans: [
                SyntaxSpan(
                    lineIndex: 0,
                    range: 0..<min(text.count, 1),
                    role: currentCount.isMultiple(of: 2) ? .string : .keyword
                )
            ],
            metrics: SyntaxMetrics(highlightedLineCount: 1, language: language)
        )
    }
}
