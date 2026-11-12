import Foundation

@main struct MechanicsCheck {
    static func main() {
        var pair = DoublePressWindow()
        precondition(!pair.press(at: 10))
        precondition(pair.press(at: 10.2))
        precondition(!pair.press(at: 10.25), "第三次按下必须开始新的一对")
        precondition(pair.press(at: 10.4))
        var expired = DoublePressWindow()
        precondition(!expired.press(at: 0))
        precondition(!expired.press(at: 0.3), "到期后不能触发双击")
        precondition(expired.press(at: 0.4))
        precondition(Mechanics.neverDisplayDelay == 2.5)
        precondition(Mechanics.activationDelay == 0.2)
        precondition(Mechanics.overlaySize == 0.7 && Mechanics.overlayOpacity == 0.75)
        print("机制验证通过：双击配对、三连按、超时及恢复常量")
    }
}
