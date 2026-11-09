import XCTest
@testable import GlimmerCore

final class CoreTests: XCTestCase {
    func testBlinkSwitchesAtHalfCycle() {
        XCTAssertEqual(LightPattern.blink.level(at: 0.1, cycle: 1), 1)
        XCTAssertEqual(LightPattern.blink.level(at: 0.6, cycle: 1), 0)
        XCTAssertEqual(LightPattern.blink.level(at: 1.1, cycle: 1), 1)
    }

    func testPulseIsSmooth() {
        XCTAssertEqual(LightPattern.pulse.level(at: 0, cycle: 2), 0, accuracy: 0.001)
        XCTAssertEqual(LightPattern.pulse.level(at: 1, cycle: 2), 1, accuracy: 0.001)
        XCTAssertEqual(LightPattern.pulse.level(at: 0.5, cycle: 2), 0.5, accuracy: 0.001)
    }

    func testDoubleFlashHasTwoFlashes() {
        let levels = stride(from: 0.0, to: 1.0, by: 0.05).map { LightPattern.doubleFlash.level(at: $0, cycle: 1) }
        let rises = zip([0.0] + levels, levels).filter { $0 == 0 && $1 == 1 }.count
        XCTAssertEqual(rises, 2)
    }

    func testDecodesCapturedAccelerometerReport() throws {
        let report: [UInt8] = [75, 216, 0, 0, 0, 0, 84, 5, 0, 0, 2, 7, 0, 0, 19, 3, 255, 255, 0, 253, 46, 0]
        let sample = try XCTUnwrap(SensorDecoding.acceleration(from: report))
        XCTAssertEqual(sample.x, 0.0208, accuracy: 0.001)
        XCTAssertEqual(sample.y, 0.0274, accuracy: 0.001)
        XCTAssertEqual(sample.z, -0.988, accuracy: 0.001)
    }

    func testDecodesCapturedLidReport() {
        XCTAssertEqual(SensorDecoding.lidAngle(from: [1, 113, 0]), 113)
        XCTAssertNil(SensorDecoding.lidAngle(from: [1]))
    }

    func testSudoersRulePassesVisudo() throws {
        let rule = try XCTUnwrap(PrivilegeRule.sudoers(user: "karox"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try rule.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/visudo")
        process.arguments = ["-cf", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testSudoersRuleAllowsOnlyListedCommands() throws {
        let rule = try XCTUnwrap(PrivilegeRule.sudoers(user: "karox"))
        XCTAssertFalse(rule.contains("ALL\n"))
        XCTAssertTrue(rule.hasPrefix("karox ALL=(root) NOPASSWD: /usr/bin/defaults write"))
        XCTAssertEqual(rule.components(separatedBy: "/usr/bin/").count - 1, 5)
    }

    func testSudoersRuleRejectsUnsafeUserNames() {
        XCTAssertNil(PrivilegeRule.sudoers(user: ""))
        XCTAssertNil(PrivilegeRule.sudoers(user: "a b"))
        XCTAssertNil(PrivilegeRule.sudoers(user: "a ALL=(ALL) ALL\nb"))
        XCTAssertNotNil(PrivilegeRule.sudoers(user: "karl.o-x_1"))
    }

    func testDetectorIgnoresNoiseAndSingleSpike() {
        var detector = MotionDetector(threshold: 0.05)
        let rest = Acceleration(x: 0, y: 0, z: -1)
        XCTAssertFalse(detector.feed(rest))
        for _ in 0..<50 { XCTAssertFalse(detector.feed(Acceleration(x: 0.005, y: 0, z: -1))) }
        XCTAssertFalse(detector.feed(Acceleration(x: 0.2, y: 0, z: -1)))
        XCTAssertFalse(detector.feed(rest))
    }

    func testDetectorTriggersOnSustainedMotion() {
        var detector = MotionDetector(threshold: 0.05)
        XCTAssertFalse(detector.feed(Acceleration(x: 0, y: 0, z: -1)))
        let moved = Acceleration(x: 0.2, y: 0, z: -1)
        XCTAssertFalse(detector.feed(moved))
        XCTAssertFalse(detector.feed(moved))
        XCTAssertTrue(detector.feed(moved))
    }
}
