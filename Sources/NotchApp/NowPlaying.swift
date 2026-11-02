import AppKit
import Observation

/// Now-playing state for whatever app owns the system media session (Music, Spotify,
/// browsers, ...). Data comes from MediaRemoteBridge.m running inside /usr/bin/perl.
@Observable
@MainActor
final class NowPlaying {
    private(set) var title = ""
    private(set) var artist = ""
    private(set) var duration: Double = 0
    private(set) var isPlaying = false
    private(set) var artwork: NSImage?
    private(set) var appIcon: NSImage?
    private(set) var appName = ""
    private(set) var bundleID: String?
    private(set) var bridgeFailed = false

    // Position is extrapolated from the last report instead of polled.
    private var elapsedAtTimestamp: Double = 0
    private var rate: Double = 0
    private var timestamp = Date()

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var input: FileHandle?
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var restartDelay: TimeInterval = 1

    var hasContent: Bool { !title.isEmpty }

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
        isPlaying.toggle()
        if !isPlaying { freezePosition() }
        send("toggle")
    }

    func next() { send("next") }
    func previous() { send("prev") }

    func seek(to seconds: Double) {
        elapsedAtTimestamp = seconds
        timestamp = Date()
        send("seek \(seconds)")
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
        restartDelay = 1
        if update.error {
            bridgeFailed = true
            return
        }
        guard !update.empty else {
            title = ""; artist = ""; duration = 0; isPlaying = false
            artwork = nil; appIcon = nil; appName = ""; bundleID = nil
            return
        }
        title = update.title
        artist = update.artist
        duration = update.duration
        isPlaying = update.playing
        rate = update.rate
        elapsedAtTimestamp = update.elapsed
        timestamp = update.timestamp
        if let artworkData = update.artwork {
            artwork = NSImage(data: artworkData)
        } else if update.noArtwork {
            artwork = nil
        }
        if update.bundle != bundleID {
            bundleID = update.bundle
            if let bundle = update.bundle, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                appIcon = NSWorkspace.shared.icon(forFile: url.path)
                appName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            } else {
                appIcon = nil
                appName = ""
            }
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
