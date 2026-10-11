import SwiftUI

struct PlaybackContextView: View {

    @Environment(AppController.self) private var appController

    private let rowHeight: CGFloat = 34
    private let visibleRows = 5

    @State private var visualCenter: Double?
    @State private var queueIdentity: ObjectIdentifier?

    private var queue: PlaybackQueue? {
        appController.playbackQueue
    }

    private var currentIndex: Int? {
        appController.playbackQueueCurrentIndex
    }

    var body: some View {
        Group {
            if let queue, let currentIndex {
                PlaybackContextWindow(
                    queue: queue,
                    currentIndex: currentIndex,
                    visualCenter: visualCenter ?? Double(currentIndex),
                    rowHeight: rowHeight,
                    visibleRows: visibleRows,
                    onDoubleClick: { index in
                        appController.playPlaybackQueueIndex(index)
                    }
                )
            } else {
                Text("No Playback Queue")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(height: rowHeight * CGFloat(visibleRows))
                    .frame(maxWidth: .infinity)
                    .background(contextBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(width: 220)
        .onAppear {
            resetPosition()
        }
        .onChange(of: currentQueueIdentity) { _, _ in
            resetPosition()
        }
        .onChange(of: currentIndex) { _, newIndex in
            guard let newIndex else {
                return
            }

            guard queueIdentity == currentQueueIdentity else {
                resetPosition()
                return
            }

            withAnimation(.easeInOut(duration: 0.38)) {
                visualCenter = Double(newIndex)
            }
        }
    }

    private var currentQueueIdentity: ObjectIdentifier? {
        guard let queue else {
            return nil
        }

        return ObjectIdentifier(queue)
    }

    private var contextBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            }
    }

    private func resetPosition() {
        visualCenter = currentIndex.map(Double.init)
        queueIdentity = currentQueueIdentity
    }
}

private struct PlaybackContextWindow: View {

    @Environment(AppController.self) private var appController

    let queue: PlaybackQueue
    let currentIndex: Int
    let visualCenter: Double
    let rowHeight: CGFloat
    let visibleRows: Int
    let onDoubleClick: (Int) -> Void

    @State private var selectedIndex: Int?
    @State private var activatedIndex: Int?

    private var displayedIndices: [Int] {
        guard !queue.urls.isEmpty else {
            return []
        }

        let lower = max(0, Int(floor(visualCenter)) - 3)
        let upper = min(
            queue.urls.count - 1,
            Int(ceil(visualCenter)) + 3
        )

        guard lower <= upper else {
            return []
        }

        return Array(lower...upper)
    }

    var body: some View {
        ZStack {
            ForEach(displayedIndices, id: \.self) { index in
                PlaybackContextRow(
                    title: title(for: queue.urls[index]),
                    index: index,
                    visualCenter: visualCenter,
                    rowHeight: rowHeight,
                    isSelected: selectedIndex == index,
                    isActivated: activatedIndex == index,
                    onSelect: {
                        selectedIndex = index
                    },
                    onDoubleClick: {
                        selectedIndex = index
                        activatedIndex = index
                        onDoubleClick(index)
                    }
                )
                .offset(
                    y: (Double(index) - visualCenter) * rowHeight
                )
            }
        }
        .frame(height: rowHeight * CGFloat(visibleRows))
        .frame(maxWidth: .infinity)
        .background(contextBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            edgeFade
        }
        .overlay {
            EmptyView()
        }
        .onAppear {
            activatedIndex = currentIndex
        }
        .onChange(of: currentIndex) { _, newIndex in
            activatedIndex = newIndex
            selectedIndex = nil
        }
    }

    private var contextBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            }
    }

    private var edgeFade: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: rowHeight * 0.9)

            Spacer()

            LinearGradient(
                colors: [
                    Color.clear,
                    Color(nsColor: .controlBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: rowHeight * 0.9)
        }
        .allowsHitTesting(false)
    }

    private func title(for url: URL) -> String {
        if let track = appController.library.tracks.first(
            where: { $0.filePath == url }
        ) {
            return track.title.isEmpty
                ? url.deletingPathExtension().lastPathComponent
                : track.title
        }

        return url.deletingPathExtension().lastPathComponent
    }
}

private struct PlaybackContextRow: View {

    let title: String
    let index: Int
    let visualCenter: Double
    let rowHeight: CGFloat
    let isSelected: Bool
    let isActivated: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void

    @State private var isHovered = false

    private var distance: Double {
        abs(Double(index) - visualCenter)
    }

    private var isCurrent: Bool {
        distance < 0.01
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("◀")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(markerOpacity)
                .frame(width: 16)
                .rotationEffect(.degrees(isActivated ? 180 : 0))
                .animation(.easeInOut(duration: 0.22), value: isActivated)

            Text(title)
                .font(
                    .system(
                        size: fontSize,
                        weight: isCurrent ? .semibold : .regular
                    )
                )
                .foregroundStyle(
                    .primary.opacity(opacity)
                )
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)

            Text("▶")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(markerOpacity)
                .frame(width: 16)
                .rotationEffect(.degrees(isActivated ? -180 : 0))
                .animation(.easeInOut(duration: 0.22), value: isActivated)
        }
        .padding(.horizontal, 4)
        .frame(height: rowHeight)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
                .shadow(
                    color: isActivated ? .black.opacity(0.24) : .clear,
                    radius: isActivated ? 6 : 0,
                    x: 0,
                    y: 1
                )
                .padding(.horizontal, 6)
        }
        .contentShape(Rectangle())
        .overlay {
            MouseInputHandler { event in
                switch event {
                case .leftClick(isShiftPressed: _):
                    onSelect()
                case .leftDoubleClick(isShiftPressed: _):
                    onDoubleClick()
                case .rightClick:
                    break
                }
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .blur(radius: distance > 2.0 ? 0.6 : 0)
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

    private var markerOpacity: Color {
        if isActivated {
            return .primary.opacity(0.95)
        }

        if isSelected {
            return .secondary.opacity(0.72)
        }

        if distance < 1.5 {
            return .secondary.opacity(0.55)
        }

        return .secondary.opacity(0.38)
    }

    private var fontSize: CGFloat {
        if distance < 0.5 {
            return 16
        }

        if distance < 1.5 {
            return 14
        }

        return 12
    }

    private var opacity: Double {
        if distance < 0.5 {
            return 1.0
        }

        if distance < 1.5 {
            return 0.72
        }

        return 0.45
    }
}
