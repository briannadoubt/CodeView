import Foundation

#if canImport(SwiftTreeSitter)
import SwiftTreeSitter
#endif
#if canImport(SwiftTreeSitterLayer)
import SwiftTreeSitterLayer
#endif
#if canImport(TreeSitterBash)
import TreeSitterBash
#endif
#if canImport(TreeSitterCSS)
import TreeSitterCSS
#endif
#if canImport(TreeSitterHTML)
import TreeSitterHTML
#endif
#if canImport(TreeSitterJavaScript)
import TreeSitterJavaScript
#endif
#if canImport(TreeSitterJSON)
import TreeSitterJSON
#endif
#if canImport(TreeSitterMarkdown)
import TreeSitterMarkdown
#endif
#if canImport(TreeSitterMarkdownInline)
import TreeSitterMarkdownInline
#endif
#if canImport(TreeSitterSwift)
import TreeSitterSwift
#endif
#if canImport(TreeSitterTSX)
import TreeSitterTSX
#endif
#if canImport(TreeSitterTypeScript)
import TreeSitterTypeScript
#endif
#if canImport(TreeSitterYAML)
import TreeSitterYAML
#endif

public final class TreeSitterSyntaxRuntime: @unchecked Sendable, SyntaxRuntimeProviding {
    #if canImport(SwiftTreeSitter) && canImport(SwiftTreeSitterLayer)
    private let registry = TreeSitterLanguageRegistry()
    #endif

    public init?() {
        #if canImport(SwiftTreeSitter) && canImport(SwiftTreeSitterLayer)
        guard TreeSitterLanguageRegistry.canBuild else {
            return nil
        }
        #else
        return nil
        #endif
    }

    public func resolveLanguage(
        path: String,
        alias: String?,
        shebang: String?,
        configuration: SyntaxConfiguration
    ) -> SyntaxLanguage {
        SyntaxRuntime.resolveLanguage(path: path, alias: alias, shebang: shebang, configuration: configuration)
    }

    public func highlight(text: String, language: SyntaxLanguage) -> SyntaxHighlightResult {
        #if canImport(SwiftTreeSitter) && canImport(SwiftTreeSitterLayer)
        guard let rootConfiguration = registry.configuration(for: language) else {
            return LightweightSyntaxRuntime().highlight(text: text, language: language)
        }

        let lineTable = UTF16LineTable(text: text)
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        let layerConfiguration = LanguageLayer.Configuration(
            maximumLanguageDepth: 4,
            languageProvider: { [registry] name in
                registry.configurationForInjection(named: name)
            }
        )

        do {
            let layer = try LanguageLayer(languageConfig: rootConfiguration, configuration: layerConfiguration)
            layer.replaceContent(with: text)
            let highlights = try layer.highlights(in: fullRange, provider: text.predicateTextProvider)
            let spans = SyntaxSpanNormalizer.normalize(spans: highlights.flatMap { highlight in
                lineTable.makeLineSpans(
                    forUTF16Range: highlight.range,
                    role: TreeSitterCaptureRoleMapper.mapRole(for: highlight.name)
                )
            })
            return SyntaxHighlightResult(
                spans: spans,
                metrics: SyntaxMetrics(highlightedLineCount: lineTable.lineCount, language: language)
            )
        } catch {
            return LightweightSyntaxRuntime().highlight(text: text, language: language)
        }
        #else
        return LightweightSyntaxRuntime().highlight(text: text, language: language)
        #endif
    }
}

#if canImport(SwiftTreeSitter) && canImport(SwiftTreeSitterLayer)
private final class TreeSitterLanguageRegistry: @unchecked Sendable {
    private struct LanguageDescriptor {
        let name: String
        let queryBundleName: String
        let parserProvider: @Sendable () -> OpaquePointer?
    }

    private enum GrammarKey: Hashable {
        case swift
        case markdown
        case markdownInline
        case json
        case yaml
        case bash
        case html
        case css
        case javaScript
        case typeScript
        case tsx

        init?(language: SyntaxLanguage) {
            switch language {
            case .swift: self = .swift
            case .markdown: self = .markdown
            case .json: self = .json
            case .yaml: self = .yaml
            case .javaScript: self = .javaScript
            case .typeScript: self = .typeScript
            case .html: self = .html
            case .css: self = .css
            case .shell: self = .bash
            case .plainText: return nil
            }
        }

        init?(injectionName: String) {
            switch injectionName.lowercased() {
            case "swift": self = .swift
            case "markdown": self = .markdown
            case "markdown_inline": self = .markdownInline
            case "json": self = .json
            case "yaml", "yml": self = .yaml
            case "bash", "shell", "sh": self = .bash
            case "html": self = .html
            case "css": self = .css
            case "javascript", "js": self = .javaScript
            case "typescript", "ts": self = .typeScript
            case "tsx", "jsx": self = .tsx
            default: return nil
            }
        }
    }

    static var canBuild: Bool {
        descriptor(for: .swift).parserProvider() != nil
    }

    private let lock = NSLock()
    private var configurationCache: [GrammarKey: LanguageConfiguration] = [:]
    private var queryURLCache: [String: URL?] = [:]
    private var discoveredQueryBundleURLs: [String: URL] = [:]
    private var hasIndexedQueryBundles = false

    func configuration(for language: SyntaxLanguage) -> LanguageConfiguration? {
        guard let key = GrammarKey(language: language) else {
            return nil
        }
        return configuration(for: key)
    }

    func configurationForInjection(named name: String) -> LanguageConfiguration? {
        guard let key = GrammarKey(injectionName: name) else {
            return nil
        }
        return configuration(for: key)
    }

    private func configuration(for key: GrammarKey) -> LanguageConfiguration? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = configurationCache[key] {
            return cached
        }

        let descriptor = Self.descriptor(for: key)
        guard let parser = descriptor.parserProvider() else {
            return nil
        }

        do {
            let configuration: LanguageConfiguration
            if let queriesURL = queriesURL(forBundleName: descriptor.queryBundleName) {
                configuration = try LanguageConfiguration(parser, name: descriptor.name, queriesURL: queriesURL)
            } else {
                configuration = try LanguageConfiguration(parser, name: descriptor.name, bundleName: descriptor.queryBundleName)
            }
            configurationCache[key] = configuration
            return configuration
        } catch {
            return nil
        }
    }

    private func queriesURL(forBundleName bundleName: String) -> URL? {
        if let cached = queryURLCache[bundleName] {
            return cached
        }

        let resolved: URL?
        if let exact = Self.exactQueriesURL(forBundleName: bundleName) {
            resolved = exact
        } else {
            if hasIndexedQueryBundles == false {
                discoveredQueryBundleURLs = Self.discoverQueryBundles()
                hasIndexedQueryBundles = true
            }
            resolved = discoveredQueryBundleURLs["\(bundleName).bundle"]
        }

        queryURLCache[bundleName] = resolved
        return resolved
    }

    private static func exactQueriesURL(forBundleName bundleName: String) -> URL? {
        let bundleFileName = "\(bundleName).bundle"
        let candidateBundleURLs =
            ([Bundle.main.resourceURL] + Bundle.allBundles.map(\.resourceURL) + Bundle.allFrameworks.map(\.resourceURL))
                .compactMap { $0?.appendingPathComponent(bundleFileName, isDirectory: true) }

        for bundleURL in candidateBundleURLs where FileManager.default.fileExists(atPath: bundleURL.path) {
            if let queriesURL = bundleQueriesURL(for: bundleURL) {
                return queriesURL
            }
        }

        return nil
    }

    private static func discoverQueryBundles() -> [String: URL] {
        let candidateRoots = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).appendingPathComponent(".build", isDirectory: true),
            Bundle.main.bundleURL.deletingLastPathComponent(),
            Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        ] + Bundle.allBundles.map { $0.bundleURL.deletingLastPathComponent() }

        var bundles: [String: URL] = [:]
        for root in Set(candidateRoots) where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(".bundle") {
                guard bundles[url.lastPathComponent] == nil else { continue }
                if let queriesURL = bundleQueriesURL(for: url) {
                    bundles[url.lastPathComponent] = queriesURL
                }
            }
        }

        return bundles
    }

    private static func bundleQueriesURL(for bundleURL: URL) -> URL? {
        if FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("highlights.scm").path) {
            return bundleURL
        }

        let contentsResourcesURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        if FileManager.default.fileExists(atPath: contentsResourcesURL.appendingPathComponent("highlights.scm").path) {
            return contentsResourcesURL
        }

        let contentsQueriesURL = contentsResourcesURL.appendingPathComponent("queries", isDirectory: true)
        if FileManager.default.fileExists(atPath: contentsQueriesURL.path) {
            return contentsQueriesURL
        }

        let directQueriesURL = bundleURL.appendingPathComponent("queries", isDirectory: true)
        if FileManager.default.fileExists(atPath: directQueriesURL.path) {
            return directQueriesURL
        }

        return nil
    }

    private static func descriptor(for key: GrammarKey) -> LanguageDescriptor {
        switch key {
        case .swift:
            return .init(name: "Swift", queryBundleName: "TreeSitterLanguages_TreeSitterSwiftQueries", parserProvider: tree_sitter_swift)
        case .markdown:
            return .init(name: "Markdown", queryBundleName: "TreeSitterLanguages_TreeSitterMarkdownQueries", parserProvider: tree_sitter_markdown)
        case .markdownInline:
            return .init(name: "MarkdownInline", queryBundleName: "TreeSitterLanguages_TreeSitterMarkdownInlineQueries", parserProvider: tree_sitter_markdown_inline)
        case .json:
            return .init(name: "JSON", queryBundleName: "TreeSitterLanguages_TreeSitterJSONQueries", parserProvider: tree_sitter_json)
        case .yaml:
            return .init(name: "YAML", queryBundleName: "TreeSitterLanguages_TreeSitterYAMLQueries", parserProvider: tree_sitter_yaml)
        case .bash:
            return .init(name: "Bash", queryBundleName: "TreeSitterLanguages_TreeSitterBashQueries", parserProvider: tree_sitter_bash)
        case .html:
            return .init(name: "HTML", queryBundleName: "TreeSitterLanguages_TreeSitterHTMLQueries", parserProvider: tree_sitter_html)
        case .css:
            return .init(name: "CSS", queryBundleName: "TreeSitterLanguages_TreeSitterCSSQueries", parserProvider: tree_sitter_css)
        case .javaScript:
            return .init(name: "JavaScript", queryBundleName: "TreeSitterLanguages_TreeSitterJavaScriptQueries", parserProvider: tree_sitter_javascript)
        case .typeScript:
            return .init(name: "TypeScript", queryBundleName: "TreeSitterLanguages_TreeSitterTypeScriptQueries", parserProvider: tree_sitter_typescript)
        case .tsx:
            return .init(name: "TSX", queryBundleName: "TreeSitterLanguages_TreeSitterTSXQueries", parserProvider: tree_sitter_tsx)
        }
    }
}

private enum TreeSitterCaptureRoleMapper {
    static func mapRole(for captureName: String) -> SyntaxRole {
        let normalized = captureName.lowercased()
        if normalized.contains("comment") { return .comment }
        if normalized.contains("keyword") { return .keyword }
        if normalized.contains("string") { return .string }
        if normalized.contains("number") || normalized.contains("float") || normalized.contains("integer") { return .number }
        if normalized.contains("type")
            || normalized.contains("class")
            || normalized.contains("struct")
            || normalized.contains("enum")
            || normalized.contains("protocol") {
            return .type
        }
        return .plain
    }
}
#endif
