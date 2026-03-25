import Foundation

public struct LightweightSyntaxRuntime: SyntaxRuntimeProviding {
    public init() {}

    public func resolveLanguage(
        path: String,
        alias: String? = nil,
        shebang: String? = nil,
        configuration: SyntaxConfiguration = .default
    ) -> SyntaxLanguage {
        SyntaxRuntime.resolveLanguage(path: path, alias: alias, shebang: shebang, configuration: configuration)
    }

    public func highlight(text: String, language: SyntaxLanguage) -> SyntaxHighlightResult {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var spans: [SyntaxSpan] = []

        for (lineIndex, line) in lines.enumerated() {
            spans.append(contentsOf: classify(line: line, at: lineIndex, language: language))
        }

        return SyntaxHighlightResult(
            spans: spans,
            metrics: SyntaxMetrics(highlightedLineCount: lines.count, language: language)
        )
    }

    private func classify(line: String, at lineIndex: Int, language: SyntaxLanguage) -> [SyntaxSpan] {
        var spans: [SyntaxSpan] = []

        if let commentRange = line.range(of: "//") {
            let lower = line.distance(from: line.startIndex, to: commentRange.lowerBound)
            let upper = line.distance(from: line.startIndex, to: line.endIndex)
            spans.append(SyntaxSpan(lineIndex: lineIndex, range: lower..<upper, role: .comment))
        }

        for keyword in keywords(for: language) {
            if let range = line.range(of: keyword) {
                let lower = line.distance(from: line.startIndex, to: range.lowerBound)
                let upper = line.distance(from: line.startIndex, to: range.upperBound)
                spans.append(SyntaxSpan(lineIndex: lineIndex, range: lower..<upper, role: .keyword))
            }
        }

        if let quoteStart = line.firstIndex(of: "\""), let quoteEnd = line.lastIndex(of: "\""), quoteStart != quoteEnd {
            let lower = line.distance(from: line.startIndex, to: quoteStart)
            let upper = line.distance(from: line.startIndex, to: quoteEnd) + 1
            spans.append(SyntaxSpan(lineIndex: lineIndex, range: lower..<upper, role: .string))
        }

        if let numberRange = line.range(of: #"\b\d+\b"#, options: .regularExpression) {
            let lower = line.distance(from: line.startIndex, to: numberRange.lowerBound)
            let upper = line.distance(from: line.startIndex, to: numberRange.upperBound)
            spans.append(SyntaxSpan(lineIndex: lineIndex, range: lower..<upper, role: .number))
        }

        return spans.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    private func keywords(for language: SyntaxLanguage) -> [String] {
        switch language {
        case .swift:
            return ["func", "struct", "enum", "let", "var", "import"]
        case .javaScript, .typeScript:
            return ["function", "const", "let", "export", "import"]
        case .html:
            return ["<div", "<span", "<script", "<style"]
        case .css:
            return ["color", "display", "grid", "flex"]
        case .markdown:
            return ["# ", "## ", "```"]
        case .json, .yaml, .shell, .plainText:
            return []
        }
    }
}
