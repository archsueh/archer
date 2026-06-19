# Task: Agent-completion notification sound option (verify + wire up)

**Repo:** `~/Developer/archer` (branch `main`)
**Status when handed off:** feature is ~90% already in the code — do NOT rebuild from scratch. The job is to (a) figure out why the user can't see / use the sound option, and (b) close the real wiring gaps below.

## Background / user report
User asked for: "每次 agent run 完确认时的通知应该有个可设置提示音的选项",
but reports they don't see it in Settings.

## What ALREADY exists (verified 2026-06-19)
- Settings model: `Sources/ArcherKit/App/ArcherSettingsUI.swift`
  - `:111` `notifyOnCompleted: Bool = true`
  - `:112` `notificationSound: String = "Submarine"`
  - persisted under `notifications.completed` / `notifications.sound` (`:190-191`, `:363-364`)
- Settings UI: `ArcherSettingsUI.swift` `notificationsDetail` view
  - `:838-843` "completed" toggle
  - `:844-856` "alert sound" `Picker` (14 macOS sounds: Basso…Tink), previews on change via `NSSound(named:).play()`
- Playback on completion: `Sources/ArcherKit/App/AppDelegate.swift:347-349`
  - guarded by `notificationsEnabled && notifyOnCompleted`, then `NSSound(named: settings.notificationSound)?.play()`

## The real gaps to fix
1. **Visibility — primary user complaint.** Confirm the "alert sound" row actually renders in the running app's Settings → Notifications pane. Check:
   - Is `notificationsDetail` reachable from the settings nav (is there a "Notifications" section entry that routes to it)? Search the settings nav/section list in `ArcherSettingsUI.swift`.
   - Was the user running an older build? Current `main` has it; the shipped `dist/Archer-v1.0.0.dmg` was rebuilt from current code. If a nav entry is missing, add it.
2. **Notification banner ignores the chosen sound.** `Sources/ArcherKit/App/NotificationManager.swift:53` hardcodes `content.sound = .default`. It does not read `notificationSound`. Decide and implement ONE coherent model:
   - Option A: banner stays silent (`content.sound = nil`) and the AppDelegate `NSSound` is the single completion sound (matches the picker, which only knows `NSSound` names). Simplest, removes double-sound.
   - Option B: map the picker value to a `UNNotificationSound`/bundled sound and set it on the banner; drop the AppDelegate `NSSound`. More work (UNNotificationSound needs sound files in the app bundle, not `NSSound` system-name semantics).
   - **Recommend Option A** unless product wants the OS banner itself to carry the sound.
3. **Double-sound risk.** On completion both can fire: banner `.default` (NotificationManager) + `NSSound` (AppDelegate). Resolving #2 via Option A eliminates this.

## Acceptance criteria
- In a running build, Settings → Notifications shows: completed toggle + "alert sound" picker, both gated by master `notificationsEnabled`.
- Changing the picker previews the sound immediately (already wired at `:853-855`).
- When an agent run completes and the tab is not focused, exactly ONE sound plays, and it is the picked sound (not the OS default), only when `notificationsEnabled && notifyOnCompleted`.
- Persists to `~/.archer/settings.json` under `notifications.sound` and survives restart.

## Notes
- Project is SwiftPM, build: `swift build`; test: `swift test`; app bundle: `bash scripts/build-app.sh`.
- CI on `main` is green; keep the `AgentTemplateTests` shell-detection style if you add tests.
- Follow `CLAUDE.md`: keep `// [archer]` annotations, 4-space indent, surgical changes.
