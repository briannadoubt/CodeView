import DiffRendering
import DiffState
import Foundation

struct CodeTextSurfaceLayout: Hashable, Sendable {
    enum Item: Hashable, Identifiable, Sendable {
        case segment(CodeTextSegment)
        case hiddenContext(DiffRenderableRow)

        var id: String {
            switch self {
            case let .segment(segment):
                return segment.id
            case let .hiddenContext(row):
                return row.id
            }
        }
    }

    let surface: CodeTextSurfaceModel
    let gutterDigits: Int
    let items: [Item]

    init(surface: CodeTextSurfaceModel) {
        self.surface = surface
        let gutterDigits = max(
            4,
            surface.rows.reduce(0) { current, row in
                max(current, max(Self.digitCount(for: row.oldLineNumber), Self.digitCount(for: row.newLineNumber)))
            }
        )
        self.gutterDigits = gutterDigits

        var items: [Item] = []
        var currentRows: [DiffRenderableRow] = []
        var segmentIndex = 0

        func flushSegment() {
            guard currentRows.isEmpty == false else { return }
            items.append(
                .segment(
                    CodeTextSegment(
                        id: "\(surface.id)-segment-\(segmentIndex)",
                        surface: surface,
                        rows: currentRows,
                        gutterDigits: gutterDigits
                    )
                )
            )
            currentRows.removeAll(keepingCapacity: true)
            segmentIndex += 1
        }

        for row in surface.rows {
            switch row.kind {
            case .code:
                currentRows.append(row)
            case .hiddenContext:
                flushSegment()
                items.append(.hiddenContext(row))
            }
        }

        flushSegment()
        self.items = items
    }

    private static func digitCount(for number: Int?) -> Int {
        guard let number else { return 0 }
        return String(number).count
    }
}

struct CodeTextSegment: Hashable, Identifiable, Sendable {
    struct Line: Hashable, Sendable {
        let row: DiffRenderableRow
        let sourceUTF16Length: Int
        let displayRange: NSRange
        let newlineRange: NSRange?
    }

    let id: String
    let side: CodeTextSurfaceModel.Side
    let wrapsLines: Bool
    let gutterDigits: Int
    let text: String
    let lines: [Line]

    init(
        id: String,
        surface: CodeTextSurfaceModel,
        rows: [DiffRenderableRow],
        gutterDigits: Int
    ) {
        self.id = id
        self.side = surface.side
        self.wrapsLines = surface.wrapsLines
        self.gutterDigits = gutterDigits

        var lines: [Line] = []
        var text = ""
        var location = 0

        for (index, row) in rows.enumerated() {
            let displayText = Self.displayText(for: row)
            let displayLength = (displayText as NSString).length
            let displayRange = NSRange(location: location, length: displayLength)

            text.append(displayText)
            location += displayLength

            let newlineRange: NSRange?
            if index < rows.count - 1 {
                newlineRange = NSRange(location: location, length: 1)
                text.append("\n")
                location += 1
            } else {
                newlineRange = nil
            }

            lines.append(
                Line(
                    row: row,
                    sourceUTF16Length: (row.text as NSString).length,
                    displayRange: displayRange,
                    newlineRange: newlineRange
                )
            )
        }

        self.text = text
        self.lines = lines
    }

    var totalUTF16Length: Int {
        (text as NSString).length
    }

    func gutterText(for row: DiffRenderableRow) -> String {
        let oldNumber = row.oldLineNumber.map { String(format: "%\(gutterDigits)d", $0) } ?? String(repeating: " ", count: gutterDigits)
        let newNumber = row.newLineNumber.map { String(format: "%\(gutterDigits)d", $0) } ?? String(repeating: " ", count: gutterDigits)
        return "\(oldNumber) \(newNumber)"
    }

    func selection(for range: NSRange) -> DiffTextSelection? {
        guard let clampedRange = clampedSelectionRange(range) else { return nil }
        guard
            let anchor = position(at: clampedRange.location),
            let focus = position(at: clampedRange.location + clampedRange.length)
        else {
            return nil
        }

        return DiffTextSelection(
            surface: side.selectionSurface,
            anchor: anchor,
            focus: focus
        )
    }

    func sanitizedText(in range: NSRange) -> String {
        guard let clampedRange = clampedSelectionRange(range) else { return "" }
        guard clampedRange.length > 0 else { return "" }

        var output = ""

        for line in lines {
            let lineIntersection = NSIntersectionRange(clampedRange, line.displayRange)
            if lineIntersection.length > 0, line.sourceUTF16Length > 0 {
                let localRange = NSRange(
                    location: lineIntersection.location - line.displayRange.location,
                    length: lineIntersection.length
                )
                output.append((line.row.text as NSString).substring(with: localRange))
            }

            if let newlineRange = line.newlineRange, NSIntersectionRange(clampedRange, newlineRange).length > 0 {
                output.append("\n")
            }
        }

        return output
    }

    private func clampedSelectionRange(_ range: NSRange) -> NSRange? {
        let bounds = NSRange(location: 0, length: totalUTF16Length)
        guard range.location != NSNotFound else { return nil }

        let clampedLocation = max(bounds.location, min(range.location, bounds.length))
        let unclampedUpperBound = range.location + max(range.length, 0)
        let clampedUpperBound = max(bounds.location, min(unclampedUpperBound, bounds.length))
        return NSRange(location: clampedLocation, length: max(clampedUpperBound - clampedLocation, 0))
    }

    private func position(at utf16Offset: Int) -> DiffTextSelection.Position? {
        guard let firstLine = lines.first else { return nil }
        let clampedOffset = max(0, min(utf16Offset, totalUTF16Length))

        for (index, line) in lines.enumerated() {
            let lowerBound = line.displayRange.location
            let upperBound = line.displayRange.location + line.displayRange.length

            if clampedOffset < upperBound {
                return DiffTextSelection.Position(
                    rowID: line.row.id,
                    utf16Offset: min(clampedOffset - lowerBound, line.sourceUTF16Length)
                )
            }

            if clampedOffset == upperBound {
                if let nextLine = lines[safe: index + 1] {
                    return DiffTextSelection.Position(rowID: nextLine.row.id, utf16Offset: 0)
                }

                return DiffTextSelection.Position(
                    rowID: line.row.id,
                    utf16Offset: line.sourceUTF16Length
                )
            }

            if let newlineRange = line.newlineRange, NSLocationInRange(clampedOffset, newlineRange) {
                if let nextLine = lines[safe: index + 1] {
                    return DiffTextSelection.Position(rowID: nextLine.row.id, utf16Offset: 0)
                }
            }
        }

        return DiffTextSelection.Position(
            rowID: firstLine.row.id,
            utf16Offset: 0
        )
    }

    private static func displayText(for row: DiffRenderableRow) -> String {
        row.text.isEmpty ? " " : row.text
    }
}

private extension CodeTextSurfaceModel.Side {
    var selectionSurface: DiffTextSelection.Surface {
        switch self {
        case .unified:
            return .unified
        case .left:
            return .left
        case .right:
            return .right
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
