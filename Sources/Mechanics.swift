import Foundation

// Original function addresses and evidence are recorded in MECHANICS.md.
enum Mechanics {
    // 0x10009519c
    static let activationDelay = 0.2
    static let autoHide = 0.0
    static let overlaySize = 0.7
    static let overlayOpacity = 0.75
    // 0x10003930c: equality with 2.5 skips scheduling the display timer.
    static let neverDisplayDelay = 2.5
    // 0x10003b0b8, instructions 0x10003b374–0x10003b390
    static let doublePressInterval = 0.3
}

// A completed pair consumes the first press, matching the original timer reset.
struct DoublePressWindow {
    private var firstPress: TimeInterval?
    mutating func press(at time: TimeInterval) -> Bool {
        if let firstPress, time - firstPress < Mechanics.doublePressInterval {
            self.firstPress = nil
            return true
        }
        firstPress = time
        return false
    }
}
