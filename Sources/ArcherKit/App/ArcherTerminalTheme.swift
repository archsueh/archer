import AppKit
import Foundation

struct ArcherTerminalTheme: Identifiable, Hashable {
    enum Source: Hashable {
        case bundled
        case ghosttyUser
    }

    let id: String
    let title: String
    let storedValue: String
    let backgroundHex: String
    let foregroundHex: String
    let lines: [String]
    let source: Source

    var isBundled: Bool {
        source == .bundled
    }

    /// Light/dark split for the picker's section grouping. Uses the same
    /// luminance threshold `Theme.Resolved` applies when deciding chrome
    /// appearance, so a theme listed under "Dark" is exactly one that renders
    /// dark chrome.
    var isDark: Bool {
        (NSColor(hex: backgroundHex)?.relativeLuminance ?? 0) <= 0.55
    }

    static let presets: [ArcherTerminalTheme] = [
        .init(
            id: "catppuccin-frappe",
            title: "Catppuccin Frappe",
            background: "#303446",
            foreground: "#C6D0F5",
            cursor: "#F2D5CF",
            selectionBackground: "#626880",
            selectionForeground: "#C6D0F5",
            palette: [
                "#51576D", "#E78284", "#A6D189", "#E5C890",
                "#8CAAEE", "#F4B8E4", "#81C8BE", "#A5ADCE",
                "#626880", "#E67172", "#8EC772", "#D9BA73",
                "#7B9EF0", "#F2A4DB", "#5ABFB5", "#B5BFE2",
            ]
        ),
        .init(
            id: "catppuccin-latte",
            title: "Catppuccin Latte",
            background: "#EFF1F5",
            foreground: "#4C4F69",
            cursor: "#DC8A78",
            selectionBackground: "#CCD0DA",
            selectionForeground: "#4C4F69",
            palette: [
                "#5C5F77", "#D20F39", "#40A02B", "#DF8E1D",
                "#1E66F5", "#EA76CB", "#179299", "#ACB0BE",
                "#6C6F85", "#D20F39", "#40A02B", "#DF8E1D",
                "#1E66F5", "#EA76CB", "#179299", "#BCC0CC",
            ]
        ),
        .init(
            id: "dracula",
            title: "Dracula",
            background: "#282A36",
            foreground: "#F8F8F2",
            cursor: "#F8F8F2",
            selectionBackground: "#44475A",
            selectionForeground: "#F8F8F2",
            palette: [
                "#000000", "#FF5555", "#50FA7B", "#F1FA8C",
                "#BD93F9", "#FF79C6", "#8BE9FD", "#BBBBBB",
                "#555555", "#FF5555", "#50FA7B", "#F1FA8C",
                "#BD93F9", "#FF79C6", "#8BE9FD", "#FFFFFF",
            ]
        ),
        .init(
            id: "rose-pine",
            title: "Rosé Pine",
            background: "#191724",
            foreground: "#E0DEF4",
            cursor: "#E0DEF4",
            selectionBackground: "#403D52",
            selectionForeground: "#E0DEF4",
            palette: [
                "#26233A", "#EB6F92", "#31748F", "#F6C177",
                "#9CCFD8", "#C4A7E7", "#EBBCBA", "#E0DEF4",
                "#6E6A86", "#EB6F92", "#31748F", "#F6C177",
                "#9CCFD8", "#C4A7E7", "#EBBCBA", "#E0DEF4",
            ]
        ),
        .init(
            id: "rose-pine-dawn",
            title: "Rosé Pine Dawn",
            background: "#FAF4ED",
            foreground: "#575279",
            cursor: "#575279",
            selectionBackground: "#DFDAD9",
            selectionForeground: "#575279",
            palette: [
                "#F2E9E1", "#B4637A", "#286983", "#EA9D34",
                "#56949F", "#907AA9", "#D7827E", "#575279",
                "#9893A5", "#B4637A", "#286983", "#EA9D34",
                "#56949F", "#907AA9", "#D7827E", "#575279",
            ]
        ),
        .init(
            id: "solarized-dark",
            title: "Solarized Dark",
            background: "#002B36",
            foreground: "#839496",
            cursor: "#93A1A1",
            selectionBackground: "#073642",
            selectionForeground: "#93A1A1",
            palette: [
                "#073642", "#DC322F", "#859900", "#B58900",
                "#268BD2", "#D33682", "#2AA198", "#EEE8D5",
                "#002B36", "#CB4B16", "#586E75", "#657B83",
                "#839496", "#6C71C4", "#93A1A1", "#FDF6E3",
            ]
        ),
        .init(
            id: "solarized-light",
            title: "Solarized Light",
            background: "#FDF6E3",
            foreground: "#657B83",
            cursor: "#586E75",
            selectionBackground: "#EEE8D5",
            selectionForeground: "#586E75",
            palette: [
                "#073642", "#DC322F", "#859900", "#B58900",
                "#268BD2", "#D33682", "#2AA198", "#EEE8D5",
                "#002B36", "#CB4B16", "#586E75", "#657B83",
                "#839496", "#6C71C4", "#93A1A1", "#FDF6E3",
            ]
        ),
        .init(
            id: "tokyo-night",
            title: "Tokyo Night",
            background: "#1A1B26",
            foreground: "#C0CAF5",
            cursor: "#C0CAF5",
            selectionBackground: "#283457",
            selectionForeground: "#C0CAF5",
            palette: [
                "#15161E", "#F7768E", "#9ECE6A", "#E0AF68",
                "#7AA2F7", "#BB9AF7", "#7DCFFF", "#A9B1D6",
                "#414868", "#F7768E", "#9ECE6A", "#E0AF68",
                "#7AA2F7", "#BB9AF7", "#7DCFFF", "#C0CAF5",
            ]
        ),
        .init(
            id: "tokyo-day",
            title: "Tokyo Day",
            background: "#E1E2E7",
            foreground: "#3760BF",
            cursor: "#3760BF",
            selectionBackground: "#B7C1E3",
            selectionForeground: "#3760BF",
            palette: [
                "#B4B5B9", "#F52A65", "#587539", "#8C6C3E",
                "#2E7DE9", "#9854F1", "#007197", "#6172B0",
                "#A1A6C5", "#F52A65", "#587539", "#8C6C3E",
                "#2E7DE9", "#9854F1", "#007197", "#3760BF",
            ]
        ),
        .init(
            id: "gruvbox-dark",
            title: "Gruvbox Dark",
            background: "#282828",
            foreground: "#EBDBB2",
            cursor: "#EBDBB2",
            selectionBackground: "#665C54",
            selectionForeground: "#EBDBB2",
            palette: [
                "#282828", "#CC241D", "#98971A", "#D79921",
                "#458588", "#B16286", "#689D6A", "#A89984",
                "#928374", "#FB4934", "#B8BB26", "#FABD2F",
                "#83A598", "#D3869B", "#8EC07C", "#EBDBB2",
            ]
        ),
        .init(
            id: "gruvbox-light",
            title: "Gruvbox Light",
            background: "#FBF1C7",
            foreground: "#3C3836",
            cursor: "#3C3836",
            selectionBackground: "#D5C4A1",
            selectionForeground: "#3C3836",
            palette: [
                "#FBF1C7", "#CC241D", "#98971A", "#D79921",
                "#458588", "#B16286", "#689D6A", "#7C6F64",
                "#928374", "#9D0006", "#79740E", "#B57614",
                "#076678", "#8F3F71", "#427B58", "#3C3836",
            ]
        ),
        .init(
            id: "one-dark",
            title: "One Dark",
            background: "#282C34",
            foreground: "#ABB2BF",
            cursor: "#ABB2BF",
            selectionBackground: "#3E4451",
            selectionForeground: "#ABB2BF",
            palette: [
                "#282C34", "#E06C75", "#98C379", "#E5C07B",
                "#61AFEF", "#C678DD", "#56B6C2", "#ABB2BF",
                "#5C6370", "#E06C75", "#98C379", "#E5C07B",
                "#61AFEF", "#C678DD", "#56B6C2", "#FFFFFF",
            ]
        ),
        .init(
            id: "one-light",
            title: "One Light",
            background: "#FAFAFA",
            foreground: "#383A42",
            cursor: "#383A42",
            selectionBackground: "#DBDBDC",
            selectionForeground: "#383A42",
            palette: [
                "#383A42", "#E45649", "#50A14F", "#C18401",
                "#4078F2", "#A626A4", "#0184BC", "#A0A1A7",
                "#696C77", "#E45649", "#50A14F", "#C18401",
                "#4078F2", "#A626A4", "#0184BC", "#FFFFFF",
            ]
        ),
    ]

    static func preset(for storedValue: String) -> ArcherTerminalTheme? {
        let trimmed = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return presets.first { $0.matches(storedValue: trimmed) }
    }

    static func availableThemes(userThemeDirectory: URL = ghosttyUserThemesDirectory()) -> [ArcherTerminalTheme] {
        presets + userThemes(in: userThemeDirectory)
    }

    static func theme(for storedValue: String, in themes: [ArcherTerminalTheme]) -> ArcherTerminalTheme? {
        let trimmed = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return themes.first { $0.matches(storedValue: trimmed) }
    }

    static func ghosttyUserThemesDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let xdg = environment["XDG_CONFIG_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !xdg.isEmpty
        {
            return URL(fileURLWithPath: xdg, isDirectory: true)
                .appendingPathComponent("ghostty/themes", isDirectory: true)
        }
        return homeDirectory
            .appendingPathComponent(".config/ghostty/themes", isDirectory: true)
    }

    static func userThemes(in directory: URL) -> [ArcherTerminalTheme] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.sorted { lhs, rhs in
            lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }.compactMap { url -> ArcherTerminalTheme? in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let values = parseGhosttyConfigLines(text)
            return ArcherTerminalTheme(
                userThemeName: url.lastPathComponent,
                background: values["background"],
                foreground: values["foreground"]
            )
        }
    }

    func matches(storedValue: String) -> Bool {
        id == storedValue || title == storedValue || self.storedValue == storedValue
    }

    private init(
        id: String,
        title: String,
        background: String,
        foreground: String,
        cursor: String,
        selectionBackground: String,
        selectionForeground: String,
        palette: [String]
    ) {
        self.id = id
        self.title = title
        storedValue = id
        backgroundHex = background
        foregroundHex = foreground
        source = .bundled
        lines = [
            "background = \(background)",
            "foreground = \(foreground)",
            "cursor-color = \(cursor)",
            "selection-background = \(selectionBackground)",
            "selection-foreground = \(selectionForeground)",
        ] + palette.enumerated().map { idx, color in
            "palette = \(idx)=\(color)"
        }
    }

    private init(userThemeName: String, background: String?, foreground: String?) {
        id = "ghostty-user:\(userThemeName)"
        title = userThemeName
        storedValue = userThemeName
        backgroundHex = background ?? "#282C34"
        foregroundHex = foreground ?? "#EFEFF1"
        lines = []
        source = .ghosttyUser
    }

    private static func parseGhosttyConfigLines(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: eq)...])
                .trimmingCharacters(in: .whitespaces)
            values[key] = unwrapQuotes(rawValue)
        }
        return values
    }

    private static func unwrapQuotes(_ raw: String) -> String {
        guard raw.count >= 2,
              raw.first == raw.last,
              raw.first == "\"" || raw.first == "'" else { return raw }
        return String(raw.dropFirst().dropLast())
    }
}
