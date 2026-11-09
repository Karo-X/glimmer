import Foundation

public struct Acceleration: Equatable, Sendable {
    public var x, y, z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public enum SensorDecoding {
    /// Dekodiert einen 22-Byte-Bericht des Sensors `accel`. Werte in g.
    public static func acceleration(from report: [UInt8]) -> Acceleration? {
        guard report.count >= 18 else { return nil }
        func axis(_ offset: Int) -> Double {
            let raw = (0..<4).reduce(UInt32(0)) { $0 | UInt32(report[offset + $1]) << (8 * UInt32($1)) }
            return Double(Int32(bitPattern: raw)) / 65536
        }
        return Acceleration(x: axis(6), y: axis(10), z: axis(14))
    }

    /// Dekodiert den Feature-Bericht des Sensors `las`. Wert in Grad.
    public static func lidAngle(from report: [UInt8]) -> Int? {
        guard report.count >= 3 else { return nil }
        return Int(report[1]) | Int(report[2]) << 8
    }
}
