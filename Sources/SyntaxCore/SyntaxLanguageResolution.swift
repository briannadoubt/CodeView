import Foundation

public enum SyntaxRuntime {
    public static func resolveLanguage(
        path: String,
        alias: String? = nil,
        shebang: String? = nil,
        configuration: SyntaxConfiguration = .default
    ) -> SyntaxLanguage {
        if let aliasLanguage = alias.flatMap(resolveAlias(_:)) {
            return aliasLanguage
        }

        if let shebang, shebang.contains("bash") || shebang.contains("sh") {
            return .shell
        }

        let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()

        switch filename {
        case "dockerfile", "podfile", "brewfile":
            return .shell
        case "package.json":
            return .json
        default:
            break
        }

        switch ext {
        case "swift":
            return .swift
        case "md", "markdown":
            return .markdown
        case "json":
            return .json
        case "yml", "yaml":
            return .yaml
        case "js", "mjs", "cjs":
            return .javaScript
        case "ts", "tsx":
            return .typeScript
        case "html", "htm":
            return .html
        case "css":
            return .css
        case "sh", "zsh", "bash":
            return .shell
        default:
            return configuration.fallbackLanguage
        }
    }

    public static func resolveAlias(_ alias: String) -> SyntaxLanguage? {
        switch alias.lowercased() {
        case "js", "javascript":
            return .javaScript
        case "ts", "typescript", "tsx", "jsx":
            return .typeScript
        case "md", "markdown":
            return .markdown
        case "yml", "yaml":
            return .yaml
        case "shell", "bash", "sh":
            return .shell
        case "swift":
            return .swift
        case "html":
            return .html
        case "css":
            return .css
        case "json":
            return .json
        default:
            return nil
        }
    }

    public static func highlight(
        text: String,
        language: SyntaxLanguage
    ) -> SyntaxHighlightResult {
        LightweightSyntaxRuntime().highlight(text: text, language: language)
    }
}
