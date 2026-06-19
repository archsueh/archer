import Foundation

enum L10n {
    static func string(_ key: String) -> String {
        let value = NSLocalizedString(key, bundle: Bundle.module, value: "", comment: "")
        return value.isEmpty || value == key ? key : value
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), arguments: arguments)
    }
}
