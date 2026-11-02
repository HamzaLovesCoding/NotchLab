import SwiftUI

/// Black notch silhouette: concave "ears" where it meets the screen edge, rounded bottom.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let top = topRadius
        let bottom = max(0, min(bottomRadius, rect.height - top, (rect.width - 2 * top) / 2))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top), control: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY), control: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom), control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct NotchRootView: View {
    let model: NotchModel
    private static let celebrationWing: CGFloat = 64
    private static let agentWing: CGFloat = 88

    var body: some View {
        let expanded = model.isExpanded
        let celebrating = model.focusTimer.celebrating
        // Questions and approvals always show; the "Done" flash can be turned off in Settings.
        let agentAlert = model.agents.alert.flatMap { $0.pending || model.settings.showFinishedAlert ? $0 : nil }
        let showWings = (celebrating || agentAlert != nil) && !expanded
        let size = expanded ? model.panelSize : model.notchSize
        let wing = celebrating ? Self.celebrationWing : Self.agentWing
        let width = size.width + (showWings ? wing * 2 : 0)
        let ear: CGFloat = expanded ? 10 : 0
        // Collapsed corners are rounder than the hardware notch so no black pixel can peek
        // out from under it; width and height match the notch exactly.
        let shape = NotchShape(topRadius: ear, bottomRadius: expanded ? 24 : model.notchSize.height * 0.4)

        ZStack(alignment: .top) {
            if expanded {
                ExpandedView(model: model)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.06)),
                        removal: .opacity.animation(.easeIn(duration: 0.08))))
            } else if showWings {
                Group {
                    if celebrating {
                        CelebrationWings(timer: model.focusTimer, notchWidth: model.notchSize.width, wing: wing)
                    } else if let agentAlert {
                        AgentWings(alert: agentAlert, notchWidth: model.notchSize.width, wing: wing)
                    }
                }
                .frame(width: width, height: size.height)
                .transition(.opacity.animation(.easeOut(duration: 0.2).delay(0.12)))
            }
        }
        .frame(width: width + ear * 2, height: size.height, alignment: .top)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .shadow(color: .black.opacity(expanded ? 0.5 : 0), radius: 12, y: 4)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: expanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.88), value: model.panelSize)
        .animation(.spring(response: 0.4, dampingFraction: 0.68), value: showWings)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if celebrating {
                GeometryReader { geometry in
                    ConfettiBurst(origin: CGPoint(x: geometry.size.width / 2, y: size.height), spread: width / 2)
                }
                .allowsHitTesting(false)
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

struct ExpandedView: View {
    let model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model)
                .frame(height: model.notchSize.height)
            ZStack(alignment: .topTrailing) {
                // Fixed height so the page doesn't re-layout when the clipboard popup
                // makes the panel taller.
                Group {
                    if model.showSettings {
                        SettingsView(model: model)
                    } else {
                        switch model.tab {
                        case .home: HomeView(model: model)
                        case .shelf: ShelfView(model: model)
                        case .reminders: RemindersView(store: model.reminders)
                        case .dev: DevView(model: model)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: model.pageArea - NotchModel.pagePadding, alignment: .top)
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .frame(maxHeight: .infinity, alignment: .top)

                if model.showClipboard {
                    Color.black.opacity(0.45)
                        .contentShape(Rectangle())
                        .onTapGesture { model.showClipboard = false }
                        .transition(.opacity)
                    ClipboardPopup(history: model.clipboard) { model.showClipboard = false }
                        .frame(width: 300)
                        .padding(.trailing, 14)
                        .padding(.top, 2)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                }
            }
            .animation(.easeOut(duration: 0.15), value: model.showClipboard)
        }
    }
}

struct TopBar: View {
    let model: NotchModel

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(model.visibleTabs, id: \.self) { tab in
                    IconButton(symbol: tab.symbol, active: model.tab == tab && !model.showSettings, help: tab.title) {
                        model.statDetail = nil
                        model.showSettings = false
                        model.tab = tab
                    }
                    .overlay(alignment: .topTrailing) {
                        if tab == .dev, !model.agents.requests.isEmpty {
                            Circle().fill(.orange).frame(width: 6, height: 6).offset(x: -5, y: 4)
                        }
                    }
                }
            }
            Spacer(minLength: model.notchSize.width + 12)
            HStack(spacing: 2) {
                if model.tab == .home, !model.showSettings, model.settings.showMirrorButton {
                    IconButton(symbol: model.mirror.isOn ? "web.camera.fill" : "web.camera",
                               active: model.mirror.isOn, help: "Mirror") {
                        model.mirror.isOn.toggle()
                    }
                }
                IconButton(symbol: "doc.on.clipboard", active: model.showClipboard, help: "Clipboard history") {
                    model.showClipboard.toggle()
                }
                IconButton(symbol: "gearshape.fill", active: model.showSettings, help: "Settings") {
                    model.showSettings.toggle()
                }
            }
        }
        .padding(.horizontal, 18)
    }
}

/// SwiftUI's Menu wraps an AppKit control that can swallow the first click in a
/// non-activating panel, so menus are plain buttons that pop up an NSMenu at the pointer.
@MainActor
func popUpMenu(_ items: [NSMenuItem]) {
    let menu = NSMenu()
    menu.autoenablesItems = false
    items.forEach(menu.addItem)
    menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
}

final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}

// MARK: Shared components

struct IconButton: View {
    let symbol: String
    var active = false
    var size: CGFloat = 13
    var help: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(active ? 1 : (hovering ? 0.8 : 0.45)))
                .frame(width: 30, height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(active ? 0.12 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help ?? "")
        .accessibilityLabel(help ?? symbol)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.07)))
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}

func formatDuration(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
    return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
}
