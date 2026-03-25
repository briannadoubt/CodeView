import Foundation

public enum SyntaxLanguage: String, CaseIterable, Hashable, Codable, Sendable {
    case swift
    case markdown
    case json
    case yaml
    case javaScript
    case typeScript
    case html
    case css
    case shell
    case plainText
}

public enum SyntaxRole: String, Hashable, Codable, Sendable {
    case keyword
    case string
    case number
    case comment
    case type
    case plain
}

public struct SyntaxSpan: Hashable, Codable, Sendable {
    public var lineIndex: Int
    public var range: Range<Int>
    public var role: SyntaxRole

    public init(lineIndex: Int, range: Range<Int>, role: SyntaxRole) {
        self.lineIndex = lineIndex
        self.range = range
        self.role = role
    }
}

public struct SyntaxTheme: Hashable, Codable, Sendable {
    public var colorsByRole: [SyntaxRole: String]

    public init(colorsByRole: [SyntaxRole: String]) {
        self.colorsByRole = colorsByRole
    }

    public static let `default` = SyntaxTheme(
        colorsByRole: [
            .keyword: "#AF4D15",
            .string: "#0D5C63",
            .number: "#7C3AED",
            .comment: "#6B7280",
            .type: "#1D4ED8",
            .plain: "#111827"
        ]
    )
}

public struct SyntaxConfiguration: Hashable, Codable, Sendable {
    public var theme: SyntaxTheme
    public var fallbackLanguage: SyntaxLanguage

    public init(
        theme: SyntaxTheme = .default,
        fallbackLanguage: SyntaxLanguage = .plainText
    ) {
        self.theme = theme
        self.fallbackLanguage = fallbackLanguage
    }

    public static let `default` = SyntaxConfiguration()
}

public struct SyntaxMetrics: Hashable, Sendable {
    public var highlightedLineCount: Int
    public var language: SyntaxLanguage

    public init(highlightedLineCount: Int, language: SyntaxLanguage) {
        self.highlightedLineCount = highlightedLineCount
        self.language = language
    }
}

public struct SyntaxHighlightResult: Hashable, Sendable {
    public var spans: [SyntaxSpan]
    public var metrics: SyntaxMetrics

    public init(spans: [SyntaxSpan], metrics: SyntaxMetrics) {
        self.spans = spans
        self.metrics = metrics
    }
}

public struct SyntaxPrewarmRequest: Hashable, Sendable {
    public var language: SyntaxLanguage
    public var visibleLineRange: Range<Int>

    public init(language: SyntaxLanguage, visibleLineRange: Range<Int>) {
        self.language = language
        self.visibleLineRange = visibleLineRange
    }
}

public struct SyntaxDocument: Hashable, Sendable {
    public var path: String
    public var text: String
    public var alias: String?
    public var shebang: String?

    public init(path: String, text: String, alias: String? = nil, shebang: String? = nil) {
        self.path = path
        self.text = text
        self.alias = alias
        self.shebang = shebang
    }
}

public protocol SyntaxRuntimeProviding: Sendable {
    func resolveLanguage(
        path: String,
        alias: String?,
        shebang: String?,
        configuration: SyntaxConfiguration
    ) -> SyntaxLanguage

    func highlight(
        text: String,
        language: SyntaxLanguage
    ) -> SyntaxHighlightResult
}

public protocol SyntaxScheduling: Sendable {
    func prewarm(request: SyntaxPrewarmRequest) async
}

public struct NoOpSyntaxScheduler: SyntaxScheduling {
    public init() {}

    public func prewarm(request: SyntaxPrewarmRequest) async {}
}

public final class CachingSyntaxRuntimeProvider: @unchecked Sendable, SyntaxRuntimeProviding {
    private struct CacheKey: Hashable {
        let language: SyntaxLanguage
        let text: String
    }

    public static let shared = CachingSyntaxRuntimeProvider(base: DefaultSyntaxRuntimeProvider.uncachedShared)

    private let base: any SyntaxRuntimeProviding
    private let lock = NSLock()
    private var cache: [CacheKey: SyntaxHighlightResult] = [:]

    public init(base: any SyntaxRuntimeProviding) {
        self.base = base
    }

    public func resolveLanguage(
        path: String,
        alias: String?,
        shebang: String?,
        configuration: SyntaxConfiguration
    ) -> SyntaxLanguage {
        base.resolveLanguage(
            path: path,
            alias: alias,
            shebang: shebang,
            configuration: configuration
        )
    }

    public func highlight(text: String, language: SyntaxLanguage) -> SyntaxHighlightResult {
        let key = CacheKey(language: language, text: text)

        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let result = base.highlight(text: text, language: language)

        lock.lock()
        cache[key] = result
        lock.unlock()

        return result
    }

    public func invalidateAll() {
        lock.lock()
        cache.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

public enum DefaultSyntaxRuntimeProvider {
    static let uncachedShared: any SyntaxRuntimeProviding = {
        if let runtime = TreeSitterSyntaxRuntime() {
            return runtime
        }
        return LightweightSyntaxRuntime()
    }()

    public static let shared: any SyntaxRuntimeProviding = CachingSyntaxRuntimeProvider(base: uncachedShared)
}

public actor SyntaxHighlightSession {
    private struct CacheKey: Hashable {
        let path: String
        let text: String
        let alias: String?
        let shebang: String?
        let configuration: SyntaxConfiguration
    }

    private let runtime: any SyntaxRuntimeProviding
    private var cache: [CacheKey: SyntaxHighlightResult] = [:]

    public init(runtime: any SyntaxRuntimeProviding = DefaultSyntaxRuntimeProvider.shared) {
        self.runtime = runtime
    }

    public func highlight(
        document: SyntaxDocument,
        configuration: SyntaxConfiguration = .default
    ) -> SyntaxHighlightResult {
        let key = CacheKey(
            path: document.path,
            text: document.text,
            alias: document.alias,
            shebang: document.shebang,
            configuration: configuration
        )
        if let cached = cache[key] {
            return cached
        }

        let language = runtime.resolveLanguage(
            path: document.path,
            alias: document.alias,
            shebang: document.shebang,
            configuration: configuration
        )
        let result = runtime.highlight(text: document.text, language: language)
        cache[key] = result
        return result
    }

    public func prewarm(
        documents: [SyntaxDocument],
        configuration: SyntaxConfiguration = .default
    ) async {
        for document in documents {
            _ = highlight(document: document, configuration: configuration)
        }
    }

    public func invalidateAll() {
        cache.removeAll(keepingCapacity: true)
    }
}
