import Foundation

enum L10n {
    static func string(_ key: String) -> String {
        // Localizations live in the .app's Contents/Resources (Bundle.main),
        // generated from Localizable.xcstrings by scripts/gen-localizations.sh.
        let value = NSLocalizedString(key, bundle: Bundle.main, value: "", comment: "")
        return value.isEmpty || value == key ? key : value
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), arguments: arguments)
    }
}
