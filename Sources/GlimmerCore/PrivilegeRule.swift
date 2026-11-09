import Foundation

/// Die sudo-Regel, die Glimmer genau die nötigen Befehle ohne Passwort erlaubt.
public enum PrivilegeRule {
    public static let targetPath = "/etc/sudoers.d/glimmer"

    private static let commands = [
        "/usr/bin/defaults write com.apple.CoreBrightness LEBacklightMode -int 0",
        "/usr/bin/defaults delete com.apple.CoreBrightness LEBacklightMode",
        "/usr/bin/defaults read com.apple.CoreBrightness LEBacklightMode",
        "/usr/bin/pmset -a disablesleep 0",
        "/usr/bin/pmset -a disablesleep 1",
    ]

    /// Gibt nil zurück, wenn der Benutzername Zeichen enthält, die die Regel verändern könnten.
    public static func sudoers(user: String) -> String? {
        guard !user.isEmpty, user.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }) else {
            return nil
        }
        return "\(user) ALL=(root) NOPASSWD: \(commands.joined(separator: ", "))\n"
    }
}
