import Foundation

/// Meldet Bewegung, wenn die Beschleunigung mehrere Messungen lang vom Ruhewert abweicht.
public struct MotionDetector: Sendable {
    public var threshold: Double
    public var requiredHits: Int
    public private(set) var lastDelta = 0.0

    private let smoothing = 0.02
    private var baseline: Acceleration?
    private var hits = 0

    public init(threshold: Double, requiredHits: Int = 3) {
        self.threshold = threshold
        self.requiredHits = requiredHits
    }

    public mutating func reset() {
        baseline = nil
        hits = 0
        lastDelta = 0
    }

    public mutating func feed(_ sample: Acceleration) -> Bool {
        guard let current = baseline else {
            baseline = sample
            return false
        }
        let dx = sample.x - current.x
        let dy = sample.y - current.y
        let dz = sample.z - current.z
        lastDelta = (dx * dx + dy * dy + dz * dz).squareRoot()
        if lastDelta >= threshold {
            hits += 1
            return hits >= requiredHits
        }
        hits = 0
        baseline = Acceleration(
            x: current.x + dx * smoothing,
            y: current.y + dy * smoothing,
            z: current.z + dz * smoothing
        )
        return false
    }
}
