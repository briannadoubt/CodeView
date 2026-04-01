import DiffCore
import DiffPlatformAdapters
import DiffRendering
import DiffState
import SyntaxCore

#if canImport(SwiftUI)
import SwiftUI

public struct DiffUICallbacks: Sendable {
    public var onSelectionChanged: (@Sendable (DiffSelection?) -> Void)?
    public var onHiddenContextExpanded: (@Sendable (String) -> Void)?

    public init(
        onSelectionChanged: (@Sendable (DiffSelection?) -> Void)? = nil,
        onHiddenContextExpanded: (@Sendable (String) -> Void)? = nil
    ) {
        self.onSelectionChanged = onSelectionChanged
        self.onHiddenContextExpanded = onHiddenContextExpanded
    }
}

public protocol ViewportTracking: Sendable {
    func updateViewport(fileID: DiffFile.ID, anchorRowID: String?)
}

public protocol NavigationLayoutStrategy: Sendable {
    func makeLayout(
        sidebar: @escaping () -> AnyView,
        detail: @escaping () -> AnyView
    ) -> AnyView
}

public struct DefaultNavigationLayoutStrategy: NavigationLayoutStrategy {
    public init() {}

    public func makeLayout(
        sidebar: @escaping () -> AnyView,
        detail: @escaping () -> AnyView
    ) -> AnyView {
        AnyView(
            NavigationSplitView {
                sidebar()
            } detail: {
                detail()
            }
        )
    }
}

public struct DiffSurfaceView: View {
    private let files: [DiffFile]
    private let fileTree: [FileTreeNode]?
    private let fileContentsProvider: @Sendable (DiffFile.ID) async -> String?
    private let syntaxConfiguration: SyntaxConfiguration
    private let syntaxRuntime: any SyntaxRuntimeProviding
    private let renderer: AnyCodeTextSurfaceRenderer
    private let callbacks: DiffUICallbacks
    private let controller: DiffControlling
    private let viewportTracker: (any ViewportTracking)?
    private let navigationLayoutStrategy: any NavigationLayoutStrategy

    @State private var contents: [DiffFile.ID: String] = [:]

    public init(
        files: [DiffFile],
        fileTree: [FileTreeNode]? = nil,
        controller: DiffControlling,
        fileContentsProvider: @escaping @Sendable (DiffFile.ID) async -> String?,
        syntaxConfiguration: SyntaxConfiguration = .default,
        syntaxRuntime: any SyntaxRuntimeProviding = DefaultSyntaxRuntimeProvider.shared,
        renderer: AnyCodeTextSurfaceRenderer,
        callbacks: DiffUICallbacks = .init(),
        viewportTracker: (any ViewportTracking)? = nil,
        navigationLayoutStrategy: any NavigationLayoutStrategy = DefaultNavigationLayoutStrategy()
    ) {
        self.files = files
        self.fileTree = fileTree
        self.controller = controller
        self.fileContentsProvider = fileContentsProvider
        self.syntaxConfiguration = syntaxConfiguration
        self.syntaxRuntime = syntaxRuntime
        self.renderer = renderer
        self.callbacks = callbacks
        self.viewportTracker = viewportTracker
        self.navigationLayoutStrategy = navigationLayoutStrategy
    }

    public var body: some View {
        let fileIDs = files.map(\.id)
        navigationLayoutStrategy.makeLayout(
            sidebar: {
                AnyView(
                    Group {
                        if controller.displayOptions.showsFileTree, let fileTree {
                            List(fileTree, children: \.optionalChildren) { node in
                                Label(node.name, systemImage: node.kind == .directory ? "folder" : "doc.text")
                            }
                            .navigationTitle("Files")
                        }
                    }
                )
            },
            detail: {
                AnyView(
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                            ForEach(renderedFiles) { rendered in
                                Section {
                                    fileContent(rendered: rendered)
                                } header: {
                                    HStack {
                                        Text(rendered.file.path)
                                            .font(.headline)
                                        Spacer()
                                        Text(controller.displayOptions.viewMode.rawValue.capitalized)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(.thinMaterial)
                                }
                            }
                        }
                    }
                    .navigationTitle("CodeView")
                    .task(id: fileIDs) {
                        await reloadContents()
                    }
                    .toolbar {
                        ToolbarItemGroup {
                            Picker("Mode", selection: Binding(
                                get: { controller.displayOptions.viewMode },
                                set: { controller.setViewMode($0) }
                            )) {
                                Text("Unified").tag(DiffViewMode.unified)
                                Text("Split").tag(DiffViewMode.split)
                            }
                            .pickerStyle(.segmented)

                            Toggle("Wrap", isOn: Binding(
                                get: { controller.displayOptions.wrapsLines },
                                set: { controller.setWrapsLines($0) }
                            ))

                            Toggle("Tree", isOn: Binding(
                                get: { controller.displayOptions.showsFileTree },
                                set: { controller.setShowsFileTree($0) }
                            ))
                        }
                    }
                )
            }
        )
    }

    private var renderedFiles: [RenderedFile] {
        files.map { file in
            let projectedFile = projected(file: file)
            let rows = DiffCoreEngine.rows(
                for: projectedFile,
                fullyExpandedBlockIDs: controller.expandedBlockIDs,
                partiallyExpandedBlocks: controller.hiddenContextExpansionStates
            )
            let output = DiffRendererBridge.render(
                visibleRows: rows,
                fileContents: [file.id: contents[file.id] ?? file.flattenedText],
                displayMode: controller.displayOptions.viewMode,
                wrapsLines: controller.displayOptions.wrapsLines,
                expansionChunkSize: 20,
                syntaxConfiguration: syntaxConfiguration,
                languageResolver: { _ in
                    syntaxRuntime.resolveLanguage(
                        path: projectedFile.path,
                        alias: nil,
                        shebang: nil,
                        configuration: syntaxConfiguration
                    )
                },
                syntaxRuntime: syntaxRuntime
            )
            return RenderedFile(
                file: file,
                output: output,
                surfaces: output.surfaces.filter { $0.fileID == file.id }
            )
        }
    }

    @ViewBuilder
    private func fileContent(rendered: RenderedFile) -> some View {
        let expandHiddenContext: @MainActor @Sendable (HiddenContextBlock, HiddenContextAction) -> Void = { hiddenBlock, action in
            switch action {
            case .expandUp:
                controller.revealHiddenContext(hiddenBlock, direction: .up, lineCount: 20)
            case .expandAll:
                controller.markBlockExpanded(hiddenBlock.id)
            case .expandDown:
                controller.revealHiddenContext(hiddenBlock, direction: .down, lineCount: 20)
            }
            callbacks.onHiddenContextExpanded?(hiddenBlock.id)
        }

        let selectionChanged: @MainActor @Sendable (CodeTextSurfaceModel, DiffTextSelection?) -> Void = { surface, textSelection in
            let selection = textSelection.map {
                DiffSelection(
                    fileID: rendered.file.id,
                    lineID: $0.anchor.rowID,
                    textSelection: $0
                )
            }

            controller.selection = selection
            callbacks.onSelectionChanged?(selection)
        }

        ForEach(rendered.output.blocks) { block in
            switch block.kind {
            case let .header(text):
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            case .textSurface:
                ForEach(rendered.surfaces) { surface in
                    renderer.render(
                        surface: surface,
                        onSelectionChanged: { selectionChanged(surface, $0) },
                        onExpandHiddenContext: expandHiddenContext
                    )
                        .onAppear {
                            viewportTracker?.updateViewport(fileID: rendered.file.id, anchorRowID: surface.rows.first?.id)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.15))
                        )
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    private func projected(file: DiffFile) -> DiffFile {
        var copy = file
        copy.isCollapsed = controller.collapsedFileIDs.contains(file.id)
        return copy
    }

    private func reloadContents() async {
        var loadedContents: [DiffFile.ID: String] = [:]
        loadedContents.reserveCapacity(files.count)
        for file in files {
            loadedContents[file.id] = await fileContentsProvider(file.id) ?? file.flattenedText
        }
        await MainActor.run {
            contents = loadedContents
        }
    }

    private struct RenderedFile: Identifiable {
        let file: DiffFile
        let output: DiffRenderOutput
        let surfaces: [CodeTextSurfaceModel]

        var id: DiffFile.ID {
            file.id
        }
    }
}
#endif
