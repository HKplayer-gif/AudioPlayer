import Foundation

struct PitchCycleState: Codable, Equatable {

    enum SortOrder: String, Codable {
        case ascending
        case descending
    }

    static let defaultBasePitches: [Int] = [0]

    var selectedBasePitches: [Int]
    var isEnabled: Bool
    var offset: Double
    var cycleIndex: Int
    var sortOrder: SortOrder

    static let `default` = PitchCycleState(
        selectedBasePitches: defaultBasePitches,
        isEnabled: false,
        offset: 0.0,
        cycleIndex: 0
    )

    init(
        selectedBasePitches: [Int] = Self.defaultBasePitches,
        isEnabled: Bool = false,
        offset: Double = 0.0,
        cycleIndex: Int = 0,
        sortOrder: SortOrder = .ascending
    ) {
        self.selectedBasePitches = selectedBasePitches
        self.isEnabled = isEnabled
        self.offset = offset
        self.cycleIndex = cycleIndex
        self.sortOrder = sortOrder
    }

    var sortedBasePitches: [Int] {
        switch sortOrder {
        case .ascending:
            return selectedBasePitches.sorted()
        case .descending:
            return selectedBasePitches.sorted(by: >)
        }
    }

    var availableBasePitches: [Int] {
        switch sortOrder {
        case .ascending:
            return Array(-12...12)
        case .descending:
            return Array((-12...12).reversed())
        }
    }

    private enum CodingKeys: String, CodingKey {
        case selectedBasePitches
        case isEnabled
        case offset
        case cycleIndex
        case sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        selectedBasePitches = try container.decode(
            [Int].self,
            forKey: .selectedBasePitches
        )
        isEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .isEnabled
        ) ?? false
        offset = try container.decode(
            Double.self,
            forKey: .offset
        )
        cycleIndex = try container.decode(
            Int.self,
            forKey: .cycleIndex
        )
        sortOrder = try container.decodeIfPresent(
            SortOrder.self,
            forKey: .sortOrder
        ) ?? .ascending
    }

    var currentBasePitch: Int? {
        let pitches = sortedBasePitches
        guard !pitches.isEmpty else {
            return nil
        }

        let safeIndex = min(
            max(cycleIndex, 0),
            pitches.count - 1
        )

        return pitches[safeIndex]
    }

    var currentEffectivePitch: Double? {
        guard let basePitch = currentBasePitch else {
            return nil
        }

        return Self.clampedEffectivePitch(
            basePitch: basePitch,
            offset: offset
        )
    }

    static func clampedEffectivePitch(
        basePitch: Int,
        offset: Double
    ) -> Double {
        min(
            max(
                Double(basePitch) + offset,
                -12.0
            ),
            12.0
        )
    }

    mutating func normalize() {
        selectedBasePitches = Array(
            Set(
                selectedBasePitches.filter {
                    (-12...12).contains($0)
                }
            )
        )

        switch sortOrder {
        case .ascending:
            selectedBasePitches.sort()
        case .descending:
            selectedBasePitches.sort(by: >)
        }

        offset = min(
            max(offset, -0.99),
            0.99
        )

        guard !selectedBasePitches.isEmpty else {
            cycleIndex = 0
            return
        }

        cycleIndex = min(
            max(cycleIndex, 0),
            selectedBasePitches.count - 1
        )
    }

    mutating func setSelection(_ pitches: Set<Int>) {
        selectedBasePitches = Array(
            pitches.filter {
                (-12...12).contains($0)
            }
        )

        switch sortOrder {
        case .ascending:
            selectedBasePitches.sort()
        case .descending:
            selectedBasePitches.sort(by: >)
        }

        cycleIndex = 0
    }

    mutating func setSortOrder(_ order: SortOrder) {
        sortOrder = order
    }

    mutating func setOffset(_ value: Double) {
        offset = min(
            max(value, -0.99),
            0.99
        )
    }

    mutating func resetOffset() {
        offset = 0.0
    }

    mutating func advanceCycle() {
        let count = selectedBasePitches.count

        guard count > 0 else {
            cycleIndex = 0
            return
        }

        cycleIndex = (cycleIndex + 1) % count
    }
}

@MainActor
@Observable
final class PitchCyclesStore {
    private let stateStore: StateStore
    private let fileName = "pitch-cycles.json"

    private(set) var state: PitchCycleState
    private(set) var savedState: PitchCycleState
    private var runtimeCycleIndex: Int

    init(
        stateStore: StateStore = StateStore()
    ) {
        self.stateStore = stateStore

        let loadedState =
            stateStore.load(
                PitchCycleState.self,
                from: fileName
            ) ?? .default

        var normalizedState = loadedState
        normalizedState.normalize()

        self.state = normalizedState
        self.savedState = normalizedState
        self.runtimeCycleIndex = normalizedState.cycleIndex
    }

    var selectedBasePitches: Set<Int> {
        Set(state.selectedBasePitches)
    }

    var isEnabled: Bool {
        state.isEnabled
    }

    var sortedBasePitches: [Int] {
        state.sortedBasePitches
    }

    var availableBasePitches: [Int] {
        state.availableBasePitches
    }

    var sortOrder: PitchCycleState.SortOrder {
        state.sortOrder
    }

    var offset: Double {
        state.offset
    }

    var cycleIndex: Int {
        state.cycleIndex
    }

    var currentBasePitch: Int? {
        runtimeBasePitch
    }

    var currentEffectivePitch: Double? {
        guard let basePitch = runtimeBasePitch else {
            return nil
        }

        return PitchCycleState.clampedEffectivePitch(
            basePitch: basePitch,
            offset: savedState.offset
        )
    }

    private var runtimeBasePitch: Int? {
        let pitches = savedState.sortedBasePitches
        guard !pitches.isEmpty else {
            return nil
        }

        let safeIndex = min(
            max(runtimeCycleIndex, 0),
            pitches.count - 1
        )

        return pitches[safeIndex]
    }

    func setSelection(_ pitches: Set<Int>) {
        state.setSelection(pitches)
    }

    func setEnabled(_ enabled: Bool) {
        state.isEnabled = enabled
        savedState.isEnabled = enabled

        do {
            try stateStore.save(
                savedState,
                to: fileName
            )
        } catch {
            
        }
    }

    func resetCycleForNewQueue() {
        runtimeCycleIndex = 0
    }

    func setSortOrder(_ order: PitchCycleState.SortOrder) {
        state.setSortOrder(order)
    }

    func setOffset(_ value: Double) {
        state.setOffset(value)
    }

    func resetOffset() {
        state.resetOffset()
    }

    func resetToDefault() {
        state = .default
    }

    func restoreLastSaved() {
        state = savedState
        runtimeCycleIndex = savedState.cycleIndex
    }

    func previousCycle() {
        let count = savedState.selectedBasePitches.count

        guard count > 0 else {
            runtimeCycleIndex = 0
            return
        }

        runtimeCycleIndex =
            (runtimeCycleIndex - 1 + count) % count
    }

    func nextCycle() {
        let count = savedState.selectedBasePitches.count

        guard count > 0 else {
            runtimeCycleIndex = 0
            return
        }

        runtimeCycleIndex =
            (runtimeCycleIndex + 1) % count
    }

    func save() {
        state.normalize()

        do {
            try stateStore.save(
                state,
                to: fileName
            )

            savedState = state
            runtimeCycleIndex = 0
        } catch {
            
        }
    }
}
