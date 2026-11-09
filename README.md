# Glimmer

Menüleisten-App für macOS: lässt das Logo auf dem MacBook Pro mit PROLED-XDR-Display blinken
oder pulsieren, reagiert auf Mail und iMessage und enthält einen Bewegungsalarm.
Ohne dieses MacBook läuft das Logo als Simulation im Fenster.

Inoffizielles Hobbyprojekt, ohne Verbindung zu Apple. Bitte zuerst
[Resources/Hinweise.txt](Resources/Hinweise.txt) lesen.

## Selbst bauen

Es gibt keine fertige App zum Herunterladen. Glimmer wird selbst gebaut, das geht ohne
Apple-Entwicklerkonto und ohne Zertifikat.

Voraussetzungen: macOS 14 oder neuer, Xcode oder die Command Line Tools
(`xcode-select --install`).

    git clone https://github.com/Karo-X/glimmer.git
    cd glimmer
    ./scripts/build.sh
    open build/Glimmer.app

Dauerhaft installieren: `build/Glimmer.app` nach `/Applications` ziehen.

`build.sh` signiert mit einem „Apple Development“-Zertifikat, falls eins im Schlüsselbund
liegt, sonst ad hoc. Eine selbst gebaute App wird von macOS nicht blockiert.
Nach jedem neuen Bauen fragt macOS die Freigaben (Festplattenvollzugriff, Mail) unter
Umständen erneut ab.

Tests: `swift test`. Prüfung ohne Oberfläche und ohne Ton:
`build/Glimmer.app/Contents/MacOS/Glimmer --selftest`.

## Einrichten

- **Logo und Zuklapp-Alarm:** in der App „Rechte einrichten“ klicken. Das legt nach der
  Passwortabfrage `/etc/sudoers.d/glimmer` an und erlaubt genau die nötigen `defaults`- und
  `pmset`-Befehle (siehe `Sources/GlimmerCore/PrivilegeRule.swift`). „Rechte entfernen“
  löscht die Datei wieder.
- **iMessage:** Glimmer unter Systemeinstellungen > Datenschutz & Sicherheit >
  Festplattenvollzugriff freigeben.
- **Mail:** beim ersten Start die Automation-Abfrage bestätigen.

## Stand

Das echte Logo lässt sich bisher nur an- und ausschalten; Pulsieren wird dort zu Blinken.
Die Steuerung des echten Logos ist noch auf keinem Gerät getestet. Wer so ein MacBook hat:
`./scripts/logo-test.sh probe` liest nur und schreibt einen Bericht, `DRY_RUN=1` zeigt bei
den anderen Befehlen nur an, was passieren würde.

Sensoren (`accel`, `las`) sind undokumentierte Schnittstellen. Stufenloses Dimmen ist noch
nicht gefunden. Anrufe werden noch nicht erkannt.

## Lizenz

GPL-3.0, siehe [LICENSE](LICENSE). Wer eine veränderte Version weitergibt, muss deren
Quellcode unter derselben Lizenz offenlegen.
