import AppKit
import GlimmerCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { model?.shutdown() }
    }
}

struct GlimmerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Glimmer", id: "main") {
            ContentView(model: model, alarm: model.alarm)
                .onAppear { delegate.model = model }
        }
        .windowResizability(.contentSize)

        MenuBarExtra("Glimmer", systemImage: "sparkles") {
            Button("Glimmer öffnen") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            Button(model.alarm.isActive ? "Alarm entschärfen" : "Alarm scharf schalten") {
                model.alarm.isActive ? model.alarm.disarm() : model.alarm.arm()
            }
            Divider()
            Button("Beenden") { NSApp.terminate(nil) }
        }
    }
}

@MainActor
enum SelfTest {
    /// Prüft Sensoren und Audio ohne Oberfläche und ohne hörbaren Ton.
    static func run() {
        let sensors = SensorHub()
        var detector = MotionDetector(threshold: 0.05)
        var samples = 0
        var peak = 0.0
        sensors.onSample = { sample in
            samples += 1
            _ = detector.feed(sample)
            peak = max(peak, detector.lastDelta)
        }
        print("Sensoren gestartet:", sensors.start())
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        print("Deckelwinkel:", sensors.lidAngle().map(String.init) ?? "nicht lesbar")
        print("Bewegungswerte in 2 s:", samples, "Spitze:", String(format: "%.4f g", peak))
        sensors.stop()
        let siren = Siren()
        siren.start(gain: 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        print("Audio läuft (lautlos):", siren.isRunning)
        siren.stop()
        print("Rechte eingerichtet:", SystemCommands.hasPrivileges)
        print("Akku:", SystemCommands.batteryPercentIfOnBattery().map { "\($0) %" } ?? "Netzbetrieb")
        print("iMessage lesbar:", MessagesDatabase.latestIncomingRowID() != nil)
        alarmRun()
    }

    /// Lässt den Alarm lautlos durchlaufen. Die winzige Schwelle löst schon durch Sensorrauschen aus.
    private static func alarmRun() {
        let alarm = AlarmController()
        alarm.isSilent = true
        alarm.threshold = 0.0002
        var states = [AlarmController.State]()
        alarm.onStateChange = { states.append(alarm.state) }
        alarm.setMetering(true)
        var meterPeak = 0.0
        let meterEnd = Date().addingTimeInterval(1)
        while Date() < meterEnd {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            meterPeak = max(meterPeak, alarm.meter.level)
        }
        print("Pegel in 1 s:", String(format: "%.4f g", meterPeak), "würde auslösen:", alarm.meter.wouldTrigger)
        alarm.arm()
        let deadline = Date().addingTimeInterval(14)
        while alarm.state != .triggered, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
        alarm.disarm()
        alarm.setMetering(false)
        UserDefaults.standard.removeObject(forKey: "alarmThreshold")
        print("Alarmablauf:", states)
        print("Hinweis:", alarm.note.isEmpty ? "-" : alarm.note)
    }
}

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            MainActor.assumeIsolated { SelfTest.run() }
        } else {
            GlimmerApp.main()
        }
    }
}
