import Foundation
import GlimmerCore

/// Getrennt vom AlarmController, damit der Pegel nur seine eigene Anzeige neu zeichnet.
@MainActor
final class MeterSignal: ObservableObject {
    @Published var level = 0.0
    @Published var wouldTrigger = false
}

@MainActor
final class AlarmController: ObservableObject {
    enum State: Equatable {
        case disarmed
        case arming(remaining: Int)
        case armed
        case triggered
    }

    private nonisolated static let sleepFlag = "sleepOverrideActive"
    private static let armDelay = 10
    private static let lidTolerance = 4
    private static let minimumBattery = 15
    private static let sirenLimit: TimeInterval = 300

    @Published private(set) var state = State.disarmed
    @Published private(set) var note = ""
    @Published private(set) var liveAngle: Int?
    @Published private(set) var liveDelta = 0.0
    @Published var threshold = UserDefaults.standard.object(forKey: "alarmThreshold") as? Double ?? 0.05 {
        didSet {
            UserDefaults.standard.set(threshold, forKey: "alarmThreshold")
            detector.threshold = threshold
        }
    }

    var onStateChange: (() -> Void)?
    let meter = MeterSignal()
    /// Für den Selbsttest: kein Ton, keine Änderung der Lautstärke.
    var isSilent = false

    private let sensors = SensorHub()
    private let siren = Siren()
    private var detector = MotionDetector(threshold: 0.05)
    private var clock: Timer?
    private var sirenStop: Timer?
    private var activity: NSObjectProtocol?
    private var baselineAngle: Int?
    private var previousVolume: Int?
    private var sleepOverride = false
    private var ticks = 0
    private var isMetering = false
    private var meterClock: Timer?
    private var meterPeak = 0.0
    private var triggerShownUntil = Date.distantPast

    var isActive: Bool { state != .disarmed }

    nonisolated static func restoreSleepIfNeeded() {
        guard UserDefaults.standard.bool(forKey: sleepFlag) else { return }
        if SystemCommands.setSleepDisabled(false) {
            UserDefaults.standard.set(false, forKey: sleepFlag)
        }
    }

    /// Zeigt die Bewegung live an, ohne den Alarm auszulösen.
    func setMetering(_ enabled: Bool) {
        guard enabled != isMetering else { return }
        isMetering = enabled
        if enabled {
            startSensorsForMeter()
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateMeter() }
            }
            RunLoop.main.add(timer, forMode: .common)
            meterClock = timer
        } else {
            meterClock?.invalidate()
            meterClock = nil
            if state == .disarmed {
                sensors.stop()
                sensors.onSample = nil
            }
            meter.level = 0
            meter.wouldTrigger = false
        }
    }

    private func startSensorsForMeter() {
        guard state == .disarmed else { return }
        detector.threshold = threshold
        detector.reset()
        attachSensors()
        sensors.start()
    }

    private func attachSensors() {
        sensors.onSample = { [weak self] sample in
            MainActor.assumeIsolated { self?.handle(sample) }
        }
    }

    private func updateMeter() {
        meter.level = max(meterPeak, meter.level * 0.85)
        meterPeak = 0
        let shouldShow = Date() < triggerShownUntil
        if meter.wouldTrigger != shouldShow { meter.wouldTrigger = shouldShow }
    }

    func arm() {
        guard state == .disarmed else { return }
        detector.threshold = threshold
        detector.reset()
        attachSensors()
        guard sensors.start() else {
            note = "Bewegungssensor nicht lesbar."
            return
        }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .latencyCritical, .userInitiated],
            reason: "Glimmer-Alarm ist scharf"
        )
        sleepOverride = SystemCommands.setSleepDisabled(true)
        if sleepOverride {
            UserDefaults.standard.set(true, forKey: Self.sleepFlag)
            note = "Bleibt auch zugeklappt wach. Der Akkuschutz stoppt bei \(Self.minimumBattery) %."
        } else {
            note = "Ohne Rechte schläft der Mac beim Zuklappen ein, der Alarm ist dann aus. Du kannst sie oben einrichten."
        }
        state = .arming(remaining: Self.armDelay)
        ticks = 0
        startClock()
        onStateChange?()
    }

    func disarm(reason: String = "") {
        guard state != .disarmed else { return }
        clock?.invalidate()
        clock = nil
        stopSiren()
        sensors.stop()
        sensors.onSample = nil
        if sleepOverride, SystemCommands.setSleepDisabled(false) {
            UserDefaults.standard.set(false, forKey: Self.sleepFlag)
        }
        sleepOverride = false
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
        baselineAngle = nil
        liveAngle = nil
        liveDelta = 0
        state = .disarmed
        note = reason
        onStateChange?()
        if isMetering { startSensorsForMeter() }
    }

    func testSiren() {
        guard state == .disarmed else { return }
        siren.start(gain: 0.35)
        sirenStop?.invalidate()
        sirenStop = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.siren.stop() }
        }
    }

    private func startClock() {
        clock?.invalidate()
        clock = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        ticks += 1
        liveAngle = sensors.lidAngle()
        liveDelta = detector.lastDelta
        if ticks % 120 == 0,
           let battery = SystemCommands.batteryPercentIfOnBattery(), battery <= Self.minimumBattery {
            disarm(reason: "Automatisch entschärft: Akku bei \(battery) %.")
            return
        }
        switch state {
        case .arming(let remaining):
            guard ticks % 4 == 0 else { return }
            if remaining <= 1 {
                detector.reset()
                baselineAngle = liveAngle
                state = .armed
                onStateChange?()
            } else {
                state = .arming(remaining: remaining - 1)
            }
        case .armed:
            if let liveAngle, let baselineAngle, abs(liveAngle - baselineAngle) >= Self.lidTolerance {
                trigger()
            }
        case .disarmed, .triggered:
            break
        }
    }

    private func handle(_ sample: Acceleration) {
        let moved = detector.feed(sample)
        meterPeak = max(meterPeak, detector.lastDelta)
        if moved { triggerShownUntil = Date().addingTimeInterval(1.5) }
        if moved, state == .armed { trigger() }
    }

    private func trigger() {
        guard state == .armed else { return }
        state = .triggered
        if !isSilent {
            previousVolume = SystemCommands.outputVolume()
            SystemCommands.setOutputVolume(100)
        }
        siren.start(gain: isSilent ? 0 : 1)
        sirenStop?.invalidate()
        sirenStop = Timer.scheduledTimer(withTimeInterval: Self.sirenLimit, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.rearm() }
        }
        onStateChange?()
    }

    private func stopSiren() {
        sirenStop?.invalidate()
        sirenStop = nil
        siren.stop()
        if let previousVolume {
            SystemCommands.setOutputVolume(previousVolume)
        }
        previousVolume = nil
    }

    private func rearm() {
        stopSiren()
        detector.reset()
        baselineAngle = liveAngle
        state = .armed
        onStateChange?()
    }
}
