import AppKit
import Observation
import QuickLookThumbnailing

struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
}

/// Files parked in the notch. Normal files are kept by reference, so adding even a huge
/// file is instant; only temporary files (screenshot thumbnails, promised drops) are copied.
@Observable
@MainActor
final class Shelf {
    private(set) var items: [ShelfItem] = []
    private(set) var thumbnails: [URL: NSImage] = [:]

    static let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    static let storageFolder: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("NotchApp/Shelf", isDirectory: true)
    }()

    private static let defaultsKey = "shelfPaths"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        items = paths.map { ShelfItem(url: URL(fileURLWithPath: $0)) }
        prune()
    }

    func add(_ urls: [URL]) {
        for url in urls {
            let stored = Self.isTemporary(url) ? (Self.copyToStorage(url) ?? url) : url
            let path = stored.standardizedFileURL.path
            guard !items.contains(where: { $0.url.standardizedFileURL.path == path }) else { continue }
            items.append(ShelfItem(url: stored))
        }
        save()
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        thumbnails[item.url] = nil
        if item.url.standardizedFileURL.path.hasPrefix(Self.storageFolder.path) {
            try? FileManager.default.removeItem(at: item.url)
        }
        save()
    }

    func clear() {
        items.forEach(remove)
    }

    /// Drops entries whose files were deleted or moved since they were added.
    func prune() {
        let existing = items.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        if existing.count != items.count {
            items = existing
            save()
        }
    }

    func loadThumbnail(for item: ShelfItem) async {
        guard thumbnails[item.url] == nil else { return }
        // Folders and bundles (apps) look best as their Finder icon; files get a content preview.
        let isDirectory = (try? item.url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if !isDirectory {
            let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 56, height: 56),
                                                       scale: 2, representationTypes: .thumbnail)
            if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                thumbnails[item.url] = representation.nsImage
                return
            }
        }
        thumbnails[item.url] = NSWorkspace.shared.icon(forFile: item.url.path)
    }

    func copyToPasteboard(_ item: ShelfItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item.url as NSURL])
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.url.path), forKey: Self.defaultsKey)
    }

    /// A fresh folder per drop so promised files with the same name never collide.
    static func makeDropFolder() -> URL? {
        let folder = storageFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        } catch {
            return nil
        }
    }

    private static func isTemporary(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        return path.hasPrefix("/private/var/folders/") || path.hasPrefix("/var/folders/")
            || path.hasPrefix("/private/tmp/") || path.hasPrefix("/tmp/")
    }

    private static func copyToStorage(_ url: URL) -> URL? {
        guard let folder = makeDropFolder() else { return nil }
        let destination = folder.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}

@MainActor
enum AirDrop {
    static var icon: NSImage {
        NSSharingService(named: .sendViaAirDrop)?.image
            ?? NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: "AirDrop")
            ?? NSImage()
    }

    static func send(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate()
        if service.canPerform(withItems: urls) { service.perform(withItems: urls) }
    }

    static func chooseAndSend() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "AirDrop"
        panel.message = "Choose files to send with AirDrop"
        NSApp.activate()
        panel.begin { response in
            guard response == .OK else { return }
            send(panel.urls)
        }
    }
}
