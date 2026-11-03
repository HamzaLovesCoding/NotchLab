<p align="center"><img src="assets/branding/notchlab-logo.png" width="128" alt="NotchLab logo"></p>

# NotchLab

A native macOS app that turns your notch into a small workspace. Hover over it to open your tools, then move away to close it. Works on displays without a notch, too.

## Features

- Claude and Codex usage tracking, agent status, questions, and approval requests.
- CPU, memory, and GPU monitoring.
- Music controls, audio output switching, and focus timers.
- Quick notes, clipboard history, and Apple Reminders.
- A file shelf with AirDrop, VPN controls, and an optional camera mirror.

## Screenshots

![Home: music controls, focus timer, VPN, and quick notes](docs/screenshots/home.png)

![Developer tools: Claude and Codex usage, system stats, and agent sessions](docs/screenshots/developer.png)

![Reminders: connect Apple Reminders to view and complete tasks](docs/screenshots/reminders.png)

![Files: drop files onto the shelf or share them with AirDrop](docs/screenshots/files.png)

## Download

Requires an **Apple silicon Mac** and **macOS 14 or later**.

1. Download `NotchLab.dmg` from the [latest release](https://github.com/HamzaLovesCoding/NotchLab/releases/latest).
2. Open it and drag **NotchApp** into **Applications**.
3. Open NotchApp from Applications. NotchLab isn't notarized by Apple yet, so the first time macOS says it can't verify the app. Click **Done**, open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to NotchApp. You only have to do this once.

   Or skip the prompt from Terminal: `xattr -dr com.apple.quarantine /Applications/NotchApp.app`

Hover over the notch to get started. The first time it opens, you'll see **Connections**: Claude Code, Codex, Claude usage, Camera, Reminders, VPN control (Accessibility), and Launch at Login, each with its own button, plus **Connect all** to set everything up at once. It's always under the gear in **Settings**, along with:

- **General:** open on hover or on click, and how fast it opens and closes.
- **Appearance:** accent color and panel width.
- **Home:** which cards show and their order.
- **Pages:** which pages and Dev cards show.
- **Agents:** where questions and approvals go.
- Focus timer lengths and clipboard history.

The camera turns off when the notch closes or when you click the mirror.

## Build from source

Requires **Xcode Command Line Tools with Swift 6 or later** (`xcode-select --install`).

```sh
git clone https://github.com/HamzaLovesCoding/NotchLab.git
cd NotchLab
./build.sh --install
```

This builds, installs, and opens `/Applications/NotchApp.app`. Use `./build.sh --dmg` to make `build/NotchLab.dmg` for sharing.

## Agent questions and approvals

NotchLab shows Claude Code and Codex permission requests in the notch with **Allow** and **Deny**, lets you answer Claude's multiple-choice questions there, and flashes a side alert when an agent finishes.

**To connect:** click **Connect Claude** and **Connect Codex** on the **Dev** page, or switch them on in **Settings → Connections**. NotchLab adds its bundled `notch-hook` helper to `~/.claude/settings.json` and `~/.codex/hooks.json`, keeps everything else in those files, and saves a one-time backup next to each as `*.before-notchapp`. Then:

- **Codex:** run `/hooks` in Codex once and trust NotchLab's hooks. Codex won't run new hooks until you do.
- Restart any Claude Code or Codex sessions that were already open.

Run NotchApp from your Applications folder before connecting, since the hooks point at the app's location. To undo, switch the agent off in Settings before you delete the app.

**Manual setup:** if you'd rather edit the files yourself, add these entries. If your config already has a `hooks` section, merge them into it.

**Claude Code:** `~/.claude/settings.json`

```json
{
  "hooks": {
    "PermissionRequest": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "/Applications/NotchApp.app/Contents/MacOS/notch-hook claude", "timeout": 300 }] }],
    "PreToolUse": [{ "matcher": "AskUserQuestion", "hooks": [{ "type": "command", "command": "/Applications/NotchApp.app/Contents/MacOS/notch-hook claude", "timeout": 300 }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "/Applications/NotchApp.app/Contents/MacOS/notch-hook claude" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "/Applications/NotchApp.app/Contents/MacOS/notch-hook claude" }] }],
    "SessionEnd": [{ "hooks": [{ "type": "command", "command": "/Applications/NotchApp.app/Contents/MacOS/notch-hook claude" }] }]
  }
}
```

**Codex:** `~/.codex/hooks.json`, then run `/hooks` in Codex once to trust it.

```json
{
  "hooks": {
    "PermissionRequest": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "/Applications/NotchApp.app/Contents/MacOS/notch-hook codex", "timeout": 300 }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "/Applications/NotchApp.app/Contents/MacOS/notch-hook codex" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "/Applications/NotchApp.app/Contents/MacOS/notch-hook codex" }] }],
    "SessionEnd": [{ "hooks": [{ "type": "command", "command": "/Applications/NotchApp.app/Contents/MacOS/notch-hook codex" }] }]
  }
}
```

While a request waits in the notch, the agent holds its terminal prompt, so the question doesn't show in the terminal or in Claude's Remote Control. Answer in the notch, click **Terminal** to answer there instead, or wait about five minutes for the terminal prompt to come back. **Settings → Agents** picks where questions and approvals go:

- **Auto** (default): the notch while you're using the Mac. If you've been away for 2 minutes or the screen is locked, they go to the terminal, including any already waiting.
- **Notch:** always in the notch.
- **Terminal:** always in the terminal and Remote Control. If NotchLab isn't running, the hook exits immediately and the agents behave as usual. Codex questions aren't supported yet, only its approvals and finished alerts.
