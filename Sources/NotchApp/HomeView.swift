import SwiftUI

struct HomeView: View {
    let model: NotchModel

    var body: some View {
        if model.notes.isOpen {
            NotesPanel(store: model.notes)
        } else {
            HStack(spacing: 14) {
                MusicPlayerView(player: model.nowPlaying, outputs: model.audioOutputs)
                    .frame(width: 286)
                // Fills the mirror's space while the mirror is off.
                VStack(spacing: 6) {
                    TimerCard(timer: model.focusTimer)
                        .frame(height: 58)
                    VPNRow(vpn: model.vpn)
                        .frame(height: 36)
                    NoteRow(store: model.notes)
                        .frame(height: 36)
                }
                if model.mirror.isOn {
                    MirrorTile(mirror: model.mirror)
                        .frame(width: 140, height: 140)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.mirror.isOn)
        }
    }
}

// MARK: Music

struct MusicPlayerView: View {
    let player: NowPlaying
    let outputs: AudioOutputs

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(player: player)
                .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 0) {
                Text(player.hasContent ? player.title : "Nothing playing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(player.hasContent ? 1 : 0.5))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .padding(.top, 2)
                ProgressRow(player: player)
                    .padding(.top, 10)
                controls
                    .padding(.top, 8)
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear { outputs.refresh() }
    }

    private var subtitle: String {
        guard player.hasContent else { return player.bridgeFailed ? "Media info unavailable" : "Play music or a video" }
        return player.artist.isEmpty ? player.appName : player.artist
    }

    private var controls: some View {
        HStack(spacing: 0) {
            controlButton("backward.fill", label: "Previous track", size: 14, action: player.previous)
            controlButton(player.isPlaying ? "pause.fill" : "play.fill", label: player.isPlaying ? "Pause" : "Play",
                          size: 20, action: player.togglePlayPause)
                .frame(width: 44)
            controlButton("forward.fill", label: "Next track", size: 14, action: player.next)
            Spacer()
            OutputPicker(outputs: outputs)
        }
    }

    private func controlButton(_ symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

struct ArtworkView: View {
    let player: NowPlaying

    var body: some View {
        Button(action: player.openSourceApp) {
            ZStack(alignment: .bottomTrailing) {
                if let artwork = player.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if let icon = player.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                            .offset(x: 5, y: 5)
                    }
                } else if let icon = player.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.07))
                        .overlay(Image(systemName: "music.note").font(.system(size: 26)).foregroundStyle(.white.opacity(0.3)))
                }
            }
        }
        .buttonStyle(PressableStyle())
        .help(player.appName.isEmpty ? "" : "Open \(player.appName)")
    }
}

struct ProgressRow: View {
    let player: NowPlaying

    var body: some View {
        if player.duration > 0 {
            // Ticks once a second only while playing.
            TimelineView(.periodic(from: .now, by: player.isPlaying ? 1 : 3600)) { context in
                let elapsed = player.elapsed(at: context.date)
                VStack(spacing: 4) {
                    SeekBar(progress: elapsed / player.duration) { player.seek(to: $0 * player.duration) }
                    HStack {
                        Text(formatDuration(elapsed))
                        Spacer()
                        Text("-" + formatDuration(player.duration - elapsed))
                    }
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
                }
            }
        } else {
            // Some sources (e.g. browser videos) don't report a position; show the source instead.
            HStack(spacing: 5) {
                if player.hasContent, !player.appName.isEmpty {
                    Circle().fill(player.isPlaying ? Color.green : Color.white.opacity(0.3)).frame(width: 5, height: 5)
                    Text(player.appName)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.45))
            .frame(height: 20, alignment: .leading)
        }
    }
}

struct SeekBar: View {
    let progress: Double
    let onSeek: (Double) -> Void
    @State private var dragProgress: Double?

    var body: some View {
        GeometryReader { geometry in
            let value = min(max(dragProgress ?? progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(.white).frame(width: max(4, geometry.size.width * value))
            }
            .frame(height: dragProgress == nil ? 4 : 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { dragProgress = $0.location.x / max(geometry.size.width, 1) }
                .onEnded { _ in
                    if let dragProgress { onSeek(min(max(dragProgress, 0), 1)) }
                    dragProgress = nil
                })
        }
        .frame(height: 10)
        .animation(.easeOut(duration: 0.12), value: dragProgress == nil)
    }
}

struct OutputPicker: View {
    let outputs: AudioOutputs

    var body: some View {
        Button(action: showMenu) {
            Image(systemName: outputs.current?.symbol ?? "speaker.wave.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help(outputs.current.map { "Output: \($0.name)" } ?? "Audio output")
        .accessibilityLabel("Audio output")
    }

    private func showMenu() {
        outputs.refresh()
        let header = NSMenuItem(title: "Audio Output", action: nil, keyEquivalent: "")
        header.isEnabled = false
        popUpMenu([header] + outputs.devices.map { device in
            ActionMenuItem(device.name, checked: device.id == outputs.currentID) { outputs.select(device) }
        })
    }
}

// MARK: Timer

struct TimerCard: View {
    let timer: FocusTimer

    var body: some View {
        // Ticks once a second only while running.
        TimelineView(.periodic(from: .now, by: timer.isRunning ? 1 : 3600)) { context in
            let remaining = timer.remaining(at: context.date)
            Card(padding: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        TimeFields(timer: timer, seconds: Int(remaining.rounded(.up)))
                        Spacer(minLength: 0)
                        roundButton(timer.isRunning ? "pause.fill" : "play.fill", label: timer.isRunning ? "Pause timer" : "Start timer",
                                    fill: timer.isRunning ? Color.orange : Color.green, action: timer.toggle)
                        roundButton("arrow.counterclockwise", label: "Reset timer", fill: .white.opacity(0.14), action: timer.reset)
                    }
                    HStack(spacing: 4) {
                        ForEach(FocusTimer.presets) { preset in
                            presetButton(preset)
                        }
                        Spacer(minLength: 0)
                        SessionDots(count: timer.sessionsToday)
                    }
                }
            }
            // The card fills with the timer's color as the countdown runs.
            .background {
                GeometryReader { geometry in
                    timer.color.opacity(0.16)
                        .frame(width: geometry.size.width * (timer.isIdle ? 0 : 1 - remaining / timer.duration))
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func presetButton(_ preset: TimerPreset) -> some View {
        let selected = timer.preset == preset
        return Button { timer.select(preset) } label: {
            Text(preset.name)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(selected ? preset.color : .white.opacity(0.5))
                .fixedSize()
                .padding(.horizontal, 5)
                .frame(minHeight: 16)
                .background(Capsule().fill(selected ? preset.color.opacity(0.22) : .white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help("\(preset.name) · \(preset.minutes) min")
    }

    private func roundButton(_ symbol: String, label: String, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(fill))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// Hours : minutes : seconds boxes. Click a box and type to set a custom time.
private struct TimeFields: View {
    let timer: FocusTimer
    let seconds: Int

    var body: some View {
        let parts = [seconds / 3600, seconds % 3600 / 60, seconds % 60]
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                if index > 0 {
                    Text(":").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.3))
                }
                TimeBox(value: parts[index], limit: index == 0 ? 23 : 59, editable: timer.isIdle,
                        tint: timer.isRunning ? timer.color : .white, label: ["Hours", "Minutes", "Seconds"][index]) { value in
                    var updated = parts
                    updated[index] = value
                    timer.setDuration(TimeInterval(updated[0] * 3600 + updated[1] * 60 + updated[2]))
                }
            }
        }
    }
}

private struct TimeBox: View {
    let value: Int
    let limit: Int
    let editable: Bool
    let tint: Color
    let label: String
    let onCommit: (Int) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private var formatted: String { String(format: "%02d", value) }

    var body: some View {
        Group {
            if editable {
                // Cleared on focus so typing replaces the value; the old value stays as the placeholder.
                TextField(formatted, text: $text)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onSubmit { focused = false }
                    .onChange(of: text) { _, new in
                        let digits = String(new.filter(\.isNumber).prefix(2))
                        if digits != new { text = digits }
                    }
                    .onChange(of: focused) { _, isFocused in
                        if isFocused { text = "" } else { commit() }
                    }
                    .onChange(of: value) { if !focused { text = formatted } }
                    .onAppear { text = formatted }
            } else {
                Text(formatted).foregroundStyle(tint)
            }
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
        .frame(width: 27, height: 22)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(focused ? 0.2 : 0.08)))
        .help(editable ? "Click to set \(label.lowercased())" : "")
        .accessibilityLabel(label)
    }

    private func commit() {
        if let number = Int(text), min(number, limit) != value { onCommit(min(number, limit)) }
        text = formatted
    }
}

/// One dot per focus session finished today, four slots to fill.
struct SessionDots: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(index < count ? FocusTimer.presets[0].color : .white.opacity(0.14))
                    .frame(width: 6, height: 6)
                    .scaleEffect(index < count ? 1 : 0.75)
            }
            if count > 4 {
                Text("+\(count - 4)")
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(FocusTimer.presets[0].color)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.5), value: count)
        .help("\(count) focus session\(count == 1 ? "" : "s") today")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) focus sessions today")
    }
}

/// Shown beside the closed notch for a few seconds when a countdown ends.
struct CelebrationWings: View {
    let timer: FocusTimer
    let notchWidth: CGFloat
    let wing: CGFloat
    @State private var popped = false

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(timer.finishedColor)
                .scaleEffect(popped ? 1 : 0.2)
                .frame(width: wing)
            Spacer(minLength: notchWidth)
            Group {
                if timer.lastFinishedWasBreak {
                    Text("Break over").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(timer.finishedColor)
                } else {
                    SessionDots(count: timer.sessionsToday)
                }
            }
            .frame(width: wing)
        }
        .onAppear { withAnimation(.spring(response: 0.35, dampingFraction: 0.5).delay(0.15)) { popped = true } }
    }
}

/// One-shot confetti from the bottom of the notch.
struct ConfettiBurst: View {
    let origin: CGPoint
    let spread: CGFloat
    @State private var start = Date()
    @State private var pieces = (0..<48).map { _ in Piece() }

    private static let colors = FocusTimer.presets.map(\.color) + [FocusTimer.customColor, Note.accent, .white]
    private static let lifetime = 2.0

    struct Piece {
        let offset = CGFloat.random(in: -1...1)
        let angle = Double.random(in: 0.06...0.94) * .pi
        let speed = Double.random(in: 90...280)
        let spin = Double.random(in: -10...10)
        let size = CGFloat.random(in: 5...9)
        let color = ConfettiBurst.colors.randomElement() ?? .white
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
            let t = context.date.timeIntervalSince(start)
            Canvas { canvas, _ in
                guard t < Self.lifetime else { return }
                canvas.opacity = min(1, (Self.lifetime - t) / 0.6)
                for piece in pieces {
                    var context = canvas
                    context.translateBy(x: origin.x + piece.offset * spread + cos(piece.angle) * piece.speed * t,
                                        y: origin.y + sin(piece.angle) * piece.speed * t + 170 * t * t)
                    context.rotate(by: .radians(piece.spin * t))
                    context.fill(Path(CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2)),
                                 with: .color(piece.color))
                }
            }
        }
    }
}

// MARK: VPN

struct VPNRow: View {
    let vpn: VPNController

    var body: some View {
        Card(padding: 0) {
            HStack(spacing: 8) {
                Button(action: showMenu) {
                    HStack(spacing: 8) {
                        Image(systemName: vpn.isConnected ? "lock.shield.fill" : "lock.shield")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(vpn.isConnected ? Color.green : .white.opacity(0.45))
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(vpn.selected?.name ?? "VPN")
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            TimelineView(.periodic(from: .now, by: vpn.isConnected ? 30 : 3600)) { context in
                                Text(vpn.statusText(at: context.date))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(vpn.message == nil ? .white.opacity(0.45) : Color.orange.opacity(0.9))
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Choose VPN and settings")
                .accessibilityLabel("VPN options")
                SwitchView(isOn: vpn.isOn, enabled: vpn.selected != nil && vpn.state != .unavailable, action: vpn.toggle)
                    .accessibilityLabel("VPN")
                    .accessibilityValue(vpn.isOn ? "On" : "Off")
            }
            .padding(.horizontal, 10)
        }
        .onAppear { vpn.setVisible(true) }
        .onDisappear { vpn.setVisible(false) }
    }

    private func showMenu() {
        vpn.refresh()
        var items: [NSMenuItem] = []
        if vpn.services.isEmpty {
            let none = NSMenuItem(title: "No VPNs set up in System Settings", action: nil, keyEquivalent: "")
            none.isEnabled = false
            items.append(none)
        } else {
            let header = NSMenuItem(title: "VPN", action: nil, keyEquivalent: "")
            header.isEnabled = false
            items.append(header)
            items += vpn.services.map { service in
                ActionMenuItem(service.name, checked: service.id == vpn.selectedID) { vpn.selectedID = service.id }
            }
        }
        items.append(.separator())
        if vpn.needsAppControlPermission, let app = vpn.providerAppName {
            // Without this, the app undoes "off" by reconnecting itself.
            items.append(ActionMenuItem("Let Notch Use \(app)'s Buttons…", handler: vpn.requestAppControlPermission))
        }
        if let server = vpn.server, vpn.isConnected {
            let info = NSMenuItem(title: "Server  \(server)", action: nil, keyEquivalent: "")
            info.isEnabled = false
            items.append(info)
        }
        if let app = vpn.providerAppName {
            items.append(ActionMenuItem("Open \(app)…", handler: vpn.openProviderApp))
        }
        items.append(ActionMenuItem("VPN Settings…", handler: vpn.openSystemSettings))
        popUpMenu(items)
    }
}

/// Drawn in SwiftUI rather than NSSwitch so the first click in the non-activating panel registers.
struct SwitchView: View {
    let isOn: Bool
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(isOn ? Color.green : .white.opacity(0.18))
                .frame(width: 30, height: 18)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(.white).padding(2).shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isOn)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

// MARK: Mirror

struct MirrorTile: View {
    let mirror: Mirror

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.07))
            CameraPreview(session: mirror.session, running: mirror.isRunning)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .opacity(mirror.isRunning ? 1 : 0)
            if let message = mirror.message {
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(10)
            } else if !mirror.isRunning {
                ProgressView().controlSize(.small)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mirror")
        // Only on screen while the mirror is on, so the camera follows the tile.
        .onAppear { mirror.start() }
        .onDisappear { mirror.stop() }
    }
}
