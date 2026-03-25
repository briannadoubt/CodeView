import Foundation

enum SyntaxSpanNormalizer {
    static func normalize(spans: [SyntaxSpan]) -> [SyntaxSpan] {
        Array(Set(spans)).sorted {
            if $0.lineIndex != $1.lineIndex { return $0.lineIndex < $1.lineIndex }
            if $0.range.lowerBound != $1.range.lowerBound { return $0.range.lowerBound < $1.range.lowerBound }
            return $0.range.upperBound < $1.range.upperBound
        }
    }
}

struct UTF16LineTable {
    let lineStartOffsets: [Int]
    let lineLengths: [Int]

    init(text: String) {
        var starts: [Int] = [0]
        var lengths: [Int] = []
        var currentLength = 0

        for scalar in text.utf16 {
            if scalar == 10 {
                lengths.append(currentLength)
                starts.append(starts.last! + currentLength + 1)
                currentLength = 0
            } else {
                currentLength += 1
            }
        }

        lengths.append(currentLength)
        self.lineStartOffsets = starts
        self.lineLengths = lengths
    }

    var lineCount: Int {
        lineLengths.count
    }

    func makeLineSpans(forUTF16Range range: NSRange, role: SyntaxRole) -> [SyntaxSpan] {
        guard range.length > 0, role != .plain else { return [] }

        var result: [SyntaxSpan] = []
        let start = range.location
        let end = range.location + range.length

        for lineIndex in 0..<lineStartOffsets.count {
            let lineStart = lineStartOffsets[lineIndex]
            let lineEnd = lineStart + lineLengths[lineIndex]
            if end <= lineStart || start >= lineEnd {
                continue
            }

            let lower = max(start, lineStart) - lineStart
            let upper = min(end, lineEnd) - lineStart
            guard lower < upper else { continue }
            result.append(SyntaxSpan(lineIndex: lineIndex, range: lower..<upper, role: role))
        }

        return result
    }
}
