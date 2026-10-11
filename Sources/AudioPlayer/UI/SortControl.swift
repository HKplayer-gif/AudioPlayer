import SwiftUI

struct SortOption<Value: Hashable>: Identifiable {

    let id: Value
    let title: String

}

struct SortControl<Value: Hashable>: View {

    let sortOrder: Value
    let options: [SortOption<Value>]
    let onSelect: (Value) -> Void

    @State private var isPresented = false

    var body: some View {

        Button {

            isPresented.toggle()

        } label: {

            Label(
                "Sort",
                systemImage: "arrow.up.arrow.down"
            )
        }
        .popover(
            isPresented: $isPresented,
            arrowEdge: .bottom
        ) {

            SortOptionsView(
                sortOrder: sortOrder,
                options: options,
                onSelect: { order in
                    onSelect(order)
                    isPresented = false
                }
            )
        }
    }
}

private struct SortOptionsView<Value: Hashable>: View {

    let sortOrder: Value
    let options: [SortOption<Value>]
    let onSelect: (Value) -> Void

    var body: some View {

        VStack(spacing: 4) {

            ForEach(options) { option in

                SortOptionRow(
                    title: option.title,
                    order: option.id,
                    sortOrder: sortOrder,
                    onSelect: onSelect
                )
            }
        }
        .padding(8)
        .frame(width: 280)
    }
}

private struct SortOptionRow<Value: Hashable>: View {

    let title: String
    let order: Value
    let sortOrder: Value
    let onSelect: (Value) -> Void

    @State private var isHovered = false

    private var isSelected: Bool {
        sortOrder == order
    }

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

            onSelect(order)

        } label: {

            HStack {

                Text(title)

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
