import SwiftUI

struct LibraryRow: View {

    let title: String

    let isSelected: Bool
    let isActivated: Bool

    let isInteractionEnabled: Bool

       let allowsDoubleClick: Bool
 let showsSelectionIndicator: Bool
    let onSelect: (Bool) -> Void
    let onContextMenu: () -> Void

    let onActivate: () -> Void

    @State private var isHovered = false

    init(
        title: String,
        isSelected: Bool,
        isActivated: Bool,
        isInteractionEnabled: Bool,
                allowsDoubleClick: Bool = true,
        showsSelectionIndicator: Bool = false,
        onSelect: @escaping (Bool) -> Void,
        onContextMenu: @escaping () -> Void = {},
        onActivate: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.isActivated = isActivated
        self.isInteractionEnabled = isInteractionEnabled
                self.allowsDoubleClick = allowsDoubleClick
        self.showsSelectionIndicator = showsSelectionIndicator
        self.onSelect = onSelect
        self.onContextMenu = onContextMenu
        self.onActivate = onActivate
    }

    var body: some View {

        HStack(spacing: 12) {

            if showsSelectionIndicator {
                Image(
                    systemName:
                        isSelected
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .foregroundStyle(
                    isSelected
                    ? .primary
                    : .secondary
                )
                .font(.title3)
            }
            Image(systemName: "waveform")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(title)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

            if isInteractionEnabled {

                MouseInputHandler { event in

                    switch event {

                    case .leftClick(
                        isShiftPressed: let isShiftPressed
                    ):
                        onSelect(isShiftPressed)

                    case .rightClick:
                        onContextMenu()

                    case .leftDoubleClick(
                        isShiftPressed: _
                    ):
                        if allowsDoubleClick {
                            onActivate()
                        } else {
                            onSelect(false)
                        }
                    }
                }
            }
        }
        .onHover { hovering in

            guard isInteractionEnabled else {
                isHovered = false
                return
            }

            isHovered = hovering
        }
    }

    private var backgroundColor: Color {

        if isActivated {
            return Color.secondary.opacity(0.50)
        }

        if isSelected {
            return Color.secondary.opacity(0.30)
        }

        if isHovered {
            return Color.secondary.opacity(0.15)
        }

        return Color.clear
    }
}
