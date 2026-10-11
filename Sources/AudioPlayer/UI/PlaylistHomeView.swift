import SwiftUI

struct PlaylistHomeRow: View {

    let playlist: Playlist
    let isSelected: Bool
    let onSelect: () -> Void
    let onActivate: () -> Void

    @State private var isHovered = false

    var body: some View {

        HStack(spacing: 12) {

            Image(systemName: "music.note.list")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(
                alignment: .leading,
                spacing: 3
            ) {

                Text(playlist.name)
                    .lineLimit(1)

                Text(
                    "\(playlist.items.count) "
                    + (playlist.items.count == 1
                        ? "song"
                        : "songs")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .overlay {
            MouseInputHandler { event in

                switch event {

                case .leftClick:
                    onSelect()

                case .leftDoubleClick:
                    onActivate()

                case .rightClick:
                    break
                }
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var backgroundColor: Color {

        if isSelected {
            return Color.secondary.opacity(0.30)
        }

        if isHovered {
            return Color.secondary.opacity(0.15)
        }

        return Color.clear
    }
}

struct PlaylistHomeView: View {

    @Environment(AppController.self) private var appController

    @State private var selectedPlaylistID: UUID?
    @State private var activePlaylistID: UUID?

    @State private var showDeleteConfirmation = false

    @State private var showRenameSheet = false
    @State private var renameText = ""

    
    @FocusState private var renameFieldFocused: Bool

    var body: some View {

        Group {

            if let activePlaylistID {

                PlaylistDetailView(
                    playlistID: activePlaylistID,
                    onBack: {
                        self.activePlaylistID = nil
                    }
                )

            } else {

                homeContent
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .alert(
            "Delete Playlist?",
            isPresented: $showDeleteConfirmation
        ) {

            Button("Cancel", role: .cancel) {}

            Button("Delete", role: .destructive) {
                deleteSelectedPlaylist()
            }

        } message: {

            Text(
                "This will permanently delete the selected playlist."
            )
        }
        .sheet(
            isPresented: $showRenameSheet,
            onDismiss: {
                renameText = ""
                renameFieldFocused = false
            }
        ) {

            renameSheet
        }
    }

    private var homeContent: some View {

        VStack(spacing: 0) {

            HStack {

                Text("Playlists")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    guard selectedPlaylistID != nil else {
                        return
                    }

                    prepareRename()
                } label: {
                    Label(
                        "Rename",
                        systemImage: "pencil"
                    )
                }
                .foregroundStyle(
                    selectedPlaylistID == nil
                    ? Color.secondary
                    : Color.primary
                )

                                .disabled(selectedPlaylistID == nil)
Menu {
                    Button {
                        moveSelectedPlaylistToTop()
                    } label: {
                        Label(
                            "Top",
                            systemImage: "arrow.up.to.line"
                        )
                    }

                    Button {
                        moveSelectedPlaylistToBottom()
                    } label: {
                        Label(
                            "Bottom",
                            systemImage: "arrow.down.to.line"
                        )
                    }
                } label: {
                    Label(
                        "Move",
                        systemImage: "arrow.up.arrow.down"
                    )
                }
                .foregroundStyle(
                    selectedPlaylistID == nil
                    ? Color.secondary
                    : Color.primary
                )

                                .disabled(selectedPlaylistID == nil)
Button {
                    guard selectedPlaylistID != nil else {
                        return
                    }

                    showDeleteConfirmation = true
                } label: {
                    Label(
                        "Delete Playlist",
                        systemImage: "trash"
                    )
                }
                .foregroundStyle(
                    selectedPlaylistID == nil
                    ? Color.secondary
                    : Color.red
                )

                                .tint(.red)
                .disabled(selectedPlaylistID == nil)
Button {
                    createPlaylist()
                } label: {
                    Label(
                        "Create Playlist",
                        systemImage: "plus"
                    )
                }
                .disabled(
                    appController.playlists.playlists.count
                        >= PlaylistStore.maximumPlaylistCount
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            if appController.playlists.playlists.isEmpty {

                VStack(spacing: 10) {

                    Image(
                        systemName:
                            "music.note.list"
                    )
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)

                    Text("No Playlists")
                        .font(.title3)

                    Text(
                        "Create a playlist to get started."
                    )
                    .foregroundStyle(.secondary)

                    Button("Create Playlist") {
                        createPlaylist()
                    }
                    .padding(.top, 4)
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )

            } else {

                ScrollView {

                    LazyVStack(
                        spacing: 0
                    ) {

                        ForEach(
                            appController.playlists.playlists
                        ) { playlist in

                            playlistRow(
                                playlist
                            )

                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    private var renameSheet: some View {

        VStack(
            alignment: .leading,
            spacing: 16
        ) {

            Text("Rename Playlist")
                .font(.headline)

            TextField(
                "Playlist Name",
                text: $renameText
            )
            .focused(
                $renameFieldFocused
            )
            .onSubmit {
                guard !renameText
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty
                else {
                    return
                }

                renameSelectedPlaylist()
                showRenameSheet = false
            }

            HStack {

                Spacer()

                Button("Cancel") {
                    showRenameSheet = false
                }

                Button("Confirm") {
                    guard !renameText
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty
                    else {
                        return
                    }

                    renameSelectedPlaylist()
                    showRenameSheet = false
                }
            }
        }
        .padding(20)
        .frame(
            width: 380
        )
        .onAppear {
            DispatchQueue.main.async {
                renameFieldFocused = true
            }

            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.15
            ) {
                renameFieldFocused = true
            }
        }
    }

    private func playlistRow(
        _ playlist: Playlist
    ) -> some View {

        PlaylistHomeRow(
            playlist: playlist,
            isSelected:
                selectedPlaylistID == playlist.id,

            onSelect: {
                selectedPlaylistID = playlist.id
            },

            onActivate: {
                selectedPlaylistID = playlist.id
                activePlaylistID = playlist.id
            }
        )
.contextMenu {
    Button("Play") {
        selectedPlaylistID = playlist.id

        guard
            let firstItem = playlist.items.first
        else {
            return
        }

        appController.playPlaylistTrack(
            firstItem.id,
            in: playlist.id
        )
    }
    .disabled(playlist.items.isEmpty)

    Button("Open") {
        selectedPlaylistID = playlist.id
        activePlaylistID = playlist.id
    }

    Button("Rename") {
        selectedPlaylistID = playlist.id
        prepareRename()
    }

    Divider()

    Button("Delete", role: .destructive) {
        selectedPlaylistID = playlist.id
        showDeleteConfirmation = true
    }
}

    }

    private func createPlaylist() {

        let usedNames = Set(
            appController.playlists.playlists.map {
                $0.name
            }
        )

        var index = 1

        while usedNames.contains(
            "Playlist \(index)"
        ) {
            index += 1
        }

        guard let playlist =
                appController.playlists.create(
                    name: "Playlist \(index)"
                )
        else {
            return
        }

        selectedPlaylistID = playlist.id
    }

    private func prepareRename() {

        guard let selectedID = selectedPlaylistID,
              let playlist =
                appController.playlists.playlist(
                    with: selectedID
                )
        else {
            return
        }

        renameText = playlist.name
        showRenameSheet = true
    }

    private func renameSelectedPlaylist() {

        guard let selectedID = selectedPlaylistID else {
            return
        }

        let trimmedName =
            renameText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !trimmedName.isEmpty else {
            return
        }

        appController.playlists.rename(
            selectedID,
            to: trimmedName
        )
    }

    private func moveSelectedPlaylistToTop() {

        guard let selectedID = selectedPlaylistID else {
            return
        }

        appController.playlists.movePlaylistToTop(
            selectedID
        )
    }

    private func moveSelectedPlaylistToBottom() {

        guard let selectedID = selectedPlaylistID else {
            return
        }

        appController.playlists.movePlaylistToBottom(
            selectedID
        )
    }

    private func deleteSelectedPlaylist() {

        guard let selectedID = selectedPlaylistID else {
            return
        }

        guard appController.playlists.playlist(
            with: selectedID
        ) != nil else {

            selectedPlaylistID = nil
            return
        }

        appController.playlists.delete(
            selectedID
        )

        selectedPlaylistID = nil
    }
}
