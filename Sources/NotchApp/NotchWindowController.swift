import AppKit
import SwiftUI

/// Owns the overlay panel and decides when the notch opens and closes.
///
/// The window is always sized for the largest panel, but it ignores mouse events except
/// while the pointer is over the visible notch/panel, so the menu bar and the windows under
/// the transparent area keep working. Hover is tracked with global + local event monitors
/// rather than tracking areas because the window is click-through most of the time.
@MainActor
final class NotchWindowController {
    let model = NotchModel()
    let panel = NotchPanel()
    let container = NotchContainerView(frame: .zero)
    /// Pointer position in screen coordinates; replaceable so hover logic can be tested.
    var mouseLocation: () -> NSPoint = { NSEvent.mouseLocation }
    private var monitors: [Any] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var hoverWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var notchRect: NSRect = .zero
    private var dragPasteboardCount = NSPasteboard(name: .drag).changeCount
    private var fileDragActive = false

    init() {
        let hosting = NotchHostingView(rootView: NotchRootView(model: model))
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        container.controller = self
        panel.contentView = container
        panel.onEscape = { [weak self] in
            guard let self, !self.model.dismissOverlay() else { return }
            self.collapse()
        }

        layoutWindow()
        hosting.frame = container.bounds
        panel.orderFrontRegardless()

        installMonitors()
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { $0.screensChanged() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification) { $0.panel.orderFrontRegardless() }
        observe(NotificationCenter.default, NSWindow.didResignKeyNotification, object: panel) { controller in
            if !controller.expandedRect.contains(controller.mouseLocation()) { controller.collapse() }
        }
        model.nowPlaying.start()
        model.clipboard.start()
        model.agents.start()
        model.usage.start()
        model.meetings.start()
    }

    func shutdown() {
        model.nowPlaying.stop()
        model.mirror.stop()
    }

    // MARK: Geometry

    private static func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func layoutWindow() {
        guard let screen = Self.notchScreen() else { return }
        let frame = screen.frame
        let size: CGSize
        let minX: CGFloat
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            size = CGSize(width: frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
            minX = frame.minX + left.width
        } else {
            // No notch on this display: draw a pill the height of the menu bar.
            size = CGSize(width: 200, height: max(frame.maxY - screen.visibleFrame.maxY, 24))
            minX = frame.midX - 100
        }
        model.notchSize = size
        notchRect = NSRect(x: minX, y: frame.maxY - size.height, width: size.width, height: size.height)

        let windowSize = CGSize(width: model.maxPanelSize.width + 80, height: model.maxPanelSize.height + 40)
        panel.setFrame(NSRect(x: notchRect.midX - windowSize.width / 2, y: frame.maxY - windowSize.height,
                              width: windowSize.width, height: windowSize.height), display: true)
    }

    private func screensChanged() {
        collapse()
        layoutWindow()
    }

    /// Small overshoot above the screen edge so a pointer pinned to the top still counts.
    private var hoverRect: NSRect {
        NSRect(x: notchRect.minX, y: notchRect.minY, width: notchRect.width, height: notchRect.height + 4)
    }

    /// While a file is being dragged, the shelf opens anywhere across the open panel's width
    /// and down to 80 points below the notch, so the file only has to come near it.
    private var dragRect: NSRect {
        let width = max(model.settings.panelWidth, notchRect.width)
        return NSRect(x: notchRect.midX - width / 2, y: notchRect.minY - 80, width: width, height: notchRect.height + 84)
    }

    private var expandedRect: NSRect {
        let size = model.panelSize
        return NSRect(x: notchRect.midX - size.width / 2, y: notchRect.maxY - size.height,
                      width: size.width, height: size.height + 4)
    }

    // MARK: Pointer

    private func installMonitors() {
        let globalMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: globalMask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleGlobal(event) }
        }) { monitors.append(monitor) }

        let localMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: localMask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }) { monitors.append(monitor) }
    }

    private func handleGlobal(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragPasteboardCount = NSPasteboard(name: .drag).changeCount
            let point = self.mouseLocation()
            if model.isExpanded, !expandedRect.contains(point) { collapse() }
            if !model.isExpanded, model.settings.openOnClick, hoverRect.contains(point) { expand() }
        case .leftMouseDragged:
            if !fileDragActive {
                let pasteboard = NSPasteboard(name: .drag)
                if pasteboard.changeCount != dragPasteboardCount, Self.containsFiles(pasteboard) {
                    fileDragActive = true
                }
            }
            pointerMoved()
        case .leftMouseUp:
            endFileDrag()
            pointerMoved()
        default:
            pointerMoved()
        }
    }

    private static func containsFiles(_ pasteboard: NSPasteboard) -> Bool {
        guard let types = pasteboard.types else { return false }
        let promiseTypes = Set(NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        return types.contains(.fileURL) || types.contains { promiseTypes.contains($0) }
    }

    func pointerMoved() {
        let point = self.mouseLocation()
        if model.isExpanded {
            let inside = expandedRect.contains(point)
            setInteractive(inside)
            // A file dragged onto an open notch goes to the shelf, not into the note editor.
            if inside, fileDragActive, filesEnabled { expand(to: .shelf) }
            if inside {
                collapseWork?.cancel()
                collapseWork = nil
            } else if !isEditingText {
                scheduleCollapse()
            }
            return
        }

        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0
        // Recover if a drag ended without us seeing the mouse-up (e.g. cancelled with Esc).
        if fileDragActive, !buttonDown { endFileDrag() }
        if fileDragActive {
            if dragRect.contains(point), filesEnabled { expand(to: .shelf) }
            return
        }
        if hoverRect.contains(point), !buttonDown, !model.settings.openOnClick {
            guard hoverWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hoverWork = nil
                if self.hoverRect.contains(self.mouseLocation()) { self.expand() }
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + model.settings.openDelay, execute: work)
        } else {
            hoverWork?.cancel()
            hoverWork = nil
        }
    }

    private func scheduleCollapse() {
        guard collapseWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWork = nil
            if !self.expandedRect.contains(self.mouseLocation()), !self.isEditingText { self.collapse() }
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + model.settings.closeDelay, execute: work)
    }

    /// With the Files page hidden in Settings, dragged files don't open the notch.
    private var filesEnabled: Bool { model.visibleTabs.contains(.shelf) }

    /// Typing keeps the notch open even if the pointer drifts away. Only while a text field
    /// is focused, not merely while the panel holds focus after editing ended.
    private var isEditingText: Bool { panel.isKeyWindow && panel.firstResponder is NSText }

    private func setInteractive(_ interactive: Bool) {
        if panel.ignoresMouseEvents == interactive { panel.ignoresMouseEvents = !interactive }
    }

    func expand(to tab: NotchTab? = nil) {
        hoverWork?.cancel()
        hoverWork = nil
        if let tab {
            // The page asked for (the shelf, for a file drag) has to be visible, not under an overlay.
            if model.showSettings { model.showSettings = false }
            if model.showClipboard { model.showClipboard = false }
            if model.tab != tab { model.tab = tab }
        }
        // First open: show what can be connected, unless the notch opened for a drop or an agent.
        if !model.isExpanded, tab == nil, model.agents.requests.isEmpty, !model.settings.didShowSetup {
            model.settings.didShowSetup = true
            model.showSettings = true
            model.showWelcome = true
        }
        if !model.isExpanded { model.isExpanded = true }
        setInteractive(true)
    }

    func collapse() {
        collapseWork?.cancel()
        collapseWork = nil
        guard model.isExpanded else { return }
        model.isExpanded = false
        model.resetOverlays()
        // The camera turns off with the notch; reopening shows Home without it.
        model.mirror.isOn = false
        if let start = model.settings.startTab { model.tab = start }
        // Dev stays visible only while an agent waits; once that's answered, don't reopen to a hidden page.
        if !model.visibleTabs.contains(model.tab) { model.tab = .home }
        model.dropTarget = nil
        setInteractive(false)
        if panel.isKeyWindow {
            // A non-activating panel keeps keyboard focus until it leaves the screen; cycling
            // it hands focus back to the app the user was typing in. The panel is transparent
            // at this point apart from the notch itself, so nothing visibly flickers.
            panel.makeFirstResponder(nil)
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    // MARK: Drag and drop

    private func endFileDrag() {
        fileDragActive = false
        if model.dropTarget != nil { model.dropTarget = nil }
    }

    private func dropTarget(for info: NSDraggingInfo) -> DropTarget {
        let point = container.convert(info.draggingLocation, from: nil)
        let topLeft = CGPoint(x: point.x, y: container.bounds.height - point.y)
        return model.airDropFrame.contains(topLeft) ? .airDrop : .shelf
    }

    func dragUpdated(_ info: NSDraggingInfo) -> NSDragOperation {
        guard filesEnabled else { return [] }
        // Dragging a shelf item out passes over our own window; only AirDrop accepts it.
        let isInternal = info.draggingSource != nil
        let target = dropTarget(for: info)
        if isInternal, target == .shelf {
            dragExited()
            return []
        }
        fileDragActive = true
        expand(to: .shelf)
        if model.dropTarget != target { model.dropTarget = target }
        return .copy
    }

    func dragExited() {
        if model.dropTarget != nil { model.dropTarget = nil }
    }

    func dragEnded() {
        endFileDrag()
        pointerMoved()
    }

    func performDrop(_ info: NSDraggingInfo) -> Bool {
        let target = dropTarget(for: info)
        endFileDrag()
        if info.draggingSource != nil, target == .shelf { return false }
        let shelf = model.shelf
        let deliver: @MainActor ([URL]) -> Void = { urls in
            guard !urls.isEmpty else { return }
            switch target {
            case .shelf: shelf.add(urls)
            case .airDrop: AirDrop.send(urls)
            }
        }

        let pasteboard = info.draggingPasteboard
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            deliver(urls)
            return true
        }
        // Apps like Safari, Photos and Mail hand over promises instead of existing files.
        if let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
           !promises.isEmpty, let folder = Shelf.makeDropFolder() {
            for promise in promises {
                promise.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: Shelf.promiseQueue) { url, error in
                    guard error == nil else { return }
                    DispatchQueue.main.async { deliver([url]) }
                }
            }
            return true
        }
        return false
    }

    // MARK: Helpers

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, object: AnyObject? = nil,
                         _ handler: @escaping @MainActor (NotchWindowController) -> Void) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        observers.append((center, token))
    }
}

final class NotchPanel: NSPanel {
    var onEscape: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 8)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Borderless windows may sit over the menu bar; never let AppKit push us below it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    // Accessory apps have no Edit menu, so the standard editing shortcuts are routed by hand.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        var action: Selector?
        if flags == .command {
            switch key {
            case "x": action = #selector(NSText.cut(_:))
            case "c": action = #selector(NSText.copy(_:))
            case "v": action = #selector(NSText.paste(_:))
            case "a": action = #selector(NSText.selectAll(_:))
            case "z": action = Selector(("undo:"))
            default: break
            }
        } else if flags == [.command, .shift], key == "z" {
            action = Selector(("redo:"))
        }
        if let action, let responder = firstResponder, responder.tryToPerform(action, with: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Window content view: receives file drags and pointer movement for the whole window.
final class NotchContainerView: NSView {
    weak var controller: NotchWindowController?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        registerForDraggedTypes([.fileURL] + promiseTypes)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseMoved(with event: NSEvent) { controller?.pointerMoved() }
    override func mouseEntered(with event: NSEvent) { controller?.pointerMoved() }
    override func mouseExited(with event: NSEvent) { controller?.pointerMoved() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { controller?.dragUpdated(sender) ?? [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { controller?.dragUpdated(sender) ?? [] }
    override func draggingExited(_ sender: NSDraggingInfo?) { controller?.dragExited() }
    override func draggingEnded(_ sender: NSDraggingInfo) { controller?.dragEnded() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { controller?.performDrop(sender) ?? false }
}
