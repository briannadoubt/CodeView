import DiffCore
import DiffRendering
import SyntaxCore

#if canImport(SwiftUI)
import SwiftUI

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public protocol CodeTextSurfaceRenderer: Sendable {
    associatedtype Body: View
    @ViewBuilder
    func render(
        surface: CodeTextSurfaceModel,
        onExpandHiddenContext: @escaping @MainActor @Sendable (HiddenContextBlock, HiddenContextAction) -> Void
    ) -> Body
}

public struct AnyCodeTextSurfaceRenderer: Sendable {
    private let builder: @Sendable (CodeTextSurfaceModel, @escaping @MainActor @Sendable (HiddenContextBlock, HiddenContextAction) -> Void) -> AnyView

    public init<R: CodeTextSurfaceRenderer>(_ renderer: R) {
        self.builder = { (surface: CodeTextSurfaceModel, onExpandHiddenContext: @escaping @MainActor @Sendable (HiddenContextBlock, HiddenContextAction) -> Void) in
            AnyView(renderer.render(surface: surface, onExpandHiddenContext: onExpandHiddenContext))
        }
    }

    public func render(
        surface: CodeTextSurfaceModel,
        onExpandHiddenContext: @escaping @MainActor @Sendable (HiddenContextBlock, HiddenContextAction) -> Void
    ) -> AnyView {
        builder(surface, onExpandHiddenContext)
    }
}

public struct DefaultCodeTextSurfaceRenderer: CodeTextSurfaceRenderer {
    public init() {}

    public func render(
        surface: CodeTextSurfaceModel,
        onExpandHiddenContext: @escaping @MainActor @Sendable (HiddenContextBlock, HiddenContextAction) -> Void
    ) -> some View {
        #if os(macOS)
        MacCodeTextSurfaceView(surface: surface, onExpandHiddenContext: onExpandHiddenContext)
            .frame(minHeight: 48)
        #else
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(surface.rows) { row in
                    mobileRowView(row, onExpandHiddenContext: onExpandHiddenContext)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(backgroundColor(for: row.backgroundStyle))
                }
            }
        }
        #endif
    }

    @ViewBuilder
    private func mobileRowView(
        _ row: DiffRenderableRow,
        onExpandHiddenContext: @escaping @MainActor @Sendable (HiddenContextBlock, HiddenContextAction) -> Void
    ) -> some View {
        switch row.kind {
        case .code:
            HStack(alignment: .top, spacing: 12) {
                Text(row.oldLineNumber.map(String.init) ?? "")
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
                Text(row.newLineNumber.map(String.init) ?? "")
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
                Text(verbatim: row.text.isEmpty ? " " : row.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        case let .hiddenContext(block):
            HStack(spacing: 8) {
                if let upControl = row.hiddenContextControls.first(where: { $0.action == .expandUp }) {
                    hiddenContextButton(upControl.title, action: {
                        Task { @MainActor in
                            onExpandHiddenContext(block, upControl.action)
                        }
                    })
                }

                if let allControl = row.hiddenContextControls.first(where: { $0.action == .expandAll }) {
                    Button(allControl.title) {
                        Task { @MainActor in
                            onExpandHiddenContext(block, allControl.action)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(Color.secondary.opacity(0.96))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(hiddenBarFillColor())
                    )
                }

                if let downControl = row.hiddenContextControls.first(where: { $0.action == .expandDown }) {
                    hiddenContextButton(downControl.title, action: {
                        Task { @MainActor in
                            onExpandHiddenContext(block, downControl.action)
                        }
                    })
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func backgroundColor(for style: DiffBackgroundStyle) -> some ShapeStyle {
        switch style {
        case .neutral:
            return Color.clear
        case .addition:
            return Color.green.opacity(0.12)
        case .deletion:
            return Color.red.opacity(0.12)
        case .hidden:
            return Color.clear
        }
    }

    @ViewBuilder
    private func hiddenContextButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(Color.secondary.opacity(0.96))
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(hiddenBarFillColor())
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func hiddenBarFillColor() -> Color {
        Color(white: 0.26)
    }
}

#if os(macOS)
private struct MacCodeTextSurfaceView: NSViewRepresentable {
    let surface: CodeTextSurfaceModel
    let onExpandHiddenContext: @MainActor @Sendable (HiddenContextBlock, HiddenContextAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onExpandHiddenContext: onExpandHiddenContext)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = IntrinsicHeightScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.verticalScrollElasticity = .none
        scrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textView = InteractiveDiffTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 10)
        textView.usesFindBar = true
        textView.allowsUndo = false
        textView.isRichText = true
        textView.importsGraphics = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.textContainer?.lineFragmentPadding = 0
        textView.hiddenContextDelegate = context.coordinator

        scrollView.onContentWidthChange = { [weak scrollView, weak textView] in
            guard let scrollView, let textView else { return }
            Self.remeasure(scrollView: scrollView, textView: textView)
        }
        scrollView.documentView = textView
        update(scrollView: scrollView, textView: textView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard
            let textView = scrollView.documentView as? InteractiveDiffTextView
        else { return }
        context.coordinator.onExpandHiddenContext = onExpandHiddenContext
        textView.hiddenContextDelegate = context.coordinator
        update(scrollView: scrollView, textView: textView, coordinator: context.coordinator)
    }

    private func update(scrollView: NSScrollView, textView: InteractiveDiffTextView, coordinator: Coordinator) {
        let renderState = makeAttributedString()
        textView.textStorage?.setAttributedString(renderState.attributedString)
        textView.hiddenActionRanges = renderState.hiddenActionRanges
        textView.selectableRanges = renderState.selectableRanges
        scrollView.hasHorizontalScroller = !surface.wrapsLines

        if let textContainer = textView.textContainer {
            if surface.wrapsLines {
                textContainer.widthTracksTextView = true
                textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
                textView.isHorizontallyResizable = false
                textView.autoresizingMask = [.width]
            } else {
                textContainer.widthTracksTextView = false
                textContainer.containerSize = NSSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                )
                textView.isHorizontallyResizable = true
                textView.autoresizingMask = []
            }
        }

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        Self.remeasure(scrollView: scrollView, textView: textView)
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private static func remeasure(scrollView: NSScrollView, textView: InteractiveDiffTextView) {
        guard let textContainer = textView.textContainer else {
            scrollView.invalidateIntrinsicContentSize()
            return
        }

        let targetWidth: CGFloat
        if textContainer.widthTracksTextView {
            targetWidth = max(scrollView.contentSize.width, 1)
            textContainer.containerSize = NSSize(width: targetWidth, height: .greatestFiniteMagnitude)
            textView.setFrameSize(NSSize(width: targetWidth, height: max(textView.frame.height, 48)))
        } else {
            targetWidth = max(textView.frame.width, scrollView.contentSize.width)
        }

        textView.sizeToFit()
        let contentHeight = measuredContentHeight(for: textView)
        textView.setFrameSize(
            NSSize(
                width: targetWidth,
                height: contentHeight
            )
        )
        scrollView.invalidateIntrinsicContentSize()
    }

    private static func measuredContentHeight(for textView: NSTextView) -> CGFloat {
        guard
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else {
            return max(textView.fittingSize.height, 48)
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return max(ceil(usedRect.height + (textView.textContainerInset.height * 2)), 48)
    }

    private func makeAttributedString() -> RenderState {
        let full = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = surface.wrapsLines ? .byWordWrapping : .byClipping
        var actionRanges: [(HiddenContextInteraction, NSRange)] = []
        var selectableRanges: [NSRange] = []
        var location = 0

        for (index, row) in surface.rows.enumerated() {
            let prefix = gutterPrefix(for: row)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
                .backgroundColor: backgroundColor(for: row.backgroundStyle)
            ]
            let mutableLine = NSMutableAttributedString(
                string: prefix + (row.text.isEmpty ? " " : row.text),
                attributes: attributes
            )

            let gutterRange = NSRange(location: 0, length: prefix.count)
            mutableLine.addAttributes([
                .foregroundColor: NSColor.secondaryLabelColor
            ], range: gutterRange)

            switch row.kind {
            case .code:
                let codeStart = location + prefix.utf16.count
                let codeLength = max((row.text.isEmpty ? " " : row.text).utf16.count, 1)
                selectableRanges.append(NSRange(location: codeStart, length: codeLength))
                for span in row.syntaxSpans {
                    let shiftedRange = NSRange(location: prefix.count + span.range.lowerBound, length: span.range.count)
                    guard shiftedRange.location + shiftedRange.length <= mutableLine.length else { continue }
                    mutableLine.addAttributes([
                        .foregroundColor: syntaxColor(for: span.role)
                    ], range: shiftedRange)
                }
            case let .hiddenContext(block):
                mutableLine.mutableString.setString(prefix)
                let baseAttributes = attributes.merging([
                    .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.96)
                ]) { _, new in new }

                for control in row.hiddenContextControls {
                    let start = mutableLine.length
                    let token: String
                    let tokenAttributes: [NSAttributedString.Key: Any]

                    switch control.action {
                    case .expandUp, .expandDown:
                        token = " \(control.title) "
                        tokenAttributes = baseAttributes.merging([
                            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                            .backgroundColor: hiddenBarFillColor()
                        ]) { _, new in new }
                    case .expandAll:
                        token = "  \(control.title)  "
                        tokenAttributes = baseAttributes.merging([
                            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                            .backgroundColor: hiddenBarFillColor()
                        ]) { _, new in new }
                    }

                    mutableLine.append(NSAttributedString(string: token, attributes: tokenAttributes))
                    let range = NSRange(location: location + start, length: token.utf16.count)
                    actionRanges.append((HiddenContextInteraction(block: block, action: control.action), range))
                    mutableLine.append(NSAttributedString(string: " ", attributes: baseAttributes))
                }
            }

            full.append(mutableLine)
            location += mutableLine.length
            if index < surface.rows.count - 1 {
                full.append(NSAttributedString(string: "\n"))
                if case .code = row.kind {
                    selectableRanges.append(NSRange(location: location, length: 1))
                }
                location += 1
            }
        }

        return RenderState(
            attributedString: full,
            hiddenActionRanges: actionRanges,
            selectableRanges: selectableRanges
        )
    }

    private func gutterPrefix(for row: DiffRenderableRow) -> String {
        if row.isInlineHiddenContextControl {
            return "  "
        }
        let oldNumber = row.oldLineNumber.map { String(format: "%4d", $0) } ?? "    "
        let newNumber = row.newLineNumber.map { String(format: "%4d", $0) } ?? "    "
        return "\(oldNumber) \(newNumber)  "
    }

    private func backgroundColor(for style: DiffBackgroundStyle) -> NSColor {
        switch style {
        case .neutral:
            return .clear
        case .addition:
            return NSColor.systemGreen.withAlphaComponent(0.12)
        case .deletion:
            return NSColor.systemRed.withAlphaComponent(0.12)
        case .hidden:
            return .clear
        }
    }

    private func hiddenBarFillColor() -> NSColor {
        NSColor(white: 0.26, alpha: 1)
    }

    private func syntaxColor(for role: SyntaxRole) -> NSColor {
        switch role {
        case .keyword:
            return NSColor.systemOrange
        case .string:
            return NSColor.systemTeal
        case .number:
            return NSColor.systemPurple
        case .comment:
            return NSColor.secondaryLabelColor
        case .type:
            return NSColor.systemBlue
        case .plain:
            return NSColor.labelColor
        }
    }

    @MainActor
    final class Coordinator: NSObject, HiddenContextTextViewDelegate {
        fileprivate var onExpandHiddenContext: @MainActor @Sendable (HiddenContextBlock, HiddenContextAction) -> Void

        init(onExpandHiddenContext: @escaping @MainActor @Sendable (HiddenContextBlock, HiddenContextAction) -> Void) {
            self.onExpandHiddenContext = onExpandHiddenContext
        }

        func expandHiddenContext(_ interaction: HiddenContextInteraction) {
            onExpandHiddenContext(interaction.block, interaction.action)
        }
    }

    private struct RenderState {
        let attributedString: NSAttributedString
        let hiddenActionRanges: [(HiddenContextInteraction, NSRange)]
        let selectableRanges: [NSRange]
    }

    fileprivate struct HiddenContextInteraction {
        let block: HiddenContextBlock
        let action: HiddenContextAction
    }
}

@MainActor
private protocol HiddenContextTextViewDelegate: AnyObject {
    func expandHiddenContext(_ interaction: MacCodeTextSurfaceView.HiddenContextInteraction)
}

private final class InteractiveDiffTextView: NSTextView {
    weak var hiddenContextDelegate: (any HiddenContextTextViewDelegate)?
    var hiddenActionRanges: [(MacCodeTextSurfaceView.HiddenContextInteraction, NSRange)] = []
    var selectableRanges: [NSRange] = []

    override func mouseDown(with event: NSEvent) {
        guard let interaction = clickedHiddenContextInteraction(for: event) else {
            super.mouseDown(with: event)
            return
        }

        let downPoint = convert(event.locationInWindow, from: nil)
        guard let nextEvent = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else {
            hiddenContextDelegate?.expandHiddenContext(interaction)
            return
        }

        switch nextEvent.type {
        case .leftMouseDragged:
            super.mouseDown(with: event)
        case .leftMouseUp:
            let upPoint = convert(nextEvent.locationInWindow, from: nil)
            if hypot(upPoint.x - downPoint.x, upPoint.y - downPoint.y) < 4 {
                hiddenContextDelegate?.expandHiddenContext(interaction)
            } else {
                super.mouseDown(with: event)
            }
        default:
            super.mouseDown(with: event)
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        let clampedRanges = ranges.compactMap { value in
            clampSelectionRange(value.rangeValue)
        }
        let finalRanges = clampedRanges.isEmpty ? [NSValue(range: NSRange(location: 0, length: 0))] : clampedRanges.map(NSValue.init)
        super.setSelectedRanges(finalRanges, affinity: affinity, stillSelecting: stillSelectingFlag)
    }

    private func clickedHiddenContextInteraction(for event: NSEvent) -> MacCodeTextSurfaceView.HiddenContextInteraction? {
        guard
            let layoutManager,
            let textContainer
        else { return nil }

        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        return hiddenActionRanges.first(where: { NSLocationInRange(characterIndex, $0.1) })?.0
    }

    private func clampSelectionRange(_ proposedRange: NSRange) -> NSRange? {
        guard proposedRange.length > 0 else { return proposedRange }

        var lowerBound = Int.max
        var upperBound = Int.min

        for allowedRange in selectableRanges {
            let intersection = NSIntersectionRange(proposedRange, allowedRange)
            guard intersection.length > 0 else { continue }
            lowerBound = min(lowerBound, intersection.location)
            upperBound = max(upperBound, intersection.location + intersection.length)
        }

        guard lowerBound != Int.max, upperBound > lowerBound else { return nil }
        return NSRange(location: lowerBound, length: upperBound - lowerBound)
    }
}

private final class IntrinsicHeightScrollView: NSScrollView {
    var onContentWidthChange: (() -> Void)?
    private var lastObservedContentWidth = CGFloat.nan

    override func layout() {
        super.layout()

        let contentWidth = contentSize.width
        guard lastObservedContentWidth.isNaN || abs(contentWidth - lastObservedContentWidth) > 0.5 else {
            return
        }

        lastObservedContentWidth = contentWidth
        onContentWidthChange?()
    }

    override var intrinsicContentSize: NSSize {
        guard let documentView else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 48)
        }

        var height = max(documentView.fittingSize.height, 48)
        if hasHorizontalScroller {
            height += horizontalScroller?.frame.height ?? 0
        }

        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }
}
#endif
#else
public protocol CodeTextSurfaceRenderer: Sendable {}

public struct AnyCodeTextSurfaceRenderer: Sendable {
    public init<R: CodeTextSurfaceRenderer>(_ renderer: R) {}
}

public struct DefaultCodeTextSurfaceRenderer: CodeTextSurfaceRenderer {
    public init() {}
}
#endif
