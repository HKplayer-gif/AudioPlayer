import SwiftUI

struct PitchCycleRow: View {

    let title: String
    let isSelected: Bool
    let onSelect: (Bool) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
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
            MouseInputHandler { event in
                switch event {
                case .leftClick(
                    isShiftPressed: let isShiftPressed
                ):
                    onSelect(isShiftPressed)

                case .rightClick:
                    break

                case .leftDoubleClick(
                    isShiftPressed: _
                ):
                    onSelect(false)
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
