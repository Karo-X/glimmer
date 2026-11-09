import Foundation
import GlimmerCore
import IOKit.ps

enum SystemCommands {
    private static let domain = "com.apple.CoreBrightness"
    private static let key = "LEBacklightMode"

    struct Result {
        var succeeded: Bool
        var output: String
        var errors = ""
        var milliseconds: Int
    }

    @discardableResult
    static func run(_ path: String, _ arguments: [String]) -> Result {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        let start = Date()
        do {
            try process.run()
        } catch {
            return Result(succeeded: false, output: "", milliseconds: 0)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let errorText = errors.fileHandleForReading.readDataToEndOfFile()
        return Result(
            succeeded: process.terminationStatus == 0,
            output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            errors: String(decoding: errorText, as: UTF8.self),
            milliseconds: Int(Date().timeIntervalSince(start) * 1000)
        )
    }

    private static func sudo(_ arguments: [String]) -> Result {
        run("/usr/bin/sudo", ["-n"] + arguments)
    }

    /// Probiert den harmlosen Lesebefehl aus. `sudo -l` taugt nicht: Es meldet auch Befehle als
    /// erlaubt, für die ein Passwort nötig wäre. Fehlt nur der Schlüssel, meldet `defaults` den
    /// Fehler und nicht `sudo`.
    static var hasPrivileges: Bool {
        !sudo(["/usr/bin/defaults", "read", domain, key]).errors.contains("sudo:")
    }

    /// Führt einen festen Befehl nach der macOS-Passwortabfrage als root aus.
    private static func runAsAdmin(_ command: String, prompt: String) -> Result {
        run("/usr/bin/osascript", ["-e", "do shell script \"\(command)\" with prompt \"\(prompt)\" with administrator privileges"])
    }

    enum PrivilegeChange: Equatable {
        case done, cancelled, failed
    }

    private static func outcome(_ result: Result) -> PrivilegeChange {
        if result.succeeded { return .done }
        return result.errors.contains("-128") ? .cancelled : .failed
    }

    static func installPrivileges() -> PrivilegeChange {
        guard let rule = PrivilegeRule.sudoers(user: NSUserName()) else { return .failed }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("glimmer-\(UUID().uuidString)")
        guard FileManager.default.createFile(
            atPath: file.path,
            contents: Data(rule.utf8),
            attributes: [.posixPermissions: 0o600]
        ) else { return .failed }
        defer { try? FileManager.default.removeItem(at: file) }
        guard run("/usr/sbin/visudo", ["-cf", file.path]).succeeded else { return .failed }
        return outcome(runAsAdmin(
            "/usr/bin/install -m 0440 -o root -g wheel '\(file.path)' \(PrivilegeRule.targetPath)",
            prompt: "Glimmer möchte das Logo steuern und den Mac beim Alarm wach halten."
        ))
    }

    static func removePrivileges() -> PrivilegeChange {
        outcome(runAsAdmin(
            "/bin/rm -f \(PrivilegeRule.targetPath)",
            prompt: "Glimmer möchte seine Berechtigung wieder entfernen."
        ))
    }

    @discardableResult
    static func setLogo(on: Bool) -> Result {
        on
            ? sudo(["/usr/bin/defaults", "delete", domain, key])
            : sudo(["/usr/bin/defaults", "write", domain, key, "-int", "0"])
    }

    static func storedLogoMode() -> Int? {
        Int(sudo(["/usr/bin/defaults", "read", domain, key]).output)
    }

    static func setSleepDisabled(_ disabled: Bool) -> Bool {
        sudo(["/usr/bin/pmset", "-a", "disablesleep", disabled ? "1" : "0"]).succeeded
    }

    static func outputVolume() -> Int? {
        Int(run("/usr/bin/osascript", ["-e", "output volume of (get volume settings)"]).output)
    }

    static func setOutputVolume(_ volume: Int) {
        run("/usr/bin/osascript", ["-e", "set volume output volume \(volume) without output muted"])
    }

    /// Ungelesene Mails im Eingang, oder nil wenn Mail nicht läuft oder den Zugriff verweigert.
    static func unreadMailCount() -> Int? {
        let script = """
        if application "Mail" is running then
            tell application "Mail" to return unread count of inbox
        end if
        """
        return Int(run("/usr/bin/osascript", ["-e", script]).output)
    }

    static func batteryPercentIfOnBattery() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }
            return current * 100 / maximum
        }
        return nil
    }
}
