import SwiftUI

struct RecentFoldersControl: View {

    let entries: [SelectedFolderHistory.Entry]
    let selectedURL: URL?
    let onSelect: (URL) -> Void
    let onChooseFolder: () -> Void
    let onPin: (URL) -> Void
    let onUnpin: (URL) -> Void
    let onDelete: (URL) -> Void

    @State private var isPresented = false

    private let maximumVisibleSlots = 4

    var body: some View {

        Button {

            isPresented.toggle()

        } label: {

            Label(
                "Recent Folders",
                systemImage: "clock.arrow.circlepath"
            )
        }
        .popover(
            isPresented: $isPresented,
            arrowEdge: .bottom
        ) {

            RecentFoldersMenu(
                entries: Array(
                    entries.prefix(maximumVisibleSlots)
                ),
                selectedURL: selectedURL,
                onSelect: { url in
                    onSelect(url)
                    isPresented = false
                },
                onChooseFolder: {
                    isPresented = false
                    onChooseFolder()
                },
                onPin: { url in
                    onPin(url)
                    isPresented = false
                },
                onUnpin: { url in
                    onUnpin(url)
                    isPresented = false
                },
                onDelete: { url in
                    onDelete(url)
                    isPresented = false
                }
            )
        }
    }
}

private struct RecentFoldersMenu: View {

    let entries: [SelectedFolderHistory.Entry]
    let selectedURL: URL?
    let onSelect: (URL) -> Void
    let onChooseFolder: () -> Void
    let onPin: (URL) -> Void
    let onUnpin: (URL) -> Void
    let onDelete: (URL) -> Void

    private let maximumVisibleSlots = 4

    var body: some View {

        VStack(spacing: 4) {

            ForEach(
                0..<maximumVisibleSlots,
                id: \.self
            ) { index in

                if index < entries.count {

                    RecentFolderRow(
                        entry: entries[index],
                        isSelected:
                            selectedURL == entries[index].url,
                        onSelect: onSelect,
                        onPin: onPin,
                        onUnpin: onUnpin,
                        onDelete: onDelete
                    )

                } else {

                    ChooseFolderRow(
                        onChooseFolder: onChooseFolder
                    )
                }
            }
        }
        .padding(8)
        .frame(width: 280)
    }
}

private struct RecentFolderRow: View {

    let entry: SelectedFolderHistory.Entry
    let isSelected: Bool
    let onSelect: (URL) -> Void
    let onPin: (URL) -> Void
    let onUnpin: (URL) -> Void
    let onDelete: (URL) -> Void

    @State private var isHovered = false

    private var backgroundOpacity: Double {

        if isSelected {
            return 0.50
        }

        if isHovered {
            return 0.25
        }

        return 0.0
    }

    var body: some View {

        Button {

            onSelect(entry.url)

        } label: {

            HStack(spacing: 8) {

                Image(systemName: "folder")

                Text(entry.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if entry.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .background {

                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        Color.secondary.opacity(
                            backgroundOpacity
                        )
                    )
            }
            .contentShape(
                RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if entry.isPinned {
                Button("Unpin") {
                    onUnpin(entry.url)
                }
            } else {
                Button("Pin") {
                    onPin(entry.url)
                }
            }

            Divider()

            Button(
                "Delete",
                role: .destructive
            ) {
                onDelete(entry.url)
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct ChooseFolderRow: View {

    let onChooseFolder: () -> Void

    @State private var isHovered = false

    private var backgroundOpacity: Double {

        if isHovered {
            return 0.25
        }

        return 0.0
    }

    var body: some View {

        Button {

            onChooseFolder()

        } label: {

            HStack(spacing: 8) {

                Image(systemName: "folder")

                Text("Choose Folder")

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .background {

                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        Color.secondary.opacity(
                            backgroundOpacity
                        )
                    )
            }
            .contentShape(
                RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
