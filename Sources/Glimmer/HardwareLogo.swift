import Foundation

/// Schaltet das echte Logo. Das geht bisher nur an/aus; läuft ein Befehl noch, wird der nächste
/// Zustand gemerkt und danach gesetzt, damit zu schnelle Muster nichts aufstauen.
final class HardwareLogo: @unchecked Sendable {
    private static let overrideFlag = "logoOverrideActive"
    private static let previousFlag = "logoPreviousMode"

    private let queue = DispatchQueue(label: "de.karox.glimmer.logo")
    private let lock = NSLock()
    private var wanted: Bool?
    private var running = false
    private var applied: Bool?
    private let onSwitch: @Sendable (Int) -> Void

    init(onSwitch: @escaping @Sendable (Int) -> Void) {
        self.onSwitch = onSwitch
    }

    func begin() {
        queue.async {
            let defaults = UserDefaults.standard
            guard !defaults.bool(forKey: Self.overrideFlag) else { return }
            defaults.set(SystemCommands.storedLogoMode() ?? -1, forKey: Self.previousFlag)
            defaults.set(true, forKey: Self.overrideFlag)
        }
    }

    func set(on: Bool) {
        lock.lock()
        wanted = on
        let shouldStart = !running
        running = true
        lock.unlock()
        if shouldStart { queue.async { self.drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let next = wanted, next != applied else {
                wanted = nil
                running = false
                lock.unlock()
                return
            }
            wanted = nil
            lock.unlock()
            let result = SystemCommands.setLogo(on: next)
            applied = next
            onSwitch(result.milliseconds)
        }
    }

    /// Stellt den Zustand von vor Glimmer wieder her, auch nach einem Absturz beim nächsten Start.
    static func restoreIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: overrideFlag) else { return }
        let previous = defaults.object(forKey: previousFlag) as? Int ?? -1
        SystemCommands.setLogo(on: previous != 0)
        defaults.set(false, forKey: overrideFlag)
    }

    func end() {
        queue.sync {
            applied = nil
            Self.restoreIfNeeded()
        }
    }
}
