import Foundation

enum InputEvent {
    case leftClick(isShiftPressed: Bool)
    case leftDoubleClick(isShiftPressed: Bool)
    case rightClick
}
