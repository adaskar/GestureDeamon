import Foundation

public struct SmoothScrollConfig: Codable, Equatable {
    public var enabled: Bool
    public var reverseVertical: Bool
    public var reverseHorizontal: Bool
    public var smoothVertical: Bool
    public var smoothHorizontal: Bool
    public var simulateTrackpad: Bool
    public var speed: Double
    public var step: Double
    public var duration: Double
    public var deadZone: Double
    public var dashModifier: String?
    public var toggleModifier: String?
    public var blockModifier: String?

    public init(
        enabled: Bool = true,
        reverseVertical: Bool = false,
        reverseHorizontal: Bool = false,
        smoothVertical: Bool = true,
        smoothHorizontal: Bool = true,
        simulateTrackpad: Bool = true,
        speed: Double = 2.70,
        step: Double = 33.6,
        duration: Double = 4.35,
        deadZone: Double = 1.0,
        dashModifier: String? = "Option",
        toggleModifier: String? = "Shift",
        blockModifier: String? = "Command"
    ) {
        self.enabled = enabled
        self.reverseVertical = reverseVertical
        self.reverseHorizontal = reverseHorizontal
        self.smoothVertical = smoothVertical
        self.smoothHorizontal = smoothHorizontal
        self.simulateTrackpad = simulateTrackpad
        self.speed = speed
        self.step = step
        self.duration = duration
        self.deadZone = deadZone
        self.dashModifier = dashModifier
        self.toggleModifier = toggleModifier
        self.blockModifier = blockModifier
    }

    public var durationTransition: Double {
        // Upper limit matches slider range (5.0 + 0.2 offset so result is never 0)
        let upperLimit = 5.0 + 0.2
        let val = 1.0 - (duration / upperLimit).squareRoot()
        return Double(round(1000.0 * val) / 1000.0)
    }

    enum CodingKeys: String, CodingKey {
        case enabled = "Enabled"
        case reverseVertical = "ReverseVertical"
        case reverseHorizontal = "ReverseHorizontal"
        case smoothVertical = "SmoothVertical"
        case smoothHorizontal = "SmoothHorizontal"
        case simulateTrackpad = "SimulateTrackpad"
        case speed = "Speed"
        case step = "Step"
        case duration = "Duration"
        case deadZone = "DeadZone"
        case dashModifier = "DashModifier"
        case toggleModifier = "ToggleModifier"
        case blockModifier = "BlockModifier"
    }
}

