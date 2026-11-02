import AppKit
import ApplicationServices
import Observation
import os
import SystemConfiguration

private let log = Logger(subsystem: "com.hamza.notchapp", category: "vpn")

/// Toggles a VPN from the notch. Three kinds are supported:
/// - System VPNs (IKEv2/IPSec/L2TP, WireGuard, Tailscale, ...) through SystemConfiguration.
/// - App-managed VPNs such as ProtonVPN. These reconnect themselves whenever anything but their
///   own app stops the tunnel, so when allowed we press the app's own Connect/Disconnect button.
/// - Cloudflare WARP through its `warp-cli`.
@Observable
@MainActor
final class VPNController {
    struct Service: Identifiable, Hashable {
        enum Kind: Hashable { case system, warp }
        let id: String
        let name: String
        let kind: Kind
        /// Bundle ID of the app providing an app-based VPN, e.g. "ch.protonvpn.mac".
        let providerBundleID: String?
        let configuredServer: String?
    }

    enum State { case unavailable, off, connecting, connected, disconnecting }

    private(set) var services: [Service] = []
    private(set) var state: State = .unavailable
    private(set) var connectedSince: Date?
    private(set) var server: String?
    private(set) var message: String?

    @ObservationIgnored private var connection: SCNetworkConnection?
    @ObservationIgnored private var attachedID: String?
    @ObservationIgnored private var stopRequestedAt: Date?
    @ObservationIgnored private var startRequestedAt: Date?
    @ObservationIgnored private var messageSetAt: Date?
    @ObservationIgnored private var askedForAppControl = false
    @ObservationIgnored private var warpTimer: Timer?

    private nonisolated static let warpCLI = "/Applications/Cloudflare WARP.app/Contents/Resources/warp-cli"

    var selectedID: String? {
        didSet {
            UserDefaults.standard.set(selectedID, forKey: "vpnService")
            attach()
        }
    }

    init() {
        selectedID = UserDefaults.standard.string(forKey: "vpnService")
        refresh()
    }

    var selected: Service? { services.first { $0.id == selectedID } }
    var isConnected: Bool { state == .connected }
    /// The switch shows "on" while connecting too, so a tap gives immediate feedback.
    var isOn: Bool { state == .connected || state == .connecting }

    var providerAppName: String? {
        guard let url = providerAppURL else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// App-managed VPNs need Accessibility access for an "off" that sticks.
    var needsAppControlPermission: Bool { selected?.providerBundleID != nil && !AXIsProcessTrusted() }

    func statusText(at date: Date) -> String {
        if services.isEmpty { return "None set up" }
        if let message { return message }
        switch state {
        case .connected:
            guard let connectedSince else { return "Connected" }
            let minutes = max(0, Int(date.timeIntervalSince(connectedSince)) / 60)
            return minutes >= 60 ? "Connected · \(minutes / 60)h \(minutes % 60)m" : "Connected · \(minutes)m"
        case .connecting: return "Connecting…"
        case .disconnecting: return "Disconnecting…"
        case .off: return "Off"
        case .unavailable: return selected?.kind == .warp ? "WARP isn't running" : "Unavailable"
        }
    }

    // MARK: Discovery

    func refresh() {
        var found: [Service] = []
        if let prefs = SCPreferencesCreate(nil, "NotchApp" as CFString, nil),
           let all = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] {
            let dynamicStore = SCDynamicStoreCreate(nil, "NotchApp" as CFString, nil, nil)
            for service in all {
                guard SCNetworkServiceGetEnabled(service), let interface = SCNetworkServiceGetInterface(service),
                      let type = SCNetworkInterfaceGetInterfaceType(interface) as String?,
                      let id = SCNetworkServiceGetServiceID(service) as String?, Self.isVPN(type, interface) else { continue }
                let setup = dynamicStore.flatMap { SCDynamicStoreCopyValue($0, "Setup:/Network/Service/\(id)/Interface" as CFString) } as? [String: Any]
                let configured = (SCNetworkInterfaceGetConfiguration(interface) as? [String: Any])?["RemoteAddress"] as? String
                found.append(Service(id: id, name: SCNetworkServiceGetName(service) as String? ?? "VPN", kind: .system,
                                     providerBundleID: setup?["SubType"] as? String, configuredServer: configured))
            }
        }
        if FileManager.default.isExecutableFile(atPath: Self.warpCLI) {
            found.append(Service(id: "warp", name: "Cloudflare WARP", kind: .warp, providerBundleID: nil, configuredServer: nil))
        }
        services = found
        if selected == nil { selectedID = services.first?.id } else { attach() }
    }

    private static func isVPN(_ type: String, _ interface: SCNetworkInterface) -> Bool {
        if type == "VPN" || type == kSCNetworkInterfaceTypeIPSec as String { return true }
        guard type == kSCNetworkInterfaceTypePPP as String else { return false }
        // PPP also covers PPPoE; only L2TP/PPTP over PPP are VPNs.
        let inner = SCNetworkInterfaceGetInterface(interface).flatMap(SCNetworkInterfaceGetInterfaceType) as String?
        return inner == kSCNetworkInterfaceTypeL2TP as String || inner == "PPTP"
    }

    // MARK: Actions

    func toggle() {
        guard let service = selected, state != .unavailable else { return }
        let turnOn = !isOn
        message = nil
        switch service.kind {
        case .warp:
            state = turnOn ? .connecting : .disconnecting
            runWarp(turnOn ? ["connect"] : ["disconnect"]) { [weak self] _ in self?.pollWarp(fast: true) }
        case .system:
            guard let bundleID = service.providerBundleID,
                  NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first != nil else {
                systemToggle(on: turnOn)
                return
            }
            // App-managed VPNs (ProtonVPN) stop any tunnel they didn't start and restart any
            // they didn't stop, so the reliable route is the app's own button.
            guard AXIsProcessTrusted() else {
                log.notice("No Accessibility access; trying the system switch")
                // Ask once per launch; the menu has an item to ask again.
                if !askedForAppControl {
                    askedForAppControl = true
                    requestAppControlPermission()
                }
                systemToggle(on: turnOn)
                return
            }
            state = turnOn ? .connecting : .disconnecting
            Task {
                let titles = turnOn ? ["Quick Connect", "Connect"] : ["Disconnect"]
                if await ProviderAppControl.press(titles, inAppWith: bundleID) { return }
                log.error("Couldn't find \(titles, privacy: .public) in \(bundleID, privacy: .public); using the system switch")
                self.systemToggle(on: turnOn)
            }
        }
    }

    func requestAppControlPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openProviderApp() {
        guard let url = providerAppURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private var providerAppURL: URL? {
        if selected?.kind == .warp { return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.cloudflare.1dot1dot1dot1.macos") }
        return selected?.providerBundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }

    private func systemToggle(on: Bool) {
        guard let connection else { return }
        if on {
            stopRequestedAt = nil
            startRequestedAt = Date()
            if SCNetworkConnectionStart(connection, nil, false) { state = .connecting } else { message = "Couldn't connect" }
        } else {
            startRequestedAt = nil
            stopRequestedAt = Date()
            if SCNetworkConnectionStop(connection, true) { state = .disconnecting } else { message = "Couldn't disconnect" }
        }
    }

    // MARK: System VPN status

    private func attach() {
        // @Observable runs `selectedID`'s observer during init, before services are loaded,
        // so only count as attached once the service actually exists.
        guard let service = selected, attachedID != service.id else { return }
        attachedID = service.id
        if let connection { SCNetworkConnectionSetDispatchQueue(connection, nil) }
        connection = nil
        warpTimer?.invalidate()
        warpTimer = nil
        state = .unavailable
        message = nil
        connectedSince = nil
        server = nil

        if service.kind == .warp {
            pollWarp(fast: false)
            return
        }
        var context = SCNetworkConnectionContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                                 retain: nil, release: nil, copyDescription: nil)
        let callback: SCNetworkConnectionCallBack = { _, _, info in
            guard let info else { return }
            let controller = Unmanaged<VPNController>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { controller.updateSystemStatus() }
        }
        guard let connection = SCNetworkConnectionCreateWithServiceID(nil, service.id as CFString, callback, &context) else { return }
        SCNetworkConnectionSetDispatchQueue(connection, .main)
        self.connection = connection
        updateSystemStatus()
    }

    private func updateSystemStatus() {
        guard let connection else { return }
        switch SCNetworkConnectionGetStatus(connection) {
        case .connected: state = .connected
        case .connecting: state = .connecting
        case .disconnecting: state = .disconnecting
        case .disconnected: state = .off
        default: state = .unavailable
        }
        let extended = SCNetworkConnectionCopyExtendedStatus(connection) as? [String: Any]
        let vpn = extended?["VPN"] as? [String: Any]
        // App VPNs often tunnel through a local endpoint; show the configured server instead.
        let live = vpn?["RemoteAddress"] as? String
        server = (live == nil || live!.hasPrefix("127.") || live == "::1") ? selected?.configuredServer : live
        // ConnectTime is in seconds of system uptime, the same clock as systemUptime.
        if state == .connected, let connectTime = (vpn?["ConnectTime"] as? NSNumber)?.doubleValue, connectTime > 0 {
            connectedSince = Date().addingTimeInterval(-(ProcessInfo.processInfo.systemUptime - connectTime))
        } else if state != .connected {
            connectedSince = nil
        }

        // The provider app overrode us (restarted after a stop, or stopped after a start).
        // Say so instead of leaving the switch looking broken.
        let now = Date()
        if let stop = stopRequestedAt, now.timeIntervalSince(stop) < 8, state == .connecting || state == .connected {
            stopRequestedAt = nil
            showOverride("reconnected it")
        } else if let start = startRequestedAt, now.timeIntervalSince(start) < 8, state == .off {
            startRequestedAt = nil
            showOverride("blocked it")
        } else if state == .connected {
            startRequestedAt = nil
        }
        if let messageSetAt, now.timeIntervalSince(messageSetAt) > 8 { message = nil }
    }

    private func showOverride(_ what: String) {
        guard let app = providerAppName else { return }
        message = "\(app) \(what)" + (needsAppControlPermission ? " · allow in menu" : "")
        messageSetAt = Date()
    }

    // MARK: WARP

    private func pollWarp(fast: Bool) {
        warpTimer?.invalidate()
        var remainingFast = fast ? 20 : 0
        warpTimer = Timer.scheduledTimer(withTimeInterval: fast ? 0.5 : 5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                self.readWarpStatus()
                if remainingFast > 0 {
                    remainingFast -= 1
                    if remainingFast == 0 { self.pollWarp(fast: false) }
                }
            }
        }
        readWarpStatus()
    }

    private func readWarpStatus() {
        runWarp(["status"]) { [weak self] output in
            guard let self, self.selected?.kind == .warp else { return }
            let text = output.lowercased()
            if text.contains("unable to connect") || output.isEmpty { self.state = .unavailable }
            else if text.contains("disconnected") { self.state = .off; self.connectedSince = nil }
            else if text.contains("connecting") { self.state = .connecting }
            else if text.contains("connected") {
                if self.state != .connected { self.connectedSince = Date() }
                self.state = .connected
            }
        }
    }

    private func runWarp(_ arguments: [String], completion: @escaping @MainActor (String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: Self.warpCLI)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            var output = ""
            if (try? process.run()) != nil {
                output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                process.waitUntilExit()
            }
            DispatchQueue.main.async { completion(output) }
        }
    }

    /// Stops background WARP polling while the home page isn't visible.
    func setVisible(_ visible: Bool) {
        guard selected?.kind == .warp else { return }
        if visible { pollWarp(fast: false) } else { warpTimer?.invalidate(); warpTimer = nil }
    }
}

/// Presses a button or menu item in another app through the Accessibility API.
@MainActor
enum ProviderAppControl {
    /// `titles` are tried in order; e.g. "Quick Connect" before a generic "Connect", which in
    /// ProtonVPN also labels each country row.
    static func press(_ titles: [String], inAppWith bundleID: String) async -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // Menu bar items and open windows can be pressed without showing anything.
        if let target = find(titles, in: element) { return perform(target, in: bundleID) }

        // Otherwise bring up the main window, press, and hide the app again.
        guard let url = app.bundleURL else { return false }
        log.notice("No button visible in \(bundleID, privacy: .public); opening its window")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        for _ in 0..<15 {
            try? await Task.sleep(for: .milliseconds(150))
            if let target = find(titles, in: element) {
                let pressed = perform(target, in: bundleID)
                app.hide()
                return pressed
            }
        }
        log.error("Labels seen in \(bundleID, privacy: .public): \(labels(in: element).joined(separator: " | "), privacy: .public)")
        return false
    }

    private static func perform(_ target: AXUIElement, in bundleID: String) -> Bool {
        let result = AXUIElementPerformAction(target, kAXPressAction as CFString)
        log.notice("Pressed '\(label(of: target) ?? "?", privacy: .public)' in \(bundleID, privacy: .public): \(result.rawValue)")
        return result == .success
    }

    private static func find(_ titles: [String], in app: AXUIElement) -> AXUIElement? {
        let candidates = pressable(in: app)
        for title in titles {
            if let match = candidates.first(where: { $0.label == title }) { return match.element }
        }
        return nil
    }

    /// Enabled buttons and menu items, breadth-first so top-level controls come first.
    /// Windows are searched before the app's menus, and the system Apple menu (Restart,
    /// Shut Down, ...) is never searched.
    private static func pressable(in app: AXUIElement) -> [(element: AXUIElement, label: String)] {
        var queue: [AXUIElement] = (attribute(app, kAXWindowsAttribute) as [AXUIElement]?) ?? []
        if let menuBar: AXUIElement = attribute(app, kAXMenuBarAttribute) {
            queue += ((attribute(menuBar, kAXChildrenAttribute) as [AXUIElement]?) ?? []).dropFirst()
        }
        var found: [(AXUIElement, String)] = []
        var visited = 0
        while !queue.isEmpty, visited < 4000 {
            let element = queue.removeFirst()
            visited += 1
            let role: String? = attribute(element, kAXRoleAttribute)
            if role == kAXButtonRole as String || role == kAXMenuItemRole as String,
               (attribute(element, kAXEnabledAttribute) as Bool?) ?? true, let label = label(of: element) {
                found.append((element, label))
            }
            queue += (attribute(element, kAXChildrenAttribute) as [AXUIElement]?) ?? []
        }
        return found
    }

    private static func labels(in app: AXUIElement) -> [String] {
        Array(Set(pressable(in: app).map(\.label))).sorted().prefix(60).map { $0 }
    }

    private static func label(of element: AXUIElement) -> String? {
        for key in [kAXTitleAttribute, kAXDescriptionAttribute] {
            if let value: String = attribute(element, key), !value.isEmpty { return value }
        }
        // SwiftUI buttons often carry their text in a child static text.
        let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) ?? []
        return children.lazy.compactMap { attribute($0, kAXValueAttribute) as String? }.first
    }

    private static func attribute<T>(_ element: AXUIElement, _ key: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
