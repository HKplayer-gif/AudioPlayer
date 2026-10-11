import SwiftUI
import AppKit

struct LibraryView: View {

    @Environment(AppController.self) private var appController

    @State private var selectedSource: LibrarySource
    @State private var showingFolderPicker = false
    @State private var showingFolderNotFound = false

    @State private var selectedTrackID: URL?
    @State private var activatedTrackID: URL?
    @State private var quickSearchTargetID: URL?
    @State private var quickSearchController: QuickSearchController

    @State private var selectedHistoryID: URL?
    @State private var activatedHistoryID: URL?

    @State private var libraryTransitionID = UUID()
    @State private var historyTransitionID = UUID()
    @State private var browserTransitionID = UUID()
    @State private var recentFoldersTransitionID = UUID()
    @State private var isRefreshingHistory = false
    @State private var isRefreshingLibrary = false
    @State private var hoveredSection: LibrarySource?

    @State private var specificFileErrorMessage: String?

    enum LibrarySource: Hashable {
        case history
        case selectedFolder
        case browser
    }

    @MainActor
    init(appController: AppController) {
        _quickSearchController = State(
            initialValue: QuickSearchController()
        )

        switch appController.persistence.appState.librarySource {
        case "selectedFolder":
            _selectedSource = State(initialValue: .selectedFolder)
        case "browser":
            _selectedSource = State(initialValue: .browser)
        case "history":
            _selectedSource = State(initialValue: .history)
        default:
            _selectedSource = State(initialValue: .history)
        }
    }

    var body: some View {

        VStack(spacing: 0) {

            HStack(spacing: 0) {
                sectionButton(
                    title: "History",
                    section: .history
                )

                sectionButton(
                    title: "Selected Folder",
                    section: .selectedFolder
                )

                sectionButton(
                    title: "Specific File",
                    section: .browser
                )
            }
            .padding()

            Divider()

            Group {

                switch selectedSource {

                case .history:
                    historyContent

                case .selectedFolder:
                    selectedFolderContent

                case .browser:
                    browserContent
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
        .navigationTitle("Library")
        .alert(
            "Folder Not Found",
            isPresented: $showingFolderNotFound
        ) {
            Button("OK") {
                appController
                    .selectedFolder
                    .clearFolderNotFoundState()
            }
        } message: {
            Text("The selected folder could not be found.")
        }
                .alert(
            "Unable to Play",
            isPresented: Binding(
                get: {
                    appController.playbackErrorMessage != nil
                },
                set: { isPresented in
                    if !isPresented {
                        appController.dismissPlaybackError()
                    }
                }
            )
        ) {
            Button("OK") {
                appController.dismissPlaybackError()
            }
        } message: {
            Text(
                appController.playbackErrorMessage
                ?? "The selected audio file could not be played."
            )
        }
        .onAppear {
            if appController.selectedFolder.folderWasNotFound {
                showingFolderNotFound = true
            }

            if appController.settings.quickSearchEnabled {
                quickSearchController.start()
            }
        }
        .onDisappear {
            quickSearchController.stop()
            quickSearchTargetID = nil
        }
        .onChange(of: selectedSource) { _, newSource in
            quickSearchController.clear()
            quickSearchTargetID = nil
            persistLibrarySource(newSource)
        }
        .onChange(of: quickSearchController.buffer) { _, newBuffer in
            performQuickSearch(newBuffer)
        }
    

        .alert(
            "Unable to Select File",
            isPresented: Binding(
                get: {
                    specificFileErrorMessage != nil
                },
                set: { isPresented in
                    if !isPresented {
                        specificFileErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {
                specificFileErrorMessage = nil
            }
        } message: {
            Text(
                specificFileErrorMessage
                ?? "The selected file could not be loaded."
            )
        }
}

    private func persistLibrarySource(
        _ source: LibrarySource
    ) {
        let librarySource: String

        switch source {
        case .history:
            librarySource = "history"

        case .selectedFolder:
            librarySource = "selectedFolder"

        case .browser:
            librarySource = "browser"
        }

        var appState = appController.persistence.appState
        appState.librarySource = librarySource
        appController.persistence.reportApp(appState)
    }

    private func sectionButton(
        title: String,
        section: LibrarySource
    ) -> some View {
        Button {
            selectedSource = section
        } label: {
            Text(title)
                .frame(
                    maxWidth: .infinity
                )
                .frame(height: 28)
                .background(
                    RoundedRectangle(
                        cornerRadius: 6
                    )
                    .fill(
                        Color.primary.opacity(
                            selectedSource == section
                                ? 0.26
                                : hoveredSection == section
                                    ? 0.14
                                    : 0.07
                        )
                    )
                )
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: 6
                    )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredSection = hovering ? section : nil
        }
        .frame(
            maxWidth: .infinity
        )
        .frame(height: 28)
    }

    // MARK: - History

    @ViewBuilder
    private var historyContent: some View {

        VStack(spacing: 0) {

            HStack {

                Text("History")
                    .font(.headline)

                Spacer()

                SortControl(
                    sortOrder: appController.history.sortOrder,
                    options: [
                        SortOption(
                            id: History.SortOrder.nameAscending,
                            title: "Name A → Z"
                        ),
                        SortOption(
                            id: History.SortOrder.nameDescending,
                            title: "Name Z → A"
                        ),
                        SortOption(
                            id: History.SortOrder.lastPlayedAscending,
                            title: "Last Played: Oldest → Newest"
                        ),
                        SortOption(
                            id: History.SortOrder.lastPlayedDescending,
                            title: "Last Played: Newest → Oldest"
                        )
                    ],
                    onSelect: { order in
                        appController.setHistorySortOrder(order)
                        historyTransitionID = UUID()
                    }
                )

                Button {

                    refreshHistory()

                } label: {

                    Label(
                        "Refresh",
                        systemImage: "arrow.clockwise"
                    )
                }
            }
            .padding()

            Divider()

            if isRefreshingHistory {

                Color.clear

            } else if appController.history.sortedRecords.isEmpty {

                ContentUnavailableView(
                    "No History",
                    systemImage: "clock",
                    description: Text(
                        "Played tracks will appear here."
                    )
                )

            } else {

                LibraryList(
                    items: appController.history.sortedRecords,
                    transitionID: historyTransitionID,
                    title: { record in
                        record.url.deletingPathExtension().lastPathComponent
                    },
                    isSelected: { record in
                        selectedHistoryID == record.id
                    },
                    isActivated: { record in
                        activatedHistoryID == record.id
                    },
                    onSelect: { record in
                        selectedHistoryID = record.id
                    },
                    onActivate: { record in
                        selectedHistoryID = record.id
                        activatedHistoryID = record.id
                        appController.playHistory(record.url)
                    },
                    contextMenu: { record in
                        trackContextMenu(
                            url: record.url,
                            playAction: {
                                selectedHistoryID = record.id
                                appController.playHistory(record.url)
                            },
                            removeFromHistoryAction: {
                                appController.history.remove(record.url)
                                selectedHistoryID = nil
                                activatedHistoryID = nil
                                historyTransitionID = UUID()
                            }
                        )
                    },
                    scrollTargetID: quickSearchTargetID
                )
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }



    // MARK: - Selected Folder

    @ViewBuilder
    private var selectedFolderContent: some View {

        VStack(spacing: 0) {

            HStack {

                Text(appController.selectedFolder.folderName)
                    .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(
                    minWidth: 0,
                    maxWidth: .infinity,
                    alignment: .leading
                )

                Spacer()

                Button {
                    chooseFolder()
                } label: {
                    Label(
                        appController.selectedFolder.hasFolder
                            ? "Change Folder"
                            : "Choose Folder",
                        systemImage: "folder"
                    )
                }

                RecentFoldersControl(
                    entries: appController.selectedFolder.history.entries,
                    selectedURL: appController.selectedFolder.folderURL,
                    onSelect: { url in
                        selectRecentFolder(url)
                    },
                    onChooseFolder: {
                        chooseFolder()
                    },
                    onPin: { url in
                        appController.selectedFolder.history.pin(url)
                        recentFoldersTransitionID = UUID()
                    },
                    onUnpin: { url in
                        appController.selectedFolder.history.unpin(url)
                        recentFoldersTransitionID = UUID()
                    },
                    onDelete: { url in
                        if appController.selectedFolder.folderURL ==
                            url.standardizedFileURL {
                            appController.selectedFolder.clearSelection()
                            selectedTrackID = nil
                            activatedTrackID = nil
                        }

                        appController.selectedFolder.history.delete(url)
                        recentFoldersTransitionID = UUID()
                    }
                )
                .id(recentFoldersTransitionID)

                SortControl(
                    sortOrder: appController.library.sortOrder,
                    options: [
                        SortOption(
                            id: Library.SortOrder.nameAscending,
                            title: "Name A → Z"
                        ),
                        SortOption(
                            id: Library.SortOrder.nameDescending,
                            title: "Name Z → A"
                        )
                    ],
                    onSelect: { order in
                        appController.setLibrarySortOrder(order)
                        libraryTransitionID = UUID()
                    }
                )

                Button {
                    refreshLibrary()
                } label: {
                    Label(
                        "Refresh",
                        systemImage: "arrow.clockwise"
                    )
                }
            }
            .padding()

            Divider()

            if appController.selectedFolder.hasFolder {

                if isRefreshingLibrary {

                    Color.clear

                } else if appController.library.sortedTracks.isEmpty {

                    ContentUnavailableView(
                        "No Audio Files",
                        systemImage: "music.note",
                        description: Text(
                            "No supported audio files were found in this folder."
                        )
                    )

                } else {

                    LibraryList(
                        items: appController.library.sortedTracks,
                        transitionID: libraryTransitionID,
                        title: { track in
                            track.title
                        },
                        isSelected: { track in
                            selectedTrackID == track.id
                        },
                        isActivated: { track in
                            activatedTrackID == track.id
                        },
                        onSelect: { track in
                            selectedTrackID = track.id
                        },
                        onActivate: { track in
                            selectedTrackID = track.id
                            activatedTrackID = track.id
                            appController.play(track)
                        }
                        ,
                        contextMenu: { track in
                            trackContextMenu(
                                url: track.filePath,
                                playAction: {
                                    selectedTrackID = track.id
                                    appController.play(track)
                                }
                            )
                        },
                        scrollTargetID: quickSearchTargetID
                    )

                }

            } else {

                ContentUnavailableView(
                    "No Folder Selected",
                    systemImage: "folder",
                    description: Text(
                        "Choose a folder to browse your music."
                    )
                )
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    // MARK: - Browser

    @ViewBuilder
    private var browserContent: some View {

        VStack(spacing: 0) {

            HStack {

                Text("Specific File")
                    .font(.headline)

                Spacer()

                if appController.browser.track != nil {
                    Button("Clear", role: .destructive) {
                        appController.browser.clear()
                        selectedTrackID = nil
                        activatedTrackID = nil
                        browserTransitionID = UUID()
                    }
                }

                Button {
                    chooseFile()
                } label: {
                    Label(
                        "Browse",
                        systemImage: "doc"
                    )
                }
            }
            .padding()

            Divider()

            if let track = appController.browser.track {

                LibraryList(
                    items: [track],
                    transitionID: browserTransitionID,
                    title: { track in
                        track.title
                    },
                    isSelected: { track in
                        selectedTrackID == track.id
                    },
                    isActivated: { track in
                        activatedTrackID == track.id
                    },
                    onSelect: { track in
                        selectedTrackID = track.id
                    },
                    onActivate: { track in
                        selectedTrackID = track.id
                        activatedTrackID = track.id

                        appController.play(track.filePath)
                    }
                    ,
                    contextMenu: { track in
                        trackContextMenu(
                            url: track.filePath,
                            playAction: {
                                selectedTrackID = track.id
                                appController.play(track.filePath)
                            }
                        )
                    },
                    scrollTargetID: quickSearchTargetID
                )

            } else {

                ContentUnavailableView(
                    "No File Selected",
                    systemImage: "doc",
                    description: Text(
                        "Choose an audio file to play it here."
                    )
                )
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private func performQuickSearch(_ query: String) {
        quickSearchTargetID = nil

        guard !query.isEmpty else {
            selectedTrackID = nil
            selectedHistoryID = nil
            return
        }

        switch selectedSource {
        case .history:
            let match = appController.history.sortedRecords.first { record in
                quickSearchMatches(
                    query: query,
                    title: record.url.deletingPathExtension().lastPathComponent
                )
            }

            selectedHistoryID = match?.id
            selectedTrackID = nil
            quickSearchTargetID = match?.id

        case .selectedFolder:
            let match = appController.library.sortedTracks.first { track in
                quickSearchMatches(
                    query: query,
                    title: track.title
                )
            }

            selectedTrackID = match?.id
            selectedHistoryID = nil
            quickSearchTargetID = match?.id

        case .browser:
            let match = appController.browser.track.flatMap { track in
                quickSearchMatches(
                    query: query,
                    title: track.title
                ) ? track : nil
            }

            selectedTrackID = match?.id
            selectedHistoryID = nil
            quickSearchTargetID = match?.id
        }
    }

    private func quickSearchMatches(
        query: String,
        title: String
    ) -> Bool {
        if appController.settings.quickSearchCaseSensitive {
            return title.hasPrefix(query)
        }

        return title.lowercased().hasPrefix(query.lowercased())
    }

    private func trackContextMenu(
        url: URL,
        playAction: @escaping () -> Void,
        removeFromHistoryAction: (() -> Void)? = nil
    ) -> AnyView {
        AnyView(
            Group {
                Button("Play") {
                    playAction()
                }

                Menu("Add to Playlist") {
                    if appController.playlists.playlists.isEmpty {
                        Button("No Playlists") {}
                            .disabled(true)
                    } else {
                        ForEach(
                            appController.playlists.playlists
                        ) { playlist in
                            Button(playlist.name) {
                                Task { @MainActor in
                                    _ = await appController.playlists.add(
                                        [url],
                                        to: playlist.id,
                                        allowsDuplicates: appController.settings.allowDuplicatePlaylistItems
                                    )
                                }
                            }
                        }
                    }
                }

                Divider()

                Button("Show in Finder") {
                    FinderUtility.reveal(url)
                }

                if let removeFromHistoryAction {
                    Divider()

                    Button(
                        "Remove from History",
                        role: .destructive
                    ) {
                        removeFromHistoryAction()
                    }
                }
            }
        )
    }

    // MARK: - Browser File Picker

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Select"

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        Task { @MainActor in
            if await appController.browser.select(url) {
                browserTransitionID = UUID()
                selectedTrackID = nil
                activatedTrackID = nil
            } else {
                specificFileErrorMessage =
                    "The selected file could not be loaded as audio."
            }
        }
    }

    private func selectRecentFolder(_ url: URL) {

        do {

            try appController.selectedFolder.select(url)

            if let folderURL =
                appController.selectedFolder.folderURL {

                appController.library.clear()
                libraryTransitionID = UUID()

                Task { @MainActor in
                    await appController.library.refresh(
                    from: folderURL
                    )
                }
            }

        } catch {

            appController.selectedFolder.history.delete(url)

            showingFolderNotFound = true
        }
    }

    private func chooseFolder() {

        let panel = NSOpenPanel()

        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        do {

            try appController.selectedFolder.select(url)

            guard let folderURL =
                appController.selectedFolder.folderURL
            else {
                return
            }

            appController.library.clear()
            libraryTransitionID = UUID()

            Task { @MainActor in
                await appController.library.refresh(
                from: folderURL
                )
            }

        } catch {
            return
        }
    }

    private func refreshHistory() {

        isRefreshingHistory = true
        historyTransitionID = UUID()

        Task { @MainActor in

            try? await Task.sleep(
                nanoseconds: 120_000_000
            )

            guard !Task.isCancelled else {
                return
            }

            appController.history.refresh()
            isRefreshingHistory = false
        }
    }

    private func refreshLibrary() {
        guard
            appController.selectedFolder.refresh(),
            let folderURL =
                appController.selectedFolder.folderURL
        else {
            showingFolderNotFound = true
            return
        }

        isRefreshingLibrary = true

        Task { @MainActor in
            await appController.library.refresh(
                from: folderURL
            )

            libraryTransitionID = UUID()
            isRefreshingLibrary = false
        }
    }
}