import AppKit

@main
@MainActor
enum NotchApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        clearQuarantineFromHelpers()
        controller = NotchWindowController()
    }

    /// A downloaded copy carries macOS's quarantine flag, and the system then refuses to load
    /// the media bridge into perl or run the agent hook. The user has already approved the app
    /// by the time it launches, so clear the flag from the two helpers it runs outside itself.
    private func clearQuarantineFromHelpers() {
        let helpers = [Bundle.main.path(forResource: "libNotchMediaBridge", ofType: "dylib"),
                       Bundle.main.path(forAuxiliaryExecutable: "notch-hook")]
        for path in helpers.compactMap({ $0 }) {
            removexattr(path, "com.apple.quarantine", 0)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }
}
