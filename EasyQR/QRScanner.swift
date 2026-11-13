import AVFoundation
import SwiftUI

/// Owns the capture session. Reports the first QR code seen after `start()` and then ignores
/// further detections until restarted.
final class QRScanner: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()
    var onResult: ((String) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.fc.easyqr.capture")
    private var isConfigured = false
    // Main-thread only. Guards against several buffered detections delivering the same code.
    private var resultConsumed = true

    /// Returns false when no usable back camera is available.
    func start() -> Bool {
        guard configureIfNeeded() else { return false }
        resultConsumed = false
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
        return true
    }

    func stop() {
        resultConsumed = true
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureIfNeeded() -> Bool {
        if isConfigured { return true }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else { return false }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let output = AVCaptureMetadataOutput()
        guard session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input)
        session.addOutput(output)
        guard output.availableMetadataObjectTypes.contains(.qr) else {
            session.removeInput(input)
            session.removeOutput(output)
            return false
        }
        output.metadataObjectTypes = [.qr]
        output.setMetadataObjectsDelegate(self, queue: .main)

        isConfigured = true
        return true
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !resultConsumed,
              let code = metadataObjects.lazy
                  .compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue })
                  .first
        else { return }
        resultConsumed = true
        onResult?(code)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        // Keeps the preview upright when an iPad rotates (iPhone is portrait-only).
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let connection = previewLayer.connection, connection.isVideoOrientationSupported,
                  let orientation = window?.windowScene?.interfaceOrientation else { return }
            switch orientation {
            case .landscapeLeft: connection.videoOrientation = .landscapeLeft
            case .landscapeRight: connection.videoOrientation = .landscapeRight
            case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
            default: connection.videoOrientation = .portrait
            }
        }
    }
}
