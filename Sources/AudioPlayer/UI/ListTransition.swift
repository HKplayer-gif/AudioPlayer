import SwiftUI

struct ListTransition<Item: Identifiable, RowContent: View>: View {

    let items: [Item]

    let isInteractionEnabled: (Item) -> Bool

    let isRapidScrolling: Bool

    let rowContent: (Item, Int) -> RowContent

    let transitionID: UUID

    private let rowDelay: UInt64 = 25_000_000
    private let animationDuration: UInt64 = 250_000_000

    @State private var appearedIDs: Set<Item.ID> = []
    @State private var interactiveIDs: Set<Item.ID> = []
    @State private var startedTransitionID: UUID?

    init(
        items: [Item],
        isInteractionEnabled: @escaping (Item) -> Bool,
        isRapidScrolling: Bool,
        transitionID: UUID,
        @ViewBuilder rowContent: @escaping (Item, Int) -> RowContent
    ) {
        self.items = items
        self.isInteractionEnabled = isInteractionEnabled
        self.isRapidScrolling = isRapidScrolling
        self.transitionID = transitionID
        self.rowContent = rowContent
    }

    var body: some View {

        ForEach(
            Array(items.enumerated()),
            id: \.element.id
        ) { index, item in

            rowContent(item, index)
                .opacity(
                    appearedIDs.contains(item.id) ? 1 : 0
                )
                .offset(
                    y: appearedIDs.contains(item.id) ? 0 : 16
                )
                .allowsHitTesting(
                    isInteractionEnabled(item)
                    && interactiveIDs.contains(item.id)
                )
        }
        .onChange(of: transitionID) {

            resetTransition()
            startTransition()
        }
        .onChange(of: isRapidScrolling) {
            guard isRapidScrolling else {
                return
            }

            accelerateRemainingRows()
        }
        .onAppear {
            startTransition()
        }
    }

    private func resetTransition() {

        appearedIDs.removeAll()
        interactiveIDs.removeAll()
        startedTransitionID = nil
    }

    private func startTransition() {
        guard startedTransitionID != transitionID else {
            return
        }

        guard !items.isEmpty else {
            return
        }

        startedTransitionID = transitionID

        for (index, item) in items.enumerated() {

            let delay: UInt64

            switch index {
            case 0..<25:
                delay = rowDelay * UInt64(index)

            case 25..<100:
                delay = rowDelay * 24 + 5_000_000 * UInt64(index - 24)

            default:
                delay = rowDelay * 24 + 5_000_000 * 75
            }

            Task { @MainActor in

                if delay > 0 {
                    try? await Task.sleep(
                        nanoseconds: delay
                    )
                }

                guard !Task.isCancelled else {
                    return
                }

                guard !appearedIDs.contains(item.id) else {
                    return
                }

                startRowAnimation(item)
            }
        }
    }

    private func startRowAnimation(
        _ item: Item
    ) {

        _ = withAnimation(
            .easeOut(duration: 0.25)
        ) {
            appearedIDs.insert(item.id)
        }

        Task { @MainActor in

            try? await Task.sleep(
                nanoseconds: animationDuration
            )

            guard !Task.isCancelled else {
                return
            }

            interactiveIDs.insert(item.id)
        }
    }

    private func accelerateRemainingRows() {

        guard startedTransitionID == transitionID else {
            return
        }

        for item in items {

            guard !appearedIDs.contains(item.id) else {
                continue
            }

            startRowAnimation(item)
        }
    }
}
