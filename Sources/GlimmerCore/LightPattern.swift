import Foundation

public enum LightPattern: String, CaseIterable, Codable, Identifiable, Sendable {
    case normal, off, blink, pulse, doubleFlash

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .normal: "Normal"
        case .off: "Aus"
        case .blink: "Blinken"
        case .pulse: "Pulsieren"
        case .doubleFlash: "Doppelblitz"
        }
    }

    public var isAnimated: Bool {
        switch self {
        case .normal, .off: false
        case .blink, .pulse, .doubleFlash: true
        }
    }

    /// Helligkeit von 0 bis 1 zum Zeitpunkt `time` bei einer Zykluslänge `cycle` in Sekunden.
    public func level(at time: Double, cycle: Double) -> Double {
        let phase = (time / max(cycle, 0.001)).truncatingRemainder(dividingBy: 1)
        switch self {
        case .normal: return 1
        case .off: return 0
        case .blink: return phase < 0.5 ? 1 : 0
        case .pulse: return 0.5 - 0.5 * cos(2 * .pi * phase)
        case .doubleFlash: return phase < 0.1 || (phase >= 0.2 && phase < 0.3) ? 1 : 0
        }
    }
}
