import AppKit
import Foundation
import GlimmerCore

struct EventRule: Codable, Equatable {
    var enabled = true
    var pattern = LightPattern.doubleFlash
    var cycle = 0.8
    var duration = 6.0
}

enum EventKind: String, CaseIterable, Identifiable {
    case mail, message

    var id: String { rawValue }
    var title: String { self == .mail ? "Neue Mail" : "iMessage" }
}

/// Getrennt vom AppModel, damit 30 Bilder pro Sekunde nur das Logo neu zeichnen.
@MainActor
final class LevelSignal: ObservableObject {
    @Published var level = 1.0
}

@MainActor
final class AppModel: ObservableObject {
    @Published var pattern = LightPattern(rawValue: UserDefaults.standard.string(forKey: "pattern") ?? "") ?? .pulse {
        didSet {
            UserDefaults.standard.set(pattern.rawValue, forKey: "pattern")
            refreshEngine()
        }
    }
    @Published var cycle = UserDefaults.standard.object(forKey: "cycle") as? Double ?? 1.5 {
        didSet { UserDefaults.standard.set(cycle, forKey: "cycle") }
    }
    @Published var useRealLogo = false {
        didSet { realLogoChanged(from: oldValue) }
    }
    @Published var mailRule = AppModel.loadRule(.mail) { didSet { save(mailRule, .mail); updateWatchers() } }
    @Published var messageRule = AppModel.loadRule(.message) { didSet { save(messageRule, .message); updateWatchers() } }

    @Published private(set) var hasPrivileges = false
    @Published private(set) var lastSwitchMilliseconds: Int?
    @Published private(set) var privilegeNote = ""
    @Published private(set) var isChangingPrivileges = false
    @Published private(set) var mailStatus = "Wird geprüft …"
    @Published private(set) var messageStatus = "Wird geprüft …"
    @Published private(set) var eventBanner = ""

    let alarm = AlarmController()
    let signal = LevelSignal()

    private var overlay: (pattern: LightPattern, cycle: Double, until: Date)?
    private var engine: Timer?
    private let started = Date()
    private lazy var hardware = HardwareLogo { [weak self] milliseconds in
        Task { @MainActor in self?.lastSwitchMilliseconds = milliseconds }
    }
    private var mailWatcher: CounterWatcher<Int>?
    private var messageWatcher: CounterWatcher<Int64>?

    private static let alarmCycle = 0.4
    static let cycleRange = 0.2...4.0

    init() {
        alarm.onStateChange = { [weak self] in self?.refreshEngine() }
        Task { [weak self] in
            let privileges = await Task.detached {
                HardwareLogo.restoreIfNeeded()
                AlarmController.restoreSleepIfNeeded()
                return SystemCommands.hasPrivileges
            }.value
            self?.hasPrivileges = privileges
        }
        updateWatchers()
        refreshEngine()
    }

    private static func loadRule(_ kind: EventKind) -> EventRule {
        guard let data = UserDefaults.standard.data(forKey: "rule.\(kind.rawValue)"),
              let rule = try? JSONDecoder().decode(EventRule.self, from: data)
        else { return EventRule() }
        return rule
    }

    private func save(_ rule: EventRule, _ kind: EventKind) {
        UserDefaults.standard.set(try? JSONEncoder().encode(rule), forKey: "rule.\(kind.rawValue)")
    }

    private func updateWatchers() {
        if mailRule.enabled, mailWatcher == nil {
            let watcher = CounterWatcher<Int>(interval: 15, read: { SystemCommands.unreadMailCount() }) { [weak self] readable, increased in
                Task { @MainActor in
                    self?.mailStatus = readable ? "Aktiv" : "Mail läuft nicht oder Zugriff fehlt"
                    if increased { self?.fire(.mail) }
                }
            }
            watcher.start()
            mailWatcher = watcher
        } else if !mailRule.enabled {
            mailWatcher?.stop()
            mailWatcher = nil
            mailStatus = "Aus"
        }
        if messageRule.enabled, messageWatcher == nil {
            let watcher = CounterWatcher<Int64>(interval: 5, read: { MessagesDatabase.latestIncomingRowID() }) { [weak self] readable, increased in
                Task { @MainActor in
                    self?.messageStatus = readable ? "Aktiv" : "Voller Festplattenzugriff fehlt"
                    if increased { self?.fire(.message) }
                }
            }
            watcher.start()
            messageWatcher = watcher
        } else if !messageRule.enabled {
            messageWatcher?.stop()
            messageWatcher = nil
            messageStatus = "Aus"
        }
    }

    func fire(_ kind: EventKind) {
        let rule = kind == .mail ? mailRule : messageRule
        overlay = (rule.pattern, rule.cycle, Date().addingTimeInterval(rule.duration))
        eventBanner = kind.title
        refreshEngine()
    }

    private var activePattern: (pattern: LightPattern, cycle: Double) {
        if alarm.state == .triggered { return (.blink, Self.alarmCycle) }
        if let overlay { return (overlay.pattern, overlay.cycle) }
        return (pattern, cycle)
    }

    private func refreshEngine() {
        tick()
        let needsTimer = activePattern.pattern.isAnimated || overlay != nil
        if needsTimer, engine == nil {
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            engine = timer
        } else if !needsTimer {
            engine?.invalidate()
            engine = nil
        }
    }

    private func tick() {
        if let current = overlay, current.until <= Date() {
            overlay = nil
            eventBanner = ""
            refreshEngine()
            return
        }
        let active = activePattern
        let level = active.pattern.level(at: Date().timeIntervalSince(started), cycle: active.cycle)
        if isWindowVisible {
            signal.level = level
        }
        if useRealLogo {
            hardware.set(on: level >= 0.5)
        }
    }

    private var isWindowVisible: Bool {
        NSApp?.windows.contains { $0.title == "Glimmer" && $0.occlusionState.contains(.visible) } ?? false
    }

    private func realLogoChanged(from oldValue: Bool) {
        guard useRealLogo != oldValue else { return }
        if useRealLogo {
            hardware.begin()
            refreshEngine()
        } else {
            let hardware = hardware
            Task.detached { hardware.end() }
        }
    }

    func installPrivileges() {
        changePrivileges(success: "Rechte eingerichtet.") { SystemCommands.installPrivileges() }
    }

    func removePrivileges() {
        alarm.disarm()
        useRealLogo = false
        changePrivileges(success: "Rechte entfernt.") { SystemCommands.removePrivileges() }
    }

    private func changePrivileges(
        success: String,
        _ change: @escaping @Sendable () -> SystemCommands.PrivilegeChange
    ) {
        guard !isChangingPrivileges else { return }
        isChangingPrivileges = true
        privilegeNote = ""
        Task { [weak self] in
            let (outcome, privileges) = await Task.detached { (change(), SystemCommands.hasPrivileges) }.value
            guard let self else { return }
            hasPrivileges = privileges
            isChangingPrivileges = false
            switch outcome {
            case .done: privilegeNote = success
            case .cancelled: privilegeNote = "Abgebrochen."
            case .failed: privilegeNote = "Das hat nicht geklappt."
            }
        }
    }

    func shutdown() {
        alarm.disarm()
        if useRealLogo {
            hardware.end()
        }
    }
}
