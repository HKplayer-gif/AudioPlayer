import SwiftUI
import UniformTypeIdentifiers
import AppKit

enum PlaylistDetailMode {
    case normal
    case more
    case select
}



private enum PlaylistAddAlert: Identifiable {
    case failed
    case duplicate

    var id: Self {
        self
    }
}

struct PlaylistDetailView: View {

    @Environment(AppController.self) private var appController

    let playlistID: UUID
    let onBack: () -> Void

    @State private var mode: PlaylistDetailMode = .normal
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var selectionAnchorID: UUID?
    @State private var listTransitionID = UUID()

    @State private var showCleanPlaylistConfirmation = false
    @State private var showDeleteItemsConfirmation = false
@State private var pendingDeleteItemIDs: Set<UUID> = []
@State private var failedAddURLs: [URL] = []
    @State private var duplicateAddURLs: [URL] = []
    @State private var activeAddAlert: PlaylistAddAlert?

    @State private var isAddDropTargeted = false
    @State private var isPlaylistDropTargeted = false
    @State private var escapeMonitor: Any?

    var body: some View {

        VStack(spacing: 0) {

            header

            Divider()

            content
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .task {
            startEscapeMonitor()
            appController.playlists.refresh(
                playlistID
            )
            listTransitionID = UUID()
        }
        .alert(
            "Remove All Unavailable Tracks?",
            isPresented: $showCleanPlaylistConfirmation
        ) {
            Button("Cancel", role: .cancel) {}

            Button("Remove", role: .destructive) {
                cleanPlaylist()
            }
        } message: {
            Text(
                "All unavailable tracks will be removed from this playlist."
            )
        }
        .alert(
            "Delete Selected Song(s)?",
            isPresented: $showDeleteItemsConfirmation
        ) {
            Button("Cancel", role: .cancel) {}

            Button("Delete", role: .destructive) {
                deletePendingItems()
            }
        } message: {
            Text(
                "The selected songs will be removed from this playlist."
            )
        }
    

        .alert(
            activeAddAlert == .failed
                ? "File(s) Could Not Be Added"
                : "File(s) Already in Playlist",
            isPresented: Binding(
                get: {
                    activeAddAlert != nil
                },
                set: { isPresented in
                    guard !isPresented else {
                        return
                    }

                    if activeAddAlert == .failed &&
                        !duplicateAddURLs.isEmpty {
                        activeAddAlert = .duplicate
                    } else {
                        activeAddAlert = nil
                        failedAddURLs.removeAll()
                        duplicateAddURLs.removeAll()
                    }
                }
            )
        ) {
            Button("OK") {
                if activeAddAlert == .failed &&
                    !duplicateAddURLs.isEmpty {
                    activeAddAlert = .duplicate
                } else {
                    activeAddAlert = nil
                    failedAddURLs.removeAll()
                    duplicateAddURLs.removeAll()
                }
            }
        } message: {
            Text(
                (activeAddAlert == .failed
                    ? failedAddURLs
                    : duplicateAddURLs)
                    .map {
                        $0.lastPathComponent
                    }
                    .joined(separator: "\n")
            )
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
}

    private func addFilesToPlaylist(
        _ urls: [URL]
    ) {
        Task { @MainActor in
            let result = await appController.playlists.add(
                urls,
                to: playlistID,
                allowsDuplicates: appController.settings.allowDuplicatePlaylistItems
            )

            failedAddURLs = result.failedURLs
            duplicateAddURLs = result.duplicateURLs
            listTransitionID = UUID()

            if !failedAddURLs.isEmpty {
                activeAddAlert = .failed
            } else if !duplicateAddURLs.isEmpty {
                activeAddAlert = .duplicate
            }
        }
    }

    private func chooseFilesForPlaylist() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Add"

        guard panel.runModal() == .OK else {
            return
        }

        guard !panel.urls.isEmpty else {
            return
        }

        addFilesToPlaylist(panel.urls)
    }



    private func handleDroppedFiles(
        _ providers: [NSItemProvider]
    ) {
        Task { @MainActor in
            let urls = await loadDroppedURLs(
                from: providers
            )

            guard !urls.isEmpty else {
                return
            }

            addFilesToPlaylist(urls)
        }
    }

    private func loadDroppedURLs(
        from providers: [NSItemProvider]
    ) async -> [URL] {
        final class ResultBox: @unchecked Sendable {
            var urls: [URL] = []
        }

        let box = ResultBox()

        return await withCheckedContinuation { continuation in
            let group = DispatchGroup()

            for provider in providers {
                group.enter()

                _ = provider.loadObject(
                    ofClass: URL.self
                ) { url, _ in
                    if let url {
                        box.urls.append(url)
                    }

                    group.leave()
                }
            }

            group.notify(
                queue: .main
            ) {
                continuation.resume(
                    returning: box.urls
                )
            }
        }
    }


    // MARK: - Header

    @ViewBuilder
    private var header: some View {

        switch mode {

        case .normal:
            normalHeader

        case .more:
            moreHeader

        case .select:
            selectHeader
        }
    }

    private var normalHeader: some View {

        HStack {

            Spacer()

            if let playlist =
                appController.playlists.playlist(
                    with: playlistID
                ) {

                Text(playlist.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(1)

            } else {

                Text("Playlist Not Found")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Spacer()

            HStack(spacing: 8) {

                Button {
                    chooseFilesForPlaylist()
                } label: {
                    Label(
                        "Add",
                        systemImage: "plus"
                    )
                    .foregroundStyle(
                        isAddDropTargeted
                            ? .white
                            : .primary
                    )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    isAddDropTargeted
                        ? Color.green
                        : Color.clear
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 6
                    )
                )
                .onDrop(
                    of: [UTType.fileURL],
                    isTargeted: $isAddDropTargeted
                ) { providers in
                    handleDroppedFiles(providers)
                    return true
                }

                Button {
                    mode = .more
                } label: {
                    Label(
                        "More",
                        systemImage: "ellipsis"
                    )
                }

                Button {
                    guard let playlist =
                        appController.playlists.playlist(
                            with: playlistID
                        ),
                        let firstItem = playlist.items.first
                    else {
                        return
                    }

                    appController.playPlaylistTrack(
                        firstItem.id,
                        in: playlistID
                    )
                } label: {
                    Label(
                        "Play",
                        systemImage: "play.fill"
                    )
                }

                Button {
                    leaveDetail()
                } label: {
                    Label(
                        "Back",
                        systemImage: "chevron.left"
                    )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var moreHeader: some View {

        HStack(spacing: 8) {

            Button {
                showCleanPlaylistConfirmation = true
            } label: {
                Label(
                    "Remove All Unavailable Tracks",
                    systemImage: "exclamationmark.triangle"
                )
            }

                        .tint(.red)
            .disabled(
                appController.playlists
                    .playlist(with: playlistID)?
                    .items.isEmpty ?? true
            )
Button {
                appController.playlists.refresh(
                    playlistID
                )
                listTransitionID = UUID()
            } label: {
                Label(
                    "Refresh",
                    systemImage: "arrow.clockwise"
                )
            }

            Button {
                selectedItemIDs.removeAll()

                mode = .select
            } label: {
                Label(
                    "Select",
                    systemImage: "checkmark.circle"
                )
            }

                        .disabled(
                appController.playlists
                    .playlist(with: playlistID)?
                    .items.isEmpty ?? true
            )
Spacer()

            Button {
                mode = .normal
            } label: {
                Label(
                    "Cancel",
                    systemImage: "xmark"
                )
            }

            Button {
                leaveDetail()
            } label: {
                Label(
                    "Back",
                    systemImage: "chevron.left"
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var selectHeader: some View {

        HStack(spacing: 8) {

            Menu {
                Button("Top") {
                    guard !selectedItemIDs.isEmpty else {
                        return
                    }

                    appController.playlists.moveToTop(
                        Array(selectedItemIDs),
                        in: playlistID
                    )
                }

                Button("Bottom") {
                    guard !selectedItemIDs.isEmpty else {
                        return
                    }

                    appController.playlists.moveToBottom(
                        Array(selectedItemIDs),
                        in: playlistID
                    )
                }
            } label: {
                Label(
                    "Move",
                    systemImage: "arrow.up.and.down"
                )
            }
            .disabled(selectedItemIDs.isEmpty)

            Button {
                selectAll()
            } label: {
                Label(
                    "Select All",
                    systemImage: "checkmark.circle"
                )
            }
            .disabled(!canSelectAll)

            Button {
                deselectAll()
            } label: {
                Label(
                    "Deselect All",
                    systemImage: "circle"
                )
            }
            .disabled(!canDeselectAll)

            Button {
                pendingDeleteItemIDs = selectedItemIDs
                showDeleteItemsConfirmation = true
            } label: {
                Label(
                    "Delete",
                    systemImage: "trash"
                )
            }
            .tint(.red)
            .disabled(selectedItemIDs.isEmpty)

            Spacer()

            Button {
                selectedItemIDs.removeAll()

                mode = .more
            } label: {
                Label(
                    "Cancel",
                    systemImage: "xmark"
                )
            }

            Button {
                leaveDetail()
            } label: {
                Label(
                    "Back",
                    systemImage: "chevron.left"
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {

        if let playlist =
            appController.playlists.playlist(
                with: playlistID
            ) {

            if playlist.items.isEmpty {

                emptyContent

            } else {

                playlistList(
                    playlist
                )
            }

        } else {

            Text("Playlist Not Found")
                .foregroundStyle(.secondary)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
        }
    }

    private var emptyContent: some View {

        VStack(spacing: 10) {

            Image(
                systemName:
                    "music.note.list"
            )
            .font(.system(size: 32))
            .foregroundStyle(.secondary)

            Text("Playlist is Empty")
                .font(.title3)

            Text(
                "Add songs to this playlist "
                + "to get started."
            )
            .foregroundStyle(.secondary)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    private func playlistList(
        _ playlist: Playlist
    ) -> some View {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: 0
            ) {
                ListTransition(
                    items: playlist.items,
                    isInteractionEnabled: { _ in
                        true
                    },
                    isRapidScrolling: false,
                    transitionID: listTransitionID
                ) { item, _ in
                    LibraryRow(
                        title:
                            item.url
                                .deletingPathExtension()
                                .lastPathComponent,
                        isSelected:
                            mode == .select
                            && selectedItemIDs.contains(item.id),
                        isActivated:
                            mode == .normal
                            && appController.currentPlaylistItemID
                                == item.id,
                        isInteractionEnabled: true,
                        allowsDoubleClick:
                            mode != .select,
                        showsSelectionIndicator:
                            mode == .select,
                        onSelect: { isShiftPressed in
                            if mode == .select {
                                toggleSelection(
                                    item.id,
                                    isShiftPressed: isShiftPressed
                                )
                            }
                        },
onActivate: {
                            guard mode == .normal else {
                                return
                            }

                            appController.playPlaylistTrack(
                                item.id,
                                in: playlistID
                            )
                        }
                    )
                                        .contextMenu {
                        Button("Play") {
                            appController.playPlaylistTrack(
                                item.id,
                                in: playlistID
                            )
                        }

                        Button("Show in Folder") {
                            FinderUtility.reveal(item.url)
                        }

                        Divider()

                        Button(
                            "Delete from Playlist",
                            role: .destructive
                        ) {
                            requestDelete(for: item.id)
                        }
                    }
.overlay(alignment: .bottom) {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .overlay {
            if isPlaylistDropTargeted {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.green)
                    .shadow(radius: 8)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: [UTType.fileURL],
            isTargeted: $isPlaylistDropTargeted
        ) { providers in
            handleDroppedFiles(providers)
            return true
        }

    }



    // MARK: - Selection

    private var allItemIDs: Set<UUID> {

        guard let playlist =
            appController.playlists.playlist(
                with: playlistID
            )
        else {
            return []
        }

        return Set(
            playlist.items.map(\.id)
        )
    }

    private var canSelectAll: Bool {

        !allItemIDs.isEmpty
        && selectedItemIDs != allItemIDs
    }

    private var canDeselectAll: Bool {

        !selectedItemIDs.isEmpty
    }

    private func toggleSelection(
        _ itemID: UUID,
        isShiftPressed: Bool
    ) {
        guard let playlist = appController.playlists.playlist(with: playlistID)
        else {
            return
        }

        if isShiftPressed,
           let anchorID = selectionAnchorID,
           let anchorIndex = playlist.items.firstIndex(
               where: { $0.id == anchorID }
           ),
           let targetIndex = playlist.items.firstIndex(
               where: { $0.id == itemID }
           ) {
            let lowerIndex = min(anchorIndex, targetIndex)
            let upperIndex = max(anchorIndex, targetIndex)
            let rangeItems = Array(
                playlist.items[lowerIndex...upperIndex]
            )

            let shouldClear = rangeItems.allSatisfy {
                selectedItemIDs.contains($0.id)
            }

            if shouldClear {
                for item in rangeItems {
                    selectedItemIDs.remove(item.id)
                }
            } else {
                for item in rangeItems {
                    selectedItemIDs.insert(item.id)
                }
            }

            return
        }

        if selectedItemIDs.contains(itemID) {
            selectedItemIDs.remove(itemID)
        } else {
            selectedItemIDs.insert(itemID)
        }

        selectionAnchorID = itemID
    }



    private func selectAll() {

        guard canSelectAll else {
            return
        }

        selectedItemIDs = allItemIDs
        selectionAnchorID = nil
    }

    private func deselectAll() {

        guard canDeselectAll else {
            return
        }

        selectedItemIDs.removeAll()
        selectionAnchorID = nil
    }

    // MARK: - Playlist Actions

    private func cleanPlaylist() {

        appController.playlists.removeMissing(
            from: playlistID
        )
    }

    private func requestDelete(for itemID: UUID) {
        pendingDeleteItemIDs =
            selectedItemIDs.contains(itemID)
            ? selectedItemIDs
            : [itemID]

        showDeleteItemsConfirmation = true
    }

    private func deletePendingItems() {
        guard !pendingDeleteItemIDs.isEmpty else {
            return
        }

        let itemIDs = pendingDeleteItemIDs

        appController.playlists.remove(
            Array(itemIDs),
            from: playlistID
        )

        selectedItemIDs.subtract(itemIDs)
        selectionAnchorID = nil
        pendingDeleteItemIDs.removeAll()
    }


    // MARK: - Navigation

    private func startEscapeMonitor() {
        guard escapeMonitor == nil else {
            return
        }

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else {
                return event
            }

            guard appController.settings.playlistEscapeNavigationEnabled else {
                return event
            }

            handleEscapeNavigation()
            return nil
        }
    }

    private func stopEscapeMonitor() {
        guard let escapeMonitor else {
            return
        }

        NSEvent.removeMonitor(escapeMonitor)
        self.escapeMonitor = nil
    }

    private func handleEscapeNavigation() {
        // ESC dismisses exactly one active layer per press.
        // It never enters another mode and never skips intermediate modes.
        switch mode {
        case .select:
            cancelSelectMode()

        case .more:
            mode = .normal

        case .normal:
            leaveDetail()
        }
    }

    private func cancelSelectMode() {
        selectedItemIDs.removeAll()
        selectionAnchorID = nil
        mode = .more
    }

    private func leaveDetail() {
        stopEscapeMonitor()

        selectedItemIDs.removeAll()

        mode = .normal

        onBack()
    }
}
