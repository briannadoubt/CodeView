import DiffCore
import DiffRendering
import DiffState
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
    @MainActor
    @ViewBuilder
    func render(
        surface: CodeTextSurfaceModel,
        onSelectionChanged: @escaping @MainActor @Sendable (DiffTextSelection?) -> Void,
        onExpandHiddenContext: @escaping @MainActor @Sendable (HiddenContextBlock, HiddenContextAction) -> Void
    ) -> Body
}

public extension CodeTextSurfaceRenderer {
    @MainActor
    @ViewBuilder
    func render(
        surface: CodeTextSurfaceModel,
        onExpandHiddenContext: @escaping @MainActor @Sendable (HiddenContextBlock, HiddenContextAction) -> Void
    ) -> some View {
        render(
            surface: surface,
            onSelectionChanged: { _ in },
            onExpandHiddenContext: onExpandHiddenContext
        )
    }
}

public struct AnyCodeTextSurfaceRenderer: Sendable {
    private let builder: @MainActor @Sendable (
        CodeTextSurfaceModel,
        @escaping @MainActor @Sendable (DiffTextSelection?) -> Void,
        @escaping @MainActor @Sendable (HiddenContextBlock, HiddenContextAction) -> Void
    ) -> AnyView

    public init<R: CodeTextSurfaceRenderer>(_ renderer: R) {
        self.builder = {
            (surface: CodeTextSurfaceModel,
             onSelectionChanged: @escaping @MainActor @Sendable (DiffTextSelection?) -> Void,
             onExpandHiddenContext: @escaping @MainActor @Sendable (HiddenContextBlock, HiddenContextAction) -> Void) in
            AnyView(
                renderer.render(
                    surface: surface,
                    onSelectionChanged: onSelectionChanged,
                    onExpandHiddenContext: onExpandHiddenContext
                )
            )
        }
    }

    @MainActor
    public func render(
        surface: CodeTextSurfaceModel,
        onSelectionChanged: @escaping @MainActor @Sendable (DiffTextSelection?) -> Void,
        onExpandHiddenContext: @escaping @MainActor @Sendable (HiddenContextBlock, HiddenContextAction) -> Void
    ) -> AnyView {
        builder(surface, onSelectionChanged, onExpandHiddenContext)
    }

    @MainActor
    public func render(
        surface: CodeTextSurfaceModel,
        onExpandHiddenContext: @escaping @MainActor @Sendable (HiddenContextBlock, HiddenContextAction) -> Void
    ) -> AnyView {
        builder(surface, { _ in }, onExpandHiddenContext)
    }

}

public struct DefaultCodeTextSurfaceRenderer: CodeTextSurfaceRenderer {
    public init() {}

    @MainActor
    public func render(
        surface: CodeTextSurfaceModel,
        onSelectionChanged: @escaping @MainActor @Sendable (DiffTextSelection?) -> Void,
        onExpandHiddenContext: @escaping @MainActor @Sendable (HiddenContextBlock, HiddenContextAction) -> Void
    ) -> some View {
        SegmentedCodeTextSurfaceView(
            surface: surface,
            onSelectionChanged: onSelectionChanged,
            onExpandHiddenContext: onExpandHiddenContext
        )
        .frame(minHeight: CodeSurfaceMetrics.minimumHeight)
    }
}

private enum CodeSurfaceMetrics {
    static let minimumHeight: CGFloat = 48
    static let fontSize: CGFloat = 13
    static let hiddenButtonCornerRadius: CGFloat = 10
    static let hiddenButtonSize: CGFloat = 38
    static let hiddenControlSpacing: CGFloat = 8
    static let hiddenRowLeading: CGFloat = 6
    static let hiddenRowTrailing: CGFloat = 10
    static let hiddenRowVertical: CGFloat = 3
    static let gutterLeadingPadding: CGFloat = 8
    static let gutterTrailingPadding: CGFloat = 12
    static let textHorizontalPadding: CGFloat = 8
    static let textVerticalInset: CGFloat = 8
}

private struct SegmentedCodeTextSurfaceView: View {
    let layout: CodeTextSurfaceLayout
    let onSelectionChanged: @MainActor @Sendable (DiffTextSelection?) -> Void
    let onExpandHiddenContext: @MainActor @Sendable (HiddenContextBlock, HiddenContextAction) -> Void

    init(
        surface: CodeTextSurfaceModel,
        onSelectionChanged: @escaping @MainActor @Sendable (DiffTextSelection?) -> Void,
        onExpandHiddenContext: @escaping @MainActor @Sendable (HiddenContextBlock, HiddenContextAction) -> Void
    ) {
        self.layout = CodeTextSurfaceLayout(surface: surface)
        self.onSelectionChanged = onSelectionChanged
        self.onExpandHiddenContext = onExpandHiddenContext
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(layout.items) { item in
                switch item {
                case let .segment(segment):
                    platformSegmentView(segment)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case let .hiddenContext(row):
                    hiddenContextRowView(row)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func platformSegmentView(_ segment: CodeTextSegment) -> some View {
        #if os(macOS)
        MacCodeTextSegmentView(
            segment: segment,
            onSelectionChanged: onSelectionChanged
        )
        #else
        UIKitCodeTextSegmentView(
            segment: segment,
            onSelectionChanged: onSelectionChanged
        )
        #endif
    }

    @ViewBuilder
    private func hiddenContextRowView(_ row: DiffRenderableRow) -> some View {
        if case let .hiddenContext(block) = row.kind {
            HStack(spacing: CodeSurfaceMetrics.hiddenControlSpacing) {
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
                        RoundedRectangle(cornerRadius: CodeSurfaceMetrics.hiddenButtonCornerRadius, style: .continuous)
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
            .padding(.leading, CodeSurfaceMetrics.hiddenRowLeading)
            .padding(.trailing, CodeSurfaceMetrics.hiddenRowTrailing)
            .padding(.vertical, CodeSurfaceMetrics.hiddenRowVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func hiddenContextButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(Color.secondary.opacity(0.96))
                .frame(
                    width: CodeSurfaceMetrics.hiddenButtonSize,
                    height: CodeSurfaceMetrics.hiddenButtonSize
                )
                .background(
                    RoundedRectangle(cornerRadius: CodeSurfaceMetrics.hiddenButtonCornerRadius, style: .continuous)
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
private struct MacCodeTextSegmentView: NSViewRepresentable {
    let segment: CodeTextSegment
    let onSelectionChanged: @MainActor @Sendable (DiffTextSelection?) -> Void

    func makeNSView(context: Context) -> MacCodeTextSegmentContainerView {
        MacCodeTextSegmentContainerView()
    }

    func updateNSView(_ nsView: MacCodeTextSegmentContainerView, context: Context) {
        nsView.update(segment: segment, onSelectionChanged: onSelectionChanged)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: MacCodeTextSegmentContainerView,
        context: Context
    ) -> CGSize? {
        nsView.fittingSize(for: proposal.width)
    }
}

private final class MacCodeTextSegmentContainerView: NSView {
    private let gutterView = MacCodeTextGutterView()
    private let scrollView = NSScrollView()
    private let textView = MacSelectableCodeTextView(frame: .zero)

    private var segment: CodeTextSegment?
    private var selectionHandler: (@MainActor @Sendable (DiffTextSelection?) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUpViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        fittingSize(for: bounds.width > 0 ? bounds.width : nil)
    }

    func update(
        segment: CodeTextSegment,
        onSelectionChanged: @escaping @MainActor @Sendable (DiffTextSelection?) -> Void
    ) {
        self.segment = segment
        self.selectionHandler = onSelectionChanged
        textView.segment = segment
        textView.selectionRangeChanged = { [weak self] range in
            guard let self, let segment = self.segment else { return }
            let selection = segment.selection(for: range)
            Task { @MainActor in
                self.selectionHandler?(selection)
            }
        }
        textView.textStorage?.setAttributedString(Self.attributedString(for: segment))
        gutterView.segment = segment
        gutterView.textView = textView
        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    func fittingSize(for proposedWidth: CGFloat?) -> CGSize {
        applyLayout(proposedWidth: proposedWidth, updatingFrames: false)
    }

    override func layout() {
        super.layout()
        _ = applyLayout(proposedWidth: bounds.width, updatingFrames: true)
    }

    private func setUpViews() {
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = textView

        textView.isEditable = false
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.drawsBackground = false
        textView.usesFindBar = true
        textView.allowsUndo = false
        textView.isRichText = true
        textView.importsGraphics = false
        textView.textContainerInset = NSSize(width: 0, height: CodeSurfaceMetrics.textVerticalInset)
        textView.textContainer?.lineFragmentPadding = CodeSurfaceMetrics.textHorizontalPadding

        addSubview(gutterView)
        addSubview(scrollView)
    }

    private func applyLayout(proposedWidth: CGFloat?, updatingFrames: Bool) -> CGSize {
        guard let segment, let textContainer = textView.textContainer else {
            return NSSize(width: proposedWidth ?? 0, height: CodeSurfaceMetrics.minimumHeight)
        }

        let gutterWidth = Self.gutterWidth(for: segment)
        let proposedTotalWidth = max(proposedWidth ?? gutterWidth + CodeSurfaceMetrics.minimumHeight, gutterWidth + 1)
        let availableTextWidth = max(proposedTotalWidth - gutterWidth, 1)

        if segment.wrapsLines {
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(width: availableTextWidth, height: .greatestFiniteMagnitude)
            textView.isHorizontallyResizable = false
            scrollView.hasHorizontalScroller = false
        } else {
            textContainer.widthTracksTextView = false
            textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            textView.isHorizontallyResizable = true
            scrollView.hasHorizontalScroller = true
        }

        textView.setFrameSize(NSSize(width: availableTextWidth, height: max(textView.frame.height, CodeSurfaceMetrics.minimumHeight)))
        textView.layoutManager?.ensureLayout(for: textContainer)

        let contentWidth = max(Self.contentWidth(for: textView), availableTextWidth)
        let contentHeight = max(Self.contentHeight(for: textView), CodeSurfaceMetrics.minimumHeight)
        let textWidth = segment.wrapsLines ? availableTextWidth : contentWidth
        let scrollerHeight = scrollView.hasHorizontalScroller ? Self.horizontalScrollerHeight(for: scrollView) : 0
        let totalHeight = max(contentHeight + scrollerHeight, CodeSurfaceMetrics.minimumHeight)

        if updatingFrames {
            gutterView.frame = NSRect(x: 0, y: 0, width: gutterWidth, height: totalHeight)
            scrollView.frame = NSRect(
                x: gutterWidth,
                y: 0,
                width: max(bounds.width - gutterWidth, 1),
                height: totalHeight
            )
            textView.setFrameSize(NSSize(width: textWidth, height: contentHeight))

            let currentOrigin = scrollView.contentView.bounds.origin
            let maxHorizontalOffset = max(textWidth - scrollView.contentSize.width, 0)
            scrollView.contentView.scroll(
                to: NSPoint(x: min(currentOrigin.x, maxHorizontalOffset), y: 0)
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
            gutterView.needsDisplay = true
        }

        return NSSize(width: proposedTotalWidth, height: totalHeight)
    }

    private static func attributedString(for segment: CodeTextSegment) -> NSAttributedString {
        let full = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = segment.wrapsLines ? .byWordWrapping : .byClipping

        for (index, line) in segment.lines.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: codeFont(),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
            let mutableLine = NSMutableAttributedString(
                string: line.row.text.isEmpty ? " " : line.row.text,
                attributes: attributes
            )

            for span in line.row.syntaxSpans {
                let shiftedRange = NSRange(location: span.range.lowerBound, length: span.range.count)
                guard shiftedRange.location + shiftedRange.length <= mutableLine.length else { continue }
                mutableLine.addAttributes([
                    .foregroundColor: syntaxColor(for: span.role)
                ], range: shiftedRange)
            }

            full.append(mutableLine)
            if index < segment.lines.count - 1 {
                full.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }

        return full
    }

    private static func codeFont() -> NSFont {
        NSFont.monospacedSystemFont(ofSize: CodeSurfaceMetrics.fontSize, weight: .regular)
    }

    private static func syntaxColor(for role: SyntaxRole) -> NSColor {
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

    private static func gutterWidth(for segment: CodeTextSegment) -> CGFloat {
        let sample = String(repeating: "8", count: segment.gutterDigits) + " " + String(repeating: "8", count: segment.gutterDigits)
        let sampleWidth = (sample as NSString).size(withAttributes: [.font: codeFont()]).width
        return ceil(sampleWidth + CodeSurfaceMetrics.gutterLeadingPadding + CodeSurfaceMetrics.gutterTrailingPadding)
    }

    private static func contentWidth(for textView: NSTextView) -> CGFloat {
        guard
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else {
            return max(textView.fittingSize.width, CodeSurfaceMetrics.minimumHeight)
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return ceil(usedRect.width + (textContainer.lineFragmentPadding * 2))
    }

    private static func contentHeight(for textView: NSTextView) -> CGFloat {
        guard
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else {
            return max(textView.fittingSize.height, CodeSurfaceMetrics.minimumHeight)
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return ceil(usedRect.height + (textView.textContainerInset.height * 2))
    }

    private static func horizontalScrollerHeight(for scrollView: NSScrollView) -> CGFloat {
        NSScroller.scrollerWidth(for: .regular, scrollerStyle: scrollView.scrollerStyle)
    }
}

private final class MacSelectableCodeTextView: NSTextView {
    var segment: CodeTextSegment?
    var selectionRangeChanged: ((NSRange) -> Void)?

    override func drawBackground(in rect: NSRect) {
        drawLineBackgrounds()
        super.drawBackground(in: rect)
    }

    override func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting stillSelectingFlag: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        selectionRangeChanged?(selectedRange())
    }

    override func copy(_ sender: Any?) {
        guard let segment else {
            super.copy(sender)
            return
        }

        let selectedText = segment.sanitizedText(in: selectedRange())
        guard selectedRange().length > 0 else {
            super.copy(sender)
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedText, forType: .string)
    }

    func rect(for line: CodeTextSegment.Line) -> NSRect? {
        guard
            let layoutManager,
            let textContainer
        else {
            return nil
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: line.displayRange, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerInset.width
        rect.origin.y += textContainerInset.height
        return rect.integral
    }

    private func drawLineBackgrounds() {
        guard let segment else { return }

        for line in segment.lines {
            guard let lineRect = rect(for: line) else { continue }
            let backgroundRect = NSRect(x: 0, y: lineRect.minY, width: bounds.width, height: lineRect.height)
            Self.backgroundColor(for: line.row.backgroundStyle).setFill()
            backgroundRect.fill()
        }
    }

    fileprivate static func backgroundColor(for style: DiffBackgroundStyle) -> NSColor {
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
}

private final class MacCodeTextGutterView: NSView {
    weak var textView: MacSelectableCodeTextView?
    var segment: CodeTextSegment? {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let segment, let textView else { return }

        let font = NSFont.monospacedSystemFont(ofSize: CodeSurfaceMetrics.fontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        for line in segment.lines {
            guard let lineRect = textView.rect(for: line) else { continue }
            let backgroundRect = NSRect(x: 0, y: lineRect.minY, width: bounds.width, height: lineRect.height)
            MacSelectableCodeTextView.backgroundColor(for: line.row.backgroundStyle).setFill()
            backgroundRect.fill()

            let label = segment.gutterText(for: line.row)
            let textSize = (label as NSString).size(withAttributes: attributes)
            let drawPoint = NSPoint(
                x: bounds.width - CodeSurfaceMetrics.gutterTrailingPadding - textSize.width,
                y: lineRect.minY + max((lineRect.height - textSize.height) * 0.5, 0)
            )
            (label as NSString).draw(at: drawPoint, withAttributes: attributes)
        }
    }
}
#elseif canImport(UIKit)
private struct UIKitCodeTextSegmentView: UIViewRepresentable {
    let segment: CodeTextSegment
    let onSelectionChanged: @MainActor @Sendable (DiffTextSelection?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectionChanged: onSelectionChanged)
    }

    func makeUIView(context: Context) -> UIKitCodeTextSegmentContainerView {
        let view = UIKitCodeTextSegmentContainerView()
        view.textView.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: UIKitCodeTextSegmentContainerView, context: Context) {
        context.coordinator.onSelectionChanged = onSelectionChanged
        uiView.textView.delegate = context.coordinator
        uiView.update(segment: segment)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UIKitCodeTextSegmentContainerView,
        context: Context
    ) -> CGSize? {
        uiView.fittingSize(for: proposal.width)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onSelectionChanged: @MainActor @Sendable (DiffTextSelection?) -> Void

        init(onSelectionChanged: @escaping @MainActor @Sendable (DiffTextSelection?) -> Void) {
            self.onSelectionChanged = onSelectionChanged
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard
                let textView = textView as? UIKitSelectableCodeTextView,
                let segment = textView.segment
            else { return }

            let selection = segment.selection(for: textView.selectedRange)
            Task { @MainActor in
                onSelectionChanged(selection)
            }
        }
    }
}

private final class UIKitCodeTextSegmentContainerView: UIView {
    let gutterView = UIKitCodeTextGutterView()
    let textView = UIKitSelectableCodeTextView()

    private var segment: CodeTextSegment?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(segment: CodeTextSegment) {
        self.segment = segment
        textView.segment = segment
        textView.attributedText = Self.attributedString(for: segment)
        gutterView.segment = segment
        gutterView.textView = textView
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        fittingSize(for: bounds.width > 0 ? bounds.width : nil)
    }

    func fittingSize(for proposedWidth: CGFloat?) -> CGSize {
        applyLayout(proposedWidth: proposedWidth, updatingFrames: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        _ = applyLayout(proposedWidth: bounds.width, updatingFrames: true)
    }

    private func setUpViews() {
        addSubview(gutterView)
        addSubview(textView)

        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(
            top: CodeSurfaceMetrics.textVerticalInset,
            left: 0,
            bottom: CodeSurfaceMetrics.textVerticalInset,
            right: 0
        )
        textView.textContainer.lineFragmentPadding = CodeSurfaceMetrics.textHorizontalPadding
        textView.showsVerticalScrollIndicator = false
        textView.alwaysBounceVertical = false
        textView.autocorrectionType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.textDragInteraction?.isEnabled = true
    }

    private func applyLayout(proposedWidth: CGFloat?, updatingFrames: Bool) -> CGSize {
        guard let segment else {
            return CGSize(width: proposedWidth ?? 0, height: CodeSurfaceMetrics.minimumHeight)
        }

        let gutterWidth = Self.gutterWidth(for: segment)
        let proposedTotalWidth = max(proposedWidth ?? gutterWidth + CodeSurfaceMetrics.minimumHeight, gutterWidth + 1)
        let availableTextWidth = max(proposedTotalWidth - gutterWidth, 1)

        if segment.wrapsLines {
            textView.isScrollEnabled = false
            textView.showsHorizontalScrollIndicator = false
            textView.textContainer.widthTracksTextView = true
            textView.textContainer.size = CGSize(width: availableTextWidth, height: .greatestFiniteMagnitude)
        } else {
            textView.isScrollEnabled = true
            textView.showsHorizontalScrollIndicator = true
            textView.alwaysBounceHorizontal = true
            textView.textContainer.widthTracksTextView = false
            textView.textContainer.size = CGSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        }

        textView.frame = CGRect(x: gutterWidth, y: 0, width: availableTextWidth, height: max(textView.frame.height, CodeSurfaceMetrics.minimumHeight))
        textView.layoutManager.ensureLayout(for: textView.textContainer)

        let contentHeight = max(Self.contentHeight(for: textView), CodeSurfaceMetrics.minimumHeight)

        if updatingFrames {
            gutterView.frame = CGRect(x: 0, y: 0, width: gutterWidth, height: contentHeight)
            textView.frame = CGRect(x: gutterWidth, y: 0, width: availableTextWidth, height: contentHeight)
            gutterView.setNeedsDisplay()
        }

        return CGSize(width: proposedTotalWidth, height: contentHeight)
    }

    private static func attributedString(for segment: CodeTextSegment) -> NSAttributedString {
        let full = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = segment.wrapsLines ? .byWordWrapping : .byClipping

        for (index, line) in segment.lines.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: codeFont(),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph
            ]
            let mutableLine = NSMutableAttributedString(
                string: line.row.text.isEmpty ? " " : line.row.text,
                attributes: attributes
            )

            for span in line.row.syntaxSpans {
                let shiftedRange = NSRange(location: span.range.lowerBound, length: span.range.count)
                guard shiftedRange.location + shiftedRange.length <= mutableLine.length else { continue }
                mutableLine.addAttributes([
                    .foregroundColor: syntaxColor(for: span.role)
                ], range: shiftedRange)
            }

            full.append(mutableLine)
            if index < segment.lines.count - 1 {
                full.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }

        return full
    }

    private static func codeFont() -> UIFont {
        UIFont.monospacedSystemFont(ofSize: CodeSurfaceMetrics.fontSize, weight: .regular)
    }

    private static func syntaxColor(for role: SyntaxRole) -> UIColor {
        switch role {
        case .keyword:
            return .systemOrange
        case .string:
            return .systemTeal
        case .number:
            return .systemPurple
        case .comment:
            return .secondaryLabel
        case .type:
            return .systemBlue
        case .plain:
            return .label
        }
    }

    private static func gutterWidth(for segment: CodeTextSegment) -> CGFloat {
        let sample = String(repeating: "8", count: segment.gutterDigits) + " " + String(repeating: "8", count: segment.gutterDigits)
        let sampleWidth = (sample as NSString).size(withAttributes: [.font: codeFont()]).width
        return ceil(sampleWidth + CodeSurfaceMetrics.gutterLeadingPadding + CodeSurfaceMetrics.gutterTrailingPadding)
    }

    private static func contentHeight(for textView: UITextView) -> CGFloat {
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        let usedRect = textView.layoutManager.usedRect(for: textView.textContainer)
        return ceil(usedRect.height + textView.textContainerInset.top + textView.textContainerInset.bottom)
    }
}

private final class UIKitSelectableCodeTextView: UITextView {
    var segment: CodeTextSegment?

    override func draw(_ rect: CGRect) {
        drawLineBackgrounds()
        super.draw(rect)
    }

    override func copy(_ sender: Any?) {
        guard let segment else {
            super.copy(sender)
            return
        }

        guard selectedRange.length > 0 else {
            super.copy(sender)
            return
        }

        UIPasteboard.general.string = segment.sanitizedText(in: selectedRange)
    }

    func rect(for line: CodeTextSegment.Line) -> CGRect? {
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: line.displayRange, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerInset.left
        rect.origin.y += textContainerInset.top
        return rect.integral
    }

    private func drawLineBackgrounds() {
        guard let segment else { return }

        for line in segment.lines {
            guard let lineRect = rect(for: line) else { continue }
            let backgroundRect = CGRect(x: 0, y: lineRect.minY, width: bounds.width, height: lineRect.height)
            Self.backgroundColor(for: line.row.backgroundStyle).setFill()
            UIRectFill(backgroundRect)
        }
    }

    fileprivate static func backgroundColor(for style: DiffBackgroundStyle) -> UIColor {
        switch style {
        case .neutral:
            return .clear
        case .addition:
            return UIColor.systemGreen.withAlphaComponent(0.12)
        case .deletion:
            return UIColor.systemRed.withAlphaComponent(0.12)
        case .hidden:
            return .clear
        }
    }
}

private final class UIKitCodeTextGutterView: UIView {
    weak var textView: UIKitSelectableCodeTextView?
    var segment: CodeTextSegment? {
        didSet {
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        guard let segment, let textView else { return }

        let font = UIFont.monospacedSystemFont(ofSize: CodeSurfaceMetrics.fontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.secondaryLabel
        ]

        for line in segment.lines {
            guard let lineRect = textView.rect(for: line) else { continue }
            let backgroundRect = CGRect(x: 0, y: lineRect.minY, width: bounds.width, height: lineRect.height)
            UIKitSelectableCodeTextView.backgroundColor(for: line.row.backgroundStyle).setFill()
            UIRectFill(backgroundRect)

            let label = segment.gutterText(for: line.row)
            let textSize = (label as NSString).size(withAttributes: attributes)
            let drawPoint = CGPoint(
                x: bounds.width - CodeSurfaceMetrics.gutterTrailingPadding - textSize.width,
                y: lineRect.minY + max((lineRect.height - textSize.height) * 0.5, 0)
            )
            (label as NSString).draw(at: drawPoint, withAttributes: attributes)
        }
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
