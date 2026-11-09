import GlimmerCore
import SwiftUI

struct LogoPreview: View {
    @ObservedObject var signal: LevelSignal

    private var level: Double { signal.level }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.13))
            Image(systemName: "circle.fill")
                .font(.system(size: 70))
                .foregroundStyle(.white.opacity(0.07 + 0.93 * level))
                .shadow(color: .white.opacity(0.75 * level), radius: 22 * level)
        }
        .frame(height: 170)
        .accessibilityLabel("Simuliertes Licht")
    }
}

/// Pegelanzeige wie beim Mikrofon-Check. Die Wurzelskala macht auch leichtes Tippen sichtbar.
struct SensitivityMeter: View {
    @ObservedObject var meter: MeterSignal
    let threshold: Double

    private func position(_ value: Double) -> Double {
        (min(value, 0.3) / 0.3).squareRoot()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(meter.level >= threshold ? Color.orange : Color.blue)
                        .frame(width: max(10, geometry.size.width * position(meter.level)))
                        .opacity(meter.level > 0 ? 1 : 0)
                    Rectangle()
                        .fill(.primary)
                        .frame(width: 2, height: 18)
                        .offset(x: geometry.size.width * position(threshold) - 1)
                }
            }
            .frame(height: 18)
            .accessibilityElement()
            .accessibilityLabel("Bewegungspegel")
            .accessibilityValue(meter.wouldTrigger ? "Würde auslösen" : "Unter der Schwelle")
            HStack {
                Text(meter.wouldTrigger ? "Würde auslösen" : "Tippe aufs MacBook")
                    .fontWeight(meter.wouldTrigger ? .semibold : .regular)
                    .foregroundStyle(meter.wouldTrigger ? Color.orange : Color.secondary)
                Spacer()
                Text("Regler rechts = empfindlicher")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }
}

struct RuleRow: View {
    let kind: EventKind
    let status: String
    @Binding var rule: EventRule
    let test: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(kind.title, isOn: $rule.enabled)
                Spacer()
                Button("Testen", action: test)
            }
            HStack {
                Picker("Muster", selection: $rule.pattern) {
                    ForEach(LightPattern.allCases.filter(\.isAnimated)) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 130)
                Spacer()
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct NoticeView: View {
    let accept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bevor du Glimmer nutzt").font(.title2.bold())
            Text("Glimmer ist ein inoffizielles, kostenloses Hobbyprojekt und steht in keiner Verbindung zu Apple.")
            Text("Die App nutzt undokumentierte Schnittstellen. Das echte Logo wurde noch auf keinem Gerät getestet, und macOS-Updates können Funktionen jederzeit abschalten.")
            Text("Der Alarm ändert Energieeinstellungen, verbraucht Akku und spielt eine laute Sirene ab. Er schützt nicht zuverlässig vor Diebstahl.")
            Text("Die Nutzung erfolgt auf eigene Gefahr und ohne Support.")
            HStack {
                Spacer()
                Button("Beenden") { NSApp.terminate(nil) }
                Button("Verstanden", action: accept)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var alarm: AlarmController
    @AppStorage("noticeAccepted") private var noticeAccepted = false

    private var alarmLabel: String {
        switch alarm.state {
        case .disarmed: "Unscharf"
        case .arming(let remaining): "Wird scharf in \(remaining) s"
        case .armed: "Scharf"
        case .triggered: "ALARM"
        }
    }

    var body: some View {
        if noticeAccepted {
            controls
        } else {
            NoticeView { noticeAccepted = true }
                .frame(width: 460)
        }
    }

    private var controls: some View {
        Form {
            Section {
                LogoPreview(signal: model.signal)
                Text(model.useRealLogo ? "Vorschau läuft parallel zum echten Logo." : "Simulation. Das echte Logo wird nicht angesteuert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Muster") {
                Picker("Modus", selection: $model.pattern) {
                    ForEach(LightPattern.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                LabeledContent("Zyklus") {
                    HStack {
                        Slider(value: $model.cycle, in: AppModel.cycleRange)
                        Text(String(format: "%.1f s", model.cycle))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .disabled(!model.pattern.isAnimated)
            }

            Section("Alarm") {
                LabeledContent("Status", value: alarmLabel)
                LabeledContent("Empfindlichkeit") {
                    Slider(value: $alarm.threshold, in: 0.02...0.3)
                        .environment(\.layoutDirection, .rightToLeft)
                }
                SensitivityMeter(meter: alarm.meter, threshold: alarm.threshold)
                if alarm.isActive {
                    LabeledContent("Sensoren") {
                        Text("Deckel \(alarm.liveAngle.map { "\($0)°" } ?? "–"), Bewegung \(String(format: "%.3f", alarm.liveDelta)) g")
                            .monospacedDigit()
                    }
                }
                HStack {
                    Button(alarm.isActive ? "Entschärfen" : "Scharf schalten") {
                        alarm.isActive ? alarm.disarm() : alarm.arm()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Sirene testen", action: alarm.testSiren)
                        .disabled(alarm.isActive)
                }
                if !alarm.note.isEmpty {
                    Text(alarm.note).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Echtes Logo") {
                Toggle("Logo ansteuern (experimentell)", isOn: $model.useRealLogo)
                    .disabled(!model.hasPrivileges)
                if model.hasPrivileges {
                    Button("Rechte entfernen", action: model.removePrivileges)
                        .disabled(model.isChangingPrivileges)
                } else {
                    Button("Rechte einrichten …", action: model.installPrivileges)
                        .disabled(model.isChangingPrivileges)
                    Text("Einmalig mit deinem Passwort. Nötig für das Logo und den Alarm bei geschlossenem Deckel. Das Logo braucht ein MacBook Pro mit PROLED-Display.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !model.privilegeNote.isEmpty {
                    Text(model.privilegeNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if model.useRealLogo {
                    Text("Vorerst nur an/aus. Pulsieren wird auf dem Logo zu Blinken.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let milliseconds = model.lastSwitchMilliseconds {
                    LabeledContent("Letzter Schaltvorgang", value: "\(milliseconds) ms")
                }
            }

            Section("Ereignisse") {
                RuleRow(kind: .mail, status: model.mailStatus, rule: $model.mailRule) { model.fire(.mail) }
                RuleRow(kind: .message, status: model.messageStatus, rule: $model.messageRule) { model.fire(.message) }
                LabeledContent("Anruf", value: "Noch nicht möglich")
            }

        }
        .formStyle(.grouped)
        .frame(width: 460, height: 780)
        .onAppear { alarm.setMetering(true) }
        .onDisappear { alarm.setMetering(false) }
    }
}
