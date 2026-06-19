import XCTest
@testable import ArcherKit

@MainActor
final class ArcherTerminalThemeTests: XCTestCase {
    func testPresetLookupAcceptsStableId() {
        let theme = ArcherTerminalTheme.preset(for: "solarized-light")
        XCTAssertEqual(theme?.title, "Solarized Light")
    }

    func testPresetLookupAcceptsLegacyDisplayName() {
        let theme = ArcherTerminalTheme.preset(for: "Solarized Light")
        XCTAssertEqual(theme?.id, "solarized-light")
    }

    func testPresetExpandsToConcreteGhosttyColors() {
        let theme = ArcherTerminalTheme.preset(for: "dracula")
        XCTAssertEqual(theme?.lines.first, "background = #282A36")
        XCTAssertEqual(theme?.lines.filter { $0.hasPrefix("palette = ") }.count, 16)
    }

    func testSettingsThemeSelectionPreservesUnknownRawTheme() {
        let state = ArcherSettingsModel.themeSelection(for: "/Users/me/.config/ghostty/themes/custom")
        XCTAssertEqual(state.selection, ArcherSettingsModel.customThemeSelection)
        XCTAssertEqual(
            ArcherSettingsModel.persistedThemeValue(
                selection: state.selection,
                customRawValue: state.customRawValue
            ),
            "/Users/me/.config/ghostty/themes/custom"
        )
    }

    func testSettingsDefaultThemeSelectionClearsRawThemeWhenChosen() {
        let defaultSelection = ArcherSettingsModel.themeSelection(for: nil).selection
        XCTAssertNil(
            ArcherSettingsModel.persistedThemeValue(
                selection: defaultSelection,
                customRawValue: "/Users/me/.config/ghostty/themes/custom"
            )
        )
    }

    func testSettingsPresetThemeSelectionPersistsStableId() {
        let state = ArcherSettingsModel.themeSelection(for: "Solarized Light")
        XCTAssertEqual(state.selection, "solarized-light")
        XCTAssertEqual(
            ArcherSettingsModel.persistedThemeValue(
                selection: state.selection,
                customRawValue: nil
            ),
            "solarized-light"
        )
    }

    func testUserThemesLoadsGhosttyThemeDirectoryFiles() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let themeURL = dir.appendingPathComponent("My Custom Theme")
        try """
        # comments are ignored
        background = #101820
        foreground = "F2AA4C"
        palette = 0=#101820
        """.write(to: themeURL, atomically: true, encoding: .utf8)

        let themes = ArcherTerminalTheme.userThemes(in: dir)
        XCTAssertEqual(themes.map(\.title), ["My Custom Theme"])
        XCTAssertEqual(themes.first?.storedValue, "My Custom Theme")
        XCTAssertEqual(themes.first?.backgroundHex, "#101820")
        XCTAssertEqual(themes.first?.foregroundHex, "F2AA4C")
    }

    func testSettingsThemeSelectionAcceptsUserThemeByFileName() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Issue 17")
        try "background = #000000\nforeground = #ffffff\n"
            .write(to: url, atomically: true, encoding: .utf8)

        let custom = ArcherTerminalTheme.userThemes(in: dir)
        let state = ArcherSettingsModel.themeSelection(for: "Issue 17", in: ArcherTerminalTheme.presets + custom)
        XCTAssertEqual(state.selection, "ghostty-user:Issue 17")
        XCTAssertEqual(
            ArcherSettingsModel.persistedThemeValue(
                selection: state.selection,
                customRawValue: nil,
                in: ArcherTerminalTheme.presets + custom
            ),
            "Issue 17"
        )
    }

    func testGhosttyUserThemesDirectoryHonorsXDGConfigHome() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let xdg = ArcherTerminalTheme.ghosttyUserThemesDirectory(
            environment: ["XDG_CONFIG_HOME": "/tmp/xdg"],
            homeDirectory: home
        )
        XCTAssertEqual(xdg.path, "/tmp/xdg/ghostty/themes")

        let fallback = ArcherTerminalTheme.ghosttyUserThemesDirectory(
            environment: [:],
            homeDirectory: home
        )
        XCTAssertEqual(fallback.path, "/Users/example/.config/ghostty/themes")
    }

    func testSettingsThemeSelectionAutoTheme() {
        let state = ArcherSettingsModel.themeSelection(for: "__archer-auto-theme")
        XCTAssertEqual(state.selection, ArcherSettingsModel.autoThemeSelection)
        XCTAssertNil(state.customRawValue)
        XCTAssertEqual(
            ArcherSettingsModel.persistedThemeValue(
                selection: state.selection,
                customRawValue: nil
            ),
            "__archer-auto-theme"
        )
    }

    func testSelectedTerminalThemeUnderAutoTheme() {
        let model = ArcherSettingsModel.shared
        let originalSelection = model.terminalThemeSelection
        let originalLight = model.autoLightTheme
        let originalDark = model.autoDarkTheme
        defer {
            model.terminalThemeSelection = originalSelection
            model.autoLightTheme = originalLight
            model.autoDarkTheme = originalDark
        }

        model.terminalThemeSelection = ArcherSettingsModel.autoThemeSelection
        model.autoLightTheme = "catppuccin-latte"
        model.autoDarkTheme = "catppuccin-frappe"

        // Simulate daytime
        model.currentHour = 10
        XCTAssertEqual(model.selectedTerminalTheme?.id, "catppuccin-latte")

        // Simulate nighttime
        model.currentHour = 22
        XCTAssertEqual(model.selectedTerminalTheme?.id, "catppuccin-frappe")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("archer-theme-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
