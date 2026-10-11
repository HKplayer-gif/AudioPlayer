import SwiftUI

struct SettingsLibraryView: View {

    @Environment(AppController.self) private var appController
    @State private var draft: SettingsState
    @State private var showDeleteHistoryAlert = false
    @State private var showClearLibraryAlert = false
    @State private var showQuickSearchHelp = false

    init() {
        _draft = State(
            initialValue: .default
        )
    }

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
            restoreDraftIfNeeded()
        }
        .onChange(of: draft) { _, newDraft in
            appController.setSettingsHasUnsavedChanges(
                newDraft != appController.settings
            )
        }
        .alert(
            "Delete All History?",
            isPresented: $showDeleteHistoryAlert
        ) {
            Button("Delete All", role: .destructive) {
                appController.history.clear()
            }

            Button("Cancel", role: .cancel) {
            }
        } message: {
            Text(
                "This will permanently remove all history records."
            )
        }
        .alert(
            "Delete All Library Data?",
            isPresented: $showClearLibraryAlert
        ) {
            Button("Delete All", role: .destructive) {
                appController.library.clear()
                appController.history.clear()
                appController.selectedFolder.clearSelection()
                appController.selectedFolder.history.clearAll()
                appController.browser.clear()
            }

            Button("Cancel", role: .cancel) {
            }
        } message: {
            Text(
                "This will permanently remove the current Library data, Recent Folders, History, and Specific File selection. It will not affect Library settings, playlists, or other settings."
            )
        }
    }

    private var header: some View {
        HStack {
            Text("Library")
                .font(.headline)

            Spacer()

            Button("Reset") {
                resetDraft()
            }

            Button("Cancel") {
                cancelChanges()
            }

            Button("Save") {
                saveChanges()
            }
        }
        .padding()
    }

    private var content: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 24
            ) {
                casualSection
                historySection
                Spacer()
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .padding()
    }

    private var casualSection: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text("Casual")
                .font(.headline)

            HStack {
                Text("Enable Quick Search")

                Button {
                    showQuickSearchHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showQuickSearchHelp, arrowEdge: .trailing) {
                    quickSearchHelp
                }

                Spacer()

                Toggle(
                    "",
                    isOn: $draft.quickSearchEnabled
                )
                .labelsHidden()
            }

            HStack {
                Text("Case Sensitive")
                Spacer()
                Toggle(
                    "",
                    isOn: $draft.quickSearchCaseSensitive
                )
                .labelsHidden()
            }

            Button("Delete All Library Data", role: .destructive) {
                showClearLibraryAlert = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    private var quickSearchHelp: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Text("Quick Search")
                .font(.headline)

            Text(
                "Quick Search lets you quickly locate an item in the current Library by typing the beginning of its name."
            )

            Text("How to use")
                .font(.subheadline.weight(.semibold))

            Text(
                "Enable Quick Search, then type characters while viewing Library. The first matching item is selected and brought into view. Additional characters narrow the match."
            )

            Text("Supported characters")
                .font(.subheadline.weight(.semibold))

            Text(
                "Quick Search supports uppercase and lowercase English letters, numbers, and common ASCII symbols that can be typed directly from the keyboard, with or without Shift."
            )

            Text("Controls")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                quickSearchControlRow("Character", "Add the character to the search.")
                quickSearchControlRow("Delete", "Remove the last search character.")
                quickSearchControlRow("Esc", "Clear the entire search.")
            }

            Text("Quick Search currently works in Library only. Unsupported or unrecognized characters are ignored without a warning or error.")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 360)
    }

    private func quickSearchControlRow(
        _ key: String,
        _ description: String
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .frame(width: 64, alignment: .leading)
                .font(.system(.body, design: .monospaced))
            Text(description)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var historySection: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text("History")
                .font(.headline)

            HStack {
                Text("Maximum History Records")
                Spacer()
                Picker(
                    "",
                    selection: $draft.historyCapacity
                ) {
                    Text("10")
                        .tag(10)
                    Text("50")
                        .tag(50)
                    Text("100")
                        .tag(100)
                    Text("250")
                        .tag(250)
                    Text("500")
                        .tag(500)
                }
                .labelsHidden()
                .frame(width: 100)
            }

            Button("Delete All History", role: .destructive) {
                showDeleteHistoryAlert = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    private func restoreDraftIfNeeded() {
        draft = appController.settings
    }

    private func resetDraft() {
        draft = appController.settingsStore
            .loadDefaultSettings()
    }

    private func cancelChanges() {
        draft = appController.settings
    }

    private func saveChanges() {
        appController.saveSettings(draft)
    }
}
