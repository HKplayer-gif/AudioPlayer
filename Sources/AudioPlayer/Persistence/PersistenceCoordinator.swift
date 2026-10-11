import Foundation
import Observation

@Observable
final class PersistenceCoordinator {

    private let stateStore: StateStore
    private let stateFileName = "state.json"
    private let queueResumeFileName = "queue-resume.json"

    private(set) var state: PersistentState

    init(stateStore: StateStore = StateStore()) {
        self.stateStore = stateStore

        if let savedState = stateStore.load(
            PersistentState.self,
            from: stateFileName
        ) {
            state = savedState
        } else {
            state = .default
        }
    }

    var playerState: PlayerState {
        state.player
    }

    var appState: AppState {
        state.app
    }

    func reportPlayer(_ playerState: PlayerState) {
        state.player = playerState
        save()
    }

    func reportApp(_ appState: AppState) {

        
        state.app = appState
        save()
    }

    func loadQueueResume() -> QueueResumeSnapshot? {
        stateStore.load(
            QueueResumeSnapshot.self,
            from: queueResumeFileName
        )
    }

    func saveQueueResume(_ snapshot: QueueResumeSnapshot) {
        do {
            try stateStore.save(
                snapshot,
                to: queueResumeFileName
            )
        } catch {
            
        }
    }

    func clearQueueResume() {
        do {
            try stateStore.remove(queueResumeFileName)
        } catch {
            
        }
    }

    func resetToDefault() {
        state = .default
        save()
    }

    func save() {
        do {
            try stateStore.save(
                state,
                to: stateFileName
            )
        } catch {
            
        }
    }
}
