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

## Install

Requires an **Apple silicon Mac**, **macOS 14 or later**, and **Xcode Command Line Tools with Swift 6 or later**.

Install the command line tools if needed:

```sh
xcode-select --install
```

Then build and install:

```sh
git clone https://github.com/HamzaLovesCoding/NotchLab.git
cd NotchLab
./build.sh --install
```

The script installs and opens `/Applications/NotchApp.app`. Hover over the notch to get started. You can enable **Launch at Login** from the settings menu.

Allow Camera and Reminders access when using those features. Controlling some VPN apps also requires Accessibility access.

Agent alerts, questions, and approvals require configuring your coding tool's hooks to call the bundled `notch-hook` helper. Building the app does not install those hooks automatically.
