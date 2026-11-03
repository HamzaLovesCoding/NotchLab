import AppKit
import Observation
import SwiftUI

/// What the music player shows and controls, picked in Settings › Home.
enum MediaSource: String, CaseIterable {
    case automatic, spotify, music

    var title: String {
        switch self {
        case .automatic: "Whatever's playing"
        case .spotify: "Spotify"
        case .music: "Apple Music"
        }
    }

    var bundleID: String? {
        switch self {
        case .automatic: nil
        case .spotify: "com.spotify.client"
        case .music: "com.apple.Music"
        }
    }

    /// Posted by the app whenever its playback changes.
    var notification: String? {
        switch self {
        case .automatic: nil
        case .spotify: "com.spotify.client.PlaybackStateChanged"
        case .music: "com.apple.Music.playerInfo"
        }
    }
}

/// Now-playing state. On automatic it follows whatever app owns the system media session
/// (Music, Spotify, browsers, ...), with data from MediaRemoteBridge.m running inside
/// /usr/bin/perl. macOS only shares that one session, so when Spotify or Apple Music is
/// picked instead, NotchLab asks that app directly over AppleScript.
@Observable
@MainActor
final class NowPlaying {
    private(set) var title = ""
    private(set) var artist = ""
    private(set) var duration: Double = 0
    private(set) var isPlaying = false
    private(set) var artwork: NSImage? {
        didSet { if artwork !== oldValue { tint = artwork.flatMap(Self.tint(of:)) } }
    }
    /// The artwork's color, brightened to read on black; nil for gray art.
    private(set) var tint: Color?
    private(set) var appIcon: NSImage?
    private(set) var appName = ""
    private(set) var bundleID: String?
    private(set) var bridgeFailed = false
    /// Why a picked app shows nothing, e.g. it isn't open.
    private(set) var status: String?

    // Position is extrapolated from the last report instead of polled.
    private var elapsedAtTimestamp: Double = 0
    private var rate: Double = 0
    private var timestamp = Date()

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var input: FileHandle?
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var restartDelay: TimeInterval = 1
    @ObservationIgnored private let settings: AppSettings
    /// The system session, kept while an app is picked so switching back is instant.
    @ObservationIgnored private var lastBridgeUpdate: NowPlayingUpdate?
    @ObservationIgnored private var bridgeArtwork: NSImage?
    @ObservationIgnored private var scripts: [String: NSAppleScript] = [:]
    @ObservationIgnored private var appTrack = ""
    @ObservationIgnored private var appWatcher: AppWatcher?

    init(settings: AppSettings) {
        self.settings = settings
    }

    var hasContent: Bool { !title.isEmpty }
    var source: MediaSource { settings.mediaSource }

    func setSource(_ source: MediaSource) {
        settings.mediaSource = source
        clear()
        if source == .automatic {
            if let lastBridgeUpdate { show(lastBridgeUpdate) }
        } else {
            refreshFromApp()
        }
    }

    private static let loader = """
    use DynaLoader;
    my $h = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
    my $s = DynaLoader::dl_find_symbol($h, "notch_bridge_run") or die "missing symbol";
    DynaLoader::dl_install_xsub("main::run", $s);
    run();
    """

    func elapsed(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        var value = elapsedAtTimestamp
        if isPlaying { value += date.timeIntervalSince(timestamp) * (rate > 0 ? rate : 1) }
        return min(max(value, 0), duration)
    }

    // MARK: Commands

    func togglePlayPause() {
        // With nothing loaded there's no telling whether anything will play; wait for the report.
        if hasContent {
            isPlaying.toggle()
            if !isPlaying { freezePosition() }
        }
        // playpause also opens the app if it's closed.
        if source == .automatic { send("toggle") } else { tellApp("playpause") }
    }

    func next() {
        if source == .automatic { send("next") } else { tellApp("next track") }
    }

    func previous() {
        if source == .automatic { send("prev") } else { tellApp("previous track") }
    }

    func seek(to seconds: Double) {
        elapsedAtTimestamp = seconds
        timestamp = Date()
        if source == .automatic { send("seek \(seconds)") } else { tellApp("set player position to \(seconds)") }
    }

    func openSourceApp() {
        guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func freezePosition() {
        elapsedAtTimestamp = elapsed(at: Date())
        timestamp = Date()
    }

    private func send(_ command: String) {
        guard let input, let data = (command + "\n").data(using: .utf8) else { return }
        try? input.write(contentsOf: data)
    }

    // MARK: Bridge process

    func start() {
        if appWatcher == nil {
            appWatcher = AppWatcher { [weak self] in
                guard let self, self.source != .automatic else { return }
                self.refreshFromApp()
            }
            if source != .automatic { refreshFromApp() }
        }
        guard process == nil else { return }
        stopping = false
        guard let dylib = Bundle.main.url(forResource: "libNotchMediaBridge", withExtension: "dylib") else {
            bridgeFailed = true
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.loader, dylib.path]
        let output = Pipe(), input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice

        let reader = LineReader()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            for update in reader.feed(data) {
                DispatchQueue.main.async { self?.apply(update) }
            }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.bridgeExited() }
        }
        // A command sent just after the bridge died would otherwise kill NotchLab with SIGPIPE.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do {
            try process.run()
            self.process = process
            self.input = input.fileHandleForWriting
        } catch {
            bridgeFailed = true
        }
    }

    func stop() {
        stopping = true
        process?.terminate()
        process = nil
        input = nil
    }

    private func bridgeExited() {
        process = nil
        input = nil
        guard !stopping else { return }
        // Restart with backoff so a crash loop can't spin the CPU.
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, 60)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.start() }
    }

    private func apply(_ update: NowPlayingUpdate) {
        // The bridge reports an error right before it exits, so that mustn't reset the backoff.
        if update.error {
            bridgeFailed = true
            return
        }
        restartDelay = 1
        bridgeFailed = false
        if let artworkData = update.artwork {
            bridgeArtwork = NSImage(data: artworkData)
        } else if update.noArtwork || update.empty {
            bridgeArtwork = nil
        }
        lastBridgeUpdate = update
        if source == .automatic { show(update) }
    }

    private func show(_ update: NowPlayingUpdate) {
        guard !update.empty else {
            clear()
            return
        }
        title = update.title
        artist = update.artist
        duration = update.duration
        isPlaying = update.playing
        rate = update.rate
        elapsedAtTimestamp = update.elapsed
        timestamp = update.timestamp
        artwork = bridgeArtwork
        setApp(update.bundle)
    }

    private func clear() {
        title = ""; artist = ""; duration = 0; isPlaying = false
        artwork = nil; status = nil; appTrack = ""
        setApp(nil)
    }

    private func setApp(_ bundle: String?) {
        guard bundle != bundleID else { return }
        bundleID = bundle
        if let bundle, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            appIcon = NSWorkspace.shared.icon(forFile: url.path)
            appName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        } else {
            appIcon = nil
            appName = ""
        }
    }

    /// Averages the artwork down to one color, then lifts its brightness so bars and the
    /// progress line stay visible on the black notch.
    private static func tint(of image: NSImage) -> Color? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var sums = [0.0, 0.0, 0.0]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            for channel in 0..<3 { sums[channel] += Double(pixels[index + channel]) }
        }
        let count = Double(side * side) * 255
        let average = NSColor(srgbRed: sums[0] / count, green: sums[1] / count, blue: sums[2] / count, alpha: 1)
        guard average.saturationComponent > 0.15 else { return nil }
        return Color(hue: average.hueComponent, saturation: min(average.saturationComponent * 1.2, 0.85),
                     brightness: max(average.brightnessComponent, 0.85))
    }

    // MARK: A picked app

    /// Reads the picked app's player over AppleScript. Called when the app reports a change,
    /// launches or quits, and after each command.
    private func refreshFromApp() {
        guard let bundle = source.bundleID else { return }
        setApp(bundle)
        let name = source.title
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) != nil else {
            showNothing("\(name) isn't installed")
            return
        }
        // Asking a closed app anything would open it.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty else {
            showNothing("Press play to open \(name)")
            return
        }
        // Spotify reports duration in milliseconds, Music in seconds.
        let duration = source == .spotify ? "(duration of t) / 1000" : "duration of t"
        guard let result = run("""
            tell application id "\(bundle)"
                if player state is stopped then return {"", "", 0, 0, "stopped"}
                set t to current track
                return {name of t, artist of t, \(duration), player position, player state as text}
            end tell
            """) else { return }
        let track = result.atIndex(1)?.stringValue ?? ""
        guard !track.isEmpty else {
            showNothing("Nothing playing in \(name)")
            return
        }
        title = track
        artist = result.atIndex(2)?.stringValue ?? ""
        self.duration = result.atIndex(3)?.doubleValue ?? 0
        elapsedAtTimestamp = result.atIndex(4)?.doubleValue ?? 0
        timestamp = Date()
        rate = 1
        isPlaying = result.atIndex(5)?.stringValue == "playing"
        status = nil
        let key = track + "\n" + artist
        if key != appTrack {
            appTrack = key
            artwork = nil
            loadAppArtwork(for: key)
        }
    }

    private func showNothing(_ reason: String) {
        title = ""; artist = ""; duration = 0; isPlaying = false
        artwork = nil; appTrack = ""
        status = reason
    }

    /// Spotify gives an image URL; Music hands over the image itself.
    private func loadAppArtwork(for key: String) {
        if source == .spotify {
            guard let link = run("tell application id \"com.spotify.client\" to return artwork url of current track")?.stringValue,
                  let url = URL(string: link) else { return }
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url), appTrack == key else { return }
                artwork = NSImage(data: data)
            }
        } else if let data = run("tell application id \"com.apple.Music\" to return data of artwork 1 of current track")?.data {
            artwork = NSImage(data: data)
        }
    }

    private func tellApp(_ command: String) {
        guard let bundle = source.bundleID else { return }
        _ = run("tell application id \"\(bundle)\" to \(command)")
        // The app also posts a change notification, but not for every command.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.refreshFromApp() }
    }

    /// Runs on the main thread, which NSAppleScript requires; the timeout keeps a stuck app
    /// from freezing the notch for long.
    private func run(_ source: String) -> NSAppleEventDescriptor? {
        let text = "with timeout of 2 seconds\n\(source)\nend timeout"
        guard let script = scripts[text] ?? NSAppleScript(source: text) else { return nil }
        scripts[text] = script
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard let error else { return result }
        // -1743: the user hasn't allowed NotchLab to control the app.
        if error[NSAppleScript.errorNumber] as? Int == -1743 {
            showNothing("Allow it in Privacy & Security › Automation")
        }
        return nil
    }
}

/// Calls back when Spotify or Music changes track or state, launches, or quits.
private final class AppWatcher: NSObject {
    private let changed: @MainActor () -> Void
    private var workspaceObservers: [NSObjectProtocol] = []

    init(changed: @escaping @MainActor () -> Void) {
        self.changed = changed
        super.init()
        // An inactive app gets distributed notifications late unless it asks for them right away.
        for name in MediaSource.allCases.compactMap(\.notification) {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(notify), name: Notification.Name(name),
                                                                object: nil, suspensionBehavior: .deliverImmediately)
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let bundle = app?.bundleIdentifier, MediaSource.allCases.contains(where: { $0.bundleID == bundle }) else { return }
                self?.notify()
            })
        }
    }

    @objc private func notify() {
        DispatchQueue.main.async { [changed] in
            MainActor.assumeIsolated { changed() }
        }
    }
}

struct NowPlayingUpdate: Sendable {
    var empty = false
    var error = false
    var title = "", artist = ""
    var duration: Double = 0, elapsed: Double = 0, rate: Double = 0
    var timestamp = Date()
    var playing = false
    var bundle: String?
    var artwork: Data?
    var noArtwork = false

    init?(json: [String: Any]) {
        if json["error"] != nil { error = true; return }
        if json["empty"] != nil { empty = true; return }
        guard let title = json["title"] as? String else { return nil }
        self.title = title
        artist = json["artist"] as? String ?? ""
        duration = (json["duration"] as? NSNumber)?.doubleValue ?? 0
        elapsed = (json["elapsed"] as? NSNumber)?.doubleValue ?? 0
        rate = (json["rate"] as? NSNumber)?.doubleValue ?? 0
        if let seconds = (json["timestamp"] as? NSNumber)?.doubleValue { timestamp = Date(timeIntervalSince1970: seconds) }
        playing = (json["playing"] as? NSNumber)?.boolValue ?? false
        bundle = json["bundle"] as? String
        if let encoded = json["artwork"] as? String { artwork = Data(base64Encoded: encoded) }
        noArtwork = json["noArtwork"] != nil
    }
}

/// Splits the bridge's stdout into JSON lines. Only touched from the pipe's handler queue.
private final class LineReader: @unchecked Sendable {
    private var buffer = Data()

    func feed(_ data: Data) -> [NowPlayingUpdate] {
        buffer.append(data)
        var updates: [NowPlayingUpdate] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
               let update = NowPlayingUpdate(json: json) {
                updates.append(update)
            }
        }
        return updates
    }
}
