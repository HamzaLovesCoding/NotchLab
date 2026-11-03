@preconcurrency import AVFoundation
import Observation
import SwiftUI

/// Front camera preview. The session only runs while the mirror tile is on screen, and
/// closing the notch or clicking the tile turns the mirror off, so the camera (and its green
/// light) never stays on in the background.
@Observable
@MainActor
final class Mirror {
    var isOn = false
    private(set) var isRunning = false
    private(set) var message: String?

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private var configured = false
    @ObservationIgnored private let queue = DispatchQueue(label: "notch.mirror")

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted { self.run() } else { self.message = "Camera access denied" }
                }
            }
        default:
            message = "Allow camera in System Settings › Privacy"
        }
    }

    func stop() {
        let session = session
        isRunning = false
        queue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    private func run() {
        let session = session
        let needsConfiguration = !configured
        configured = true
        message = nil
        queue.async { [weak self] in
            if needsConfiguration {
                session.beginConfiguration()
                session.sessionPreset = .vga640x480
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                    ?? AVCaptureDevice.default(for: .video)
                if let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                    session.addInput(input)
                }
                session.commitConfiguration()
            }
            guard !session.inputs.isEmpty else {
                DispatchQueue.main.async { self?.message = "No camera found" }
                return
            }
            if !session.isRunning { session.startRunning() }
            DispatchQueue.main.async { self?.isRunning = true }
        }
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let running: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        // The connection only exists once the session has an input, so mirror it here.
        guard running, let connection = (view.layer as? AVCaptureVideoPreviewLayer)?.connection,
              connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
}
