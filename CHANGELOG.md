# Changelog

Notable changes per release. Tagged commits use `vX.Y.Z` shortform.

## Unreleased

- **Grok full integration** — Renamed **Grok Build** → **Grok** across the agent menu and docs. Detects `~/.grok/bin/grok`, installs Claude-compatible lifecycle + tool-call hooks into `~/.grok/hooks/archer.json`, captures `sessionId` for `--resume` on relaunch, wires `-p` for Ask Grok, and feeds the activity strip from PreToolUse/PostToolUse events.

## v1.0.3 — 2026-06-22

- **Screen-Edge Activity Glow** — Added an off-by-default screen-edge glow that mirrors the activity chime: a thin monochrome hairline on a click-through overlay window per screen, driven by the same hook signal as the notification sound. Color comes only from the activity tokens (running/attention/failure), with enable, screen-scope, brightness, and width controls in Settings → Notifications.
- **Per-Agent Usage View** — The Usage dashboard now has an agent picker and sources available agents from sessions plus the on-disk usage databases (`~/.claude/usage.db`, `~/.hermes/state.db`), so it reflects agents that actually have records and renders real Hermes/Claude metrics instead of placeholders.
- **Unified Terminal Input** — Removed the ⌘L prompt composer so input lives only in the terminal, unifying each pane to a single input surface.
- **Persistent Skill Repairs** — Skill repairs and deletions made in the Skills Dashboard now persist to disk across launches.
- **Sidebar & Panel Transitions** — Added slide/fade transitions for sidebars, panels, and cockpit views.

## v1.0.2 — 2026-06-21

- **Skills Dashboard** — Added a dedicated full-screen agent skills view, which dynamically scans local/project skills metadata, parses frontmatter config files, flags duplicates/issues, and provides an interactive one-click repair tool.
- **Agent Usage Dashboard** — Integrated a detailed token quota and rate limit tracker, pulling direct stats from `~/.claude/usage.db` SQLite logs to render live input/output metrics and a custom 7-day stacked bar chart.
- **Improved Shell Input** — Refined Prompt Composer focus border transitions inside terminal split panes.

## v1.0.1 — 2026-06-20

- **Chinese Localization (zh-Hans)** — Localized the Settings window (General, Notifications, SSH) and the system menu bar/context menus.
- **Activity Chimes** — Restored startup ritual ping sound, and play chime alerts on turn completion.
- **Design System Alignment** — Mapped all color tokens to components in `DESIGN.md` to resolve `@google/design.md` lint warnings.
- **UI & Bug Fixes** — Prevented launch hanging, aligned topbar/sidebar layouts, and updated entitlements for macOS 26+ hardened runtime compliance.

## v0.26.8 — 2026-06-15

- Fixed: switching workspaces now keeps keyboard focus on the pane you left it on, instead of jumping to the last split pane (#24).

## v0.26.7 — 2026-06-15

- Fixed: the elapsed time on the Claude Code / Pi tool-call pill (and its popover) now shows hours and days for long spans — e.g. `2d 2:00:00` instead of a giant raw minute count like `3000:00`.

## v0.26.6 — 2026-06-15

- Fixed: an agent another tool launches in the background — e.g. `codex:review` running inside Claude Code in a archer tab — no longer hangs. archer's agent wrapper now steps aside for background, tool-driven calls instead of trying to report their status.

## v0.26.5 — 2026-06-09

- New: a "Remote Login" status-bar slot shows the `user@host` you're SSHed into. Toggle it in Settings → Status Bar (needs "remote agent detection" on under Settings → SSH).

## v0.26.4 — 2026-06-09

- New: hide the top-bar search box if you don't want it — Settings → General → "top bar search". ⌘P still opens search either way.

## v0.26.3 — 2026-06-09

- Polish: selected and hover states read more clearly now — stronger contrast on the active tab, workspace, buttons, and Settings rows, in both light and dark themes.

## v0.26.2 — 2026-06-09

- Polish: tidied up a handful of mismatched button-icon and input-field sizes across the sidebar, tab bar, and Settings so same-kind controls line up.

## v0.26.1 — 2026-06-09

- Pasting a file or image into the prompt composer now inserts its full path (same as ⌘V in the terminal), not just the filename.

## v0.26.0 — 2026-06-08

- **Prompt composer (⌘L)** — a chat-style box that rises from the bottom of the pane for writing long, multi-line prompts without a stray Return firing them off mid-thought. Return sends to the current agent (or shell), Shift+Return adds a newline, Esc cancels and keeps your draft. Open it with ⌘L or the compose button in the pane status bar.

## v0.25.0 — 2026-06-04

- **Agent panel** — a right-side sidebar (top-bar toggle, three collapse states like the left one) listing every agent across all your windows, sorted by who needs you first: waiting on you, then failed, running, idle. Click a row to jump straight to that tab; compact mode shrinks it to a rail of status-tinted icons.

## v0.24.1 — 2026-06-03

- **Notification center** — a bell in the top bar (⇧⌘I) collects agent alerts from every window: who's waiting on you, what failed, what finished. A red dot marks unread; click any entry to jump straight to that tab.
- Looking at a tab clears its alerts — whether you open it, jump in from the inbox, or just switch back to archer — so a notification you've already seen doesn't keep the bell lit.

## v0.24.0 — 2026-06-03

- **Notifications** — get a macOS notification when an agent in a hidden tab starts waiting on you, or a command there fails. Turn each kind on or off in Settings → Notifications.
- Fixed: the red "command failed" dot now clears the moment you start your next command (type, paste, or recall from history), instead of lingering until that command finishes — which never happened for a long-running one like an agent.

## v0.23.0 — 2026-06-02

- **Kiro CLI** — AWS's `kiro-cli` agent joins the launcher. Pick it from the `+` menu or set it as your default agent; the sidebar activity dot tracks when it's running.

## v0.22.6 — 2026-06-02

- Right-click the Dock icon to open a new window, or jump straight to any workspace or tab across all your open windows.
- Quick Open (⌘P) now pops a minimized window back open when you jump to a tab inside it, instead of leaving it tucked in the Dock.

## v0.22.5 — 2026-06-02

- Rename a tab with ⌘R and a workspace with ⌘⇧R — the rename field opens right where you're working, instead of only through the right-click menu (which now shows the shortcuts too).

## v0.22.4 — 2026-06-02

- Fixed terminal text overflowing the pane after switching workspaces and back, when archer is on a non-Retina external monitor — a follow-up to the display-scale fix in v0.19.2. (Relates to #8.)

## v0.22.3 — 2026-06-01

- Fixed agent activity not updating when you launch an agent by typing its command (`claude` / `codex` / …) directly in the terminal — macOS had been silently killing the small helper archer uses to detect it. Claude's hooks and the tool-call pill are restored too.

## v0.22.2 — 2026-06-01

- Split a pane straight from its tab bar — two buttons on the right (split right / split down) do the same thing as ⌘D / ⌘⇧D, so splitting is right there instead of behind a shortcut.

## v0.22.1 — 2026-06-01

- Pi sessions now show the tool Pi is running right now in the pane status bar (`bash` / `read` / `edit` / etc.) with elapsed time — click the pill for the full session history, the same readout Claude Code already had.
- Settings → Status Bar lets you show or hide the tool-call pill per agent, so Claude Code and Pi toggle independently.

## v0.22.0 — 2026-06-01

- **Pi** — Earendil's `pi` coding agent ([pi.dev](https://pi.dev)) joins the launcher. Pick it from the `+` menu or set it as your default agent; the sidebar dot tracks when it's working and when it's waiting on you, and pi conversations resume across archer restarts.

## v0.21.0 — 2026-06-01

- Remote agent detection over SSH (opt-in) — `ssh` into a machine from archer and run an agent there (Claude, Codex, …), and the sidebar now shows that agent's icon and activity instead of treating the tab as a plain terminal. Turn it on in Settings → SSH. (Resolves #19.)

## v0.20.1 — 2026-05-30

- Agent icons now show on light themes — the monochrome marks (OpenCode, Cursor, Copilot, Grok, Kimi) were invisible on light color schemes and now adapt to the theme so they're visible everywhere.

## v0.20.0 — 2026-05-30

- **Kimi Code** — Moonshot AI's `kimi` CLI joins the agent launcher. Pick it from the `+` menu or set it as your default agent; the sidebar activity dot tracks when it's running.

## v0.19.3 — 2026-05-30

- **Custom Ghostty themes** — themes in your Ghostty themes folder now appear in Settings and recolor the terminal and whole window when selected. (Resolves #17.)

## v0.19.2 — 2026-05-29

- Fixed the layout breaking when you drag the window between displays with different scale factors (e.g. a Retina laptop screen and a 1x external monitor) — the terminal now re-flows to the new display's resolution instead of leaving a blank gutter on the right or letting input overflow the viewport. (Resolves #8.)

## v0.19.1 — 2026-05-29

- Fixed the terminal getting stuck mid-screen after a resize, fullscreen toggle, or the status bar appearing — when an agent like Claude Code is streaming output, the view now stays pinned to the latest output and the input box instead of stranding them below the fold. Scroll up to read history and it stays where you left it. (Resolves #7.)

## v0.19.0 — 2026-05-28

- Watch Claude Code work in real time — archer now shows a pill in the bottom status bar with the tool Claude is running (Bash / Edit / Read / etc.), how long it's been running, and whether it succeeded or failed. Click the pill to see the full session history.
- Failed tool calls turn red immediately, not after a 60-second wait.
- Settings → Status Bar gets a Claude Code section with a toggle for the activity pill.

## v0.18.3 — 2026-05-28

- Worktree close is safe by default — closing a worktree now only removes it from the sidebar; the directory and branch stay on disk. Tick "also delete worktree directory and branch" in the confirm sheet for the v0.18.x destructive behaviour.
- Adopt existing worktrees — Create Worktree → "adopt" mode lists every `git worktree list` entry not already in the sidebar. Pick the ones you want archer to manage.
- Archer no longer auto-imports CLI-created worktrees at launch. Only worktrees you explicitly created or adopted show up in the sidebar.

## v0.18.2 — 2026-05-27

- Paste a file or image — copy a file in Finder (Cmd+C) and Cmd+V into archer now pastes the full file path instead of just the filename, so Claude / Codex / Cursor can read it as an argument.
- Paste a screenshot — take a screenshot to the clipboard (Cmd+Ctrl+Shift+4), Cmd+V into archer, and the image gets saved to `~/Library/Caches/archer/pastes/` with its path pasted into the terminal. Drop a screenshot straight into a Claude prompt with no save-to-disk detour. (Resolves #15.)

## v0.18.1 — 2026-05-27

- Worktree sidebar polish — worktree rows now show a branch badge in their subtitle, source rows reveal a hover-only chevron for collapsing the worktree group, and the disclosure no longer steals a leading column from the (already narrow) sidebar.
- Right-click a worktree → "Go to Source Workspace" jumps back to the source repo. Right-click a source → "Refresh Worktrees" picks up worktrees you created in another terminal without restarting archer.
- Closing a worktree now also cleans up its branch — `git branch -d` runs after `git worktree remove`. Merged branches go away (next worktree of the same name builds cleanly); unmerged branches stay (git itself refuses, no data loss). Reads the worktree's real current branch from git at delete time, so `git switch`ing inside the worktree no longer leaves the wrong branch behind.
- "Create Worktree…" sheet opens noticeably faster (git enumeration runs in parallel), and the existing-branch picker hides itself when every local branch is already checked out somewhere.
- Worktrees you created from the command line now spawn with your default agent (the one you picked in Settings → Agents) instead of a plain Terminal.

## v0.18.0 — 2026-05-26

- **Git worktrees** — right-click a git workspace → "Create Worktree…" to spin one up on a new branch (or check out an existing one). Each worktree gets its own sidebar entry nested under its source repo, its own tabs, and its own agent — work on a feature branch with Claude without touching what's running on main. Closing a worktree deletes the directory; closing a source repo removes its whole worktree group in one confirm. Worktrees you create from the command line show up automatically next launch.

## v0.17.0 — 2026-05-26

- **Theme picker** — choose a theme in Settings. Theme changes apply immediately across the terminal and the whole window.

## v0.16.3 — 2026-05-25

- **Pane zoom (⌘⇧E)** — expand the active pane to fill the workspace; the other panes slide off-screen but their processes keep running. Toggle from ⌘⇧E, the zoom button in each pane's bottom status bar, the View menu, or right-click → "Zoom Pane".

## v0.16.2 — 2026-05-25

- **Settings → Status Bar** — drag to reorder the pane bottom status bar's slots (Python venv / Node version / Proxy / Git branch / Git diff), toggle individual ones off, or hide the whole row. Reset to defaults if you change your mind.

## v0.16.1 — 2026-05-25

- Fixed the Quick Open search pill overlapping the sidebar toggle when the window was dragged narrow. The pill now stays in the drag-handle area and hides automatically when there isn't room for it — ⌘P and the File menu still open the palette.

## v0.16.0 — 2026-05-25

- **Quick Open (⌘P)** — fuzzy-search across every window's workspaces and tabs, plus every visible agent and Terminal preset. Type to filter, ↑↓ to navigate, Enter to jump; clicking a workspace or tab focuses its owning window, picking an agent or preset spawns a new tab with it. Triggers from ⌘P or the search pill in the top chrome.

## v0.15.0 — 2026-05-25

- **Terminal presets** — define "Terminal at <path>" entries that show up in the `+` menu, each opening a new tab at a fixed folder regardless of the active workspace. Configure under Settings → Terminals: name + path (with `~/foo` shorthand or a folder picker), drag to reorder, toggle visibility, delete. Handy when you keep jumping to the same project folders.
- Settings sidebar reorganized — first category renamed `General` (was `Terminal`) to make room for the new `Terminals` category in between. The `default-new-tab` picker moved to `General` since it now controls both presets and agents.

## v0.14.4 — 2026-05-24

- File → Open Folder… (⌘O) opens any folder as a new workspace.

## v0.14.3 — 2026-05-23

- Drag a folder from Finder onto the sidebar to open it as a new workspace.

## v0.14.2 — 2026-05-23

- Right-click any tab → "Move to New Window" sends it to its own new window — the terminal, scrollback, and any running process all come along.

## v0.14.1 — 2026-05-22

- Drag a tab from one window's tab bar onto another window's to move it across — the terminal, its scrollback, and any running process all come with it.

## v0.14.0 — 2026-05-22

- Multiple windows — press ⌘⇧N to open a new window. Each window keeps its own workspaces, tabs, and sidebar, and every open window is restored when you relaunch archer.

## v0.13.0 — 2026-05-22

- Custom agents based on Claude Code can now carry their own environment variables — set `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` in a custom agent's new `env` field (Settings → Agents) to point it at a Claude-compatible mirror or proxy.

## v0.12.4 — 2026-05-21

- Fixed: arrow keys in `vim` (and other full-screen programs) now work over SSH to older remote machines.

## v0.12.3 — 2026-05-21

- The tab and sidebar name now follow the terminal title — `ssh` into a remote host and the tab shows its `user@host` instead of the local folder, then reverts when you exit.

## v0.12.2 — 2026-05-20

- Antigravity CLI joins the agent menu — Google's Go-based successor to Gemini CLI.
- Fixed: picking Antigravity from the `+` menu when only the IDE is installed now surfaces a clear CLI install hint instead of accidentally opening the IDE app.

## v0.12.1 — 2026-05-19

- Check for Updates in the Archer menu — see what's new and download the latest DMG in one click.

## v0.12.0 — 2026-05-19

- Grok (xAI) joins the agent menu.

## v0.11.6 — 2026-05-18

- Fixed: shell history and Tab completion now survive archer restarts.
- Fixed: environment variables in `~/.zshenv`, `~/.zprofile`, and `~/.bash_profile` now load in archer terminals.

## v0.11.5 — 2026-05-18

- Fixed: long Chinese / Japanese / Korean inputs no longer leave a phantom space mid-line.
- Fixed: when a long input wraps to a second line, the first line no longer disappears.

## v0.11.4 — 2026-05-18

- Fixed: Chinese / Japanese / Korean IME candidate window now shows right under the cursor instead of flying off-screen.

## v0.11.3 — 2026-05-16

- Drag a file or folder from Finder onto any archer terminal pane → its path drops in at the cursor. Multi-file drag = space-separated paths.

## v0.11.2 — 2026-05-16

- Click anywhere on your zsh prompt to jump the cursor there.

## v0.11.1 — 2026-05-15

- Right-click menu redesigned to match archer's brutalist style.
- Fixed: right-clicking selections that start with `-` no longer crashes the agent.
- Fixed: paste in the right-click menu now matches ⌘V behavior in zsh / vim.
- Fixed: right-clicking inside an inactive split now activates that pane first.

## v0.11.0 — 2026-05-15

- Right-click selection → "Ask <agent>". Select any text in a terminal, right-click, pick an agent → a new tab spawns with the selection as the first prompt.

## v0.10.8 — 2026-05-15

- Claude conversations resume across archer restarts. Quit mid-conversation → next launch picks up where you left off.
- Settings → Agents → `resume-conversation-when-reopen` toggle.

## v0.10.7 — 2026-05-15

- GitHub Copilot tabs now show the mid-run "attention" dot.

## v0.10.6 — 2026-05-15

- Custom agents can inherit from a builtin — pick **Claude Code** as the base and your custom (e.g. "Claude Opus") inherits the icon, brand tint, and lifecycle tracking.
- Fixed: custom-based-on-Claude tabs now revert to Terminal when the agent exits.

## v0.10.5 — 2026-05-15

- Define your own agent. Settings → Agents → `+ add custom agent` wires any CLI as a first-class archer agent.

## v0.10.4 — 2026-05-15

- GitHub Copilot CLI joins the agent menu.

## v0.10.3 — 2026-05-15

- Default agent for `+` and `⌘T`. Pick any agent in Settings → Agents → default to skip the popover.

## v0.10.2 — 2026-05-14

- Per-agent launch options. Each agent row in Settings has a chevron to add options like `--model opus`.

## v0.10.1 — 2026-05-14

- Customise the `+` menu — hide agents you don't use, reorder the rest.
- Settings UI redesigned with a brutalist-minimal aesthetic.

## v0.10.0 — 2026-05-14

- Cursor CLI joins the agent menu.

## v0.9.12 — 2026-05-14

- Cleaner "agent not installed" message.
- Fixed: tab icon reverts to Terminal when the agent's CLI is missing.

## v0.9.11 — 2026-05-14

- Mac-style text editing shortcuts in the shell:
  - `Cmd+←` / `Cmd+→` — beginning / end of line
  - `Option+←` / `Option+→` (or `Ctrl+←` / `Ctrl+→`) — jump by word
  - `Cmd+Backspace` — delete to start of line
  - `Option+Backspace` — delete previous word

## v0.9.10 — 2026-05-14

- Friendlier "agent not installed" message.
- Fixed: `curl | bash` installers now write to your real `~/.zshrc`.

## v0.9.9 — 2026-05-13

- Non-focused panes fully dim, including terminal content.

## v0.9.8 — 2026-05-13

- Spot the focused pane at a glance — non-focused panes dim their chrome.

## v0.9.7 — 2026-05-12

- New Settings window (`⌘,`) backed by `~/.archer/settings.json`. v1 surfaces Font Family / Font Size / Cursor Style.
- First-launch onboarding offers to import `~/.config/ghostty/config`.

## v0.9.6 — 2026-05-12

- Smoother sidebar-collapse animation.
- Per-row Unset button in the proxy popover.
- New app icon.

## v0.9.5 — 2026-05-11

- `Shift+Enter` inserts a newline. Plain Enter still submits.
- About panel polish.

## v0.9.4 — 2026-05-11

- Status bar git state auto-refreshes during agent sessions.
- Network proxy slot in the status bar.
- Tab icon promotes when you manually launch an agent.

## v0.9.3 — 2026-05-11

- Tab icon promotes when you manually launch an agent inside a Terminal tab.

## v0.9.2 — 2026-05-11

- `exit` / `logout` closes the tab automatically.
- Reveal in Finder — right-click any tab pill or workspace row.
- Reopen Closed Tab (`⌘⇧T`).
- `⌃⇥` / `⌃⇧⇥` for per-pane tab cycling.

## v0.9.1 — 2026-05-11

- Reveal in Finder for tabs and workspaces.
- Reopen Closed Tab (`⌘⇧T`) restores agent + cwd + custom title.
- `⌃⇥` / `⌃⇧⇥` per-pane tab cycling.

## v0.9.0 — 2026-05-10

- Pane status bar showing live working-tree state — Python venv, Node version, git branch, git diff.
- Click the Node version pill → switch between installed nvm versions. Click the git branch pill → switch branches.

## v0.8.0 — 2026-05-10

- Find in scrollback (`⌘F`) per-pane. `⌘G` / `⌘⇧G` for next / previous match.
- Gemini CLI activity dot.
- OpenCode activity dot.
- Amp activity dot.

## v0.7.6 — 2026-05-09

- App icon.
- macOS 14 minimum (was 15).

## v0.7.5 — 2026-05-09

- `.app` bundle. Drag `dist/Archer.app` into `/Applications` and launch from Spotlight.

## v0.7.4 — 2026-05-09

- Workspace-level command-failure dot — red dot on the sidebar row when any tab has a non-zero last exit.

## v0.7.3 — 2026-05-09

- Per-tab last-command status — small red dot when the most recent command exited non-zero. Hover for `exit N · 12.4s`.
- `⌘↑` / `⌘↓` to jump between prompts.

## v0.7.2 — 2026-05-09

- Manual rename for tabs and workspaces. Right-click → *Rename…*. Persists.

## v0.7.1 — 2026-05-09

- URL `⌘+click` opens in your default browser.
- Mouse shape follows libghostty (pointing-hand on URLs, resize on TUI splits).
- Font size shortcuts: `⌘=` increase, `⌘-` decrease, `⌘0` reset.
- Clear Pane (`⌘K`).
- Sidebar mode persists across launches.

## v0.7.0 — 2026-05-09

- Three-state sidebar (`full` / `compact` / `hidden`), `⌘⌃S` cycles.
- Top chrome strip with dedicated drag handle, sidebar toggle, traffic-light clearance.
- View menu becomes the navigation hub — Tab `⌘1`-`⌘9`, Workspace `⌥⌘1`-`⌥⌘9`, splits, sidebar toggle. New Help menu.
- Custom About panel.

## v0.6.0 — 2026-05-09

- Drag-reorder workspaces and tabs with animated drop indicators.
- Cross-pane tab move via drag.
- View menu with `Tab 1`-`9` and `Workspace 1`-`9` switches.
- Double-click tab bar zooms the window.
- Right-click menus show keyboard shortcut hints.

## v0.5.0 — 2026-05-08

- Recursive splits — `⌘D` splits right, `⌘⇧D` splits down, `⌘[` / `⌘]` cycles focus, `⌘W` closes a tab and collapses an empty pane.
- Right-click context menus on tabs and sidebar rows.
- Click-to-focus across panes.

## v0.4.0 — 2026-05-08

- Codex integration — sidebar shows the Codex icon while it's running.
- Auto-promote agent on hook — plain Terminal tabs that report a Claude / Codex hook upgrade to the matching template.
- IME — Chinese / Japanese / Korean / Vietnamese compose properly.

## v0.3.0 — 2026-05-08

- Agent activity dot in the sidebar — blue when processing, amber when waiting on input, hidden when idle.
- Real Claude Code integration.

## v0.2.0 — 2026-05-08

- Keyboard shortcuts: `⌘T` new tab, `⌘N` new workspace, `⌘W` close tab, `⌘⇧W` close workspace, `⌘1`-`⌘9` switch tab.
- Persistence — workspaces, tabs, agent type, and cwd survive relaunch.
- Hidden title bar; tab bar sits at the window top edge.

## v0.1.0 — 2026-05-08

First public release. Native macOS terminal with vertical-tab workspaces and one-click AI agent sessions (Claude Code / Codex / Gemini CLI / OpenCode / Amp).
