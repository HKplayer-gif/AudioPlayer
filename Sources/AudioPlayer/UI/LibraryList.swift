import SwiftUI

struct LibraryList<Item: Identifiable>: View {

    let items: [Item]
    let transitionID: UUID
    let title: (Item) -> String
    let isSelected: (Item) -> Bool
    let isActivated: (Item) -> Bool
    let onSelect: (Item) -> Void
    let onActivate: (Item) -> Void
    let contextMenu: ((Item) -> AnyView)?
    let scrollTargetID: Item.ID?

    init(
        items: [Item],
        transitionID: UUID,
        title: @escaping (Item) -> String,
        isSelected: @escaping (Item) -> Bool,
        isActivated: @escaping (Item) -> Bool,
        onSelect: @escaping (Item) -> Void,
        onActivate: @escaping (Item) -> Void,
        contextMenu: ((Item) -> AnyView)? = nil,
        scrollTargetID: Item.ID? = nil
    ) {
        self.items = items
        self.transitionID = transitionID
        self.title = title
        self.isSelected = isSelected
        self.isActivated = isActivated
        self.onSelect = onSelect
        self.onActivate = onActivate
        self.contextMenu = contextMenu
        self.scrollTargetID = scrollTargetID
    }

    var body: some View {

        ScrollViewReader { proxy in
            ScrollView {

                LazyVStack(spacing: 0) {

                ListTransition(
                    items: items,
                    isInteractionEnabled: { _ in
                        true
                    },
                    isRapidScrolling: false,
                    transitionID: transitionID
                ) { item, _ in

                    LibraryRow(
                        title: title(item),
                        isSelected: isSelected(item),
                        isActivated: isActivated(item),
                        isInteractionEnabled: true,
                        onSelect: { _ in
                            onSelect(item)
                        },
                        onContextMenu: {},
                        onActivate: {
                            onActivate(item)
                        }
                    )
                    .contextMenu {
                        if let contextMenu {
                            contextMenu(item)
                        }
                    }
                    .id(item.id)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .bottom) {
                        Divider()
                    }
                }
                }
            }
            .onChange(of: scrollTargetID) { _, targetID in
                guard let targetID else {
                    return
                }

                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(targetID, anchor: .center)
                }
            }
        }
    }
}
