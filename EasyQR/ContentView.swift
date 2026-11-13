import AVFoundation
import PhotosUI
import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = QRScanner()
    /// Both the scan output and the generate input.
    @State private var text = ""
    @State private var isScanning = false
    @State private var qrImages: [CGImage] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var showPermissionAlert = false
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @FocusState private var editorFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.mainBackground.ignoresSafeArea()

            VStack(spacing: 16) {
                scanArea
                textArea
                buttonArea
            }
            .padding(16)

            if !qrImages.isEmpty {
                QRDisplayDialog(images: qrImages, onSave: saveQRCodes, onClose: { qrImages = [] })
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) { toastView }
        .animation(.easeInOut(duration: 0.2), value: qrImages.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: toast)
        .alert("permission_camera_rationale", isPresented: $showPermissionAlert) {
            Button("ok") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("cancel", role: .cancel) {}
        }
        .onAppear {
            scanner.onResult = { code in
                text += code
                stopScanning()
            }
        }
        .onChange(of: text) { _ in
            // Typing takes over from scanning.
            if editorFocused { stopScanning() }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { stopScanning() }
        }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            pickerItem = nil
            scanImage(from: item)
        }
    }

    // MARK: - Sections

    private var scanArea: some View {
        ZStack {
            if isScanning {
                CameraPreview(session: scanner.session)
            } else {
                Color.scanPlaceholder
                Text("scan_notification")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { editorFocused = false }
        .overlay(alignment: .bottomTrailing) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                CircleIcon(systemName: "photo")
            }
            .accessibilityLabel(Text("from_gallery"))
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }

    private var textArea: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("text_hint")
                    .font(.system(size: 16))
                    .foregroundColor(Color(white: 0.46))
                    .padding(16)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(size: 16))
                .foregroundColor(.textColor)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .focused($editorFocused)
                // TextEditor insets its text by about 5pt x 8pt; bring it to 16pt overall.
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.textAreaBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.stroke, lineWidth: 1))
    }

    private var buttonArea: some View {
        HStack(spacing: 0) {
            ActionButton(title: "make", systemName: "qrcode", action: generateQRCode)
            ActionButton(title: "clear", systemName: "xmark") { text = "" }
            ActionButton(title: "copy", systemName: "doc.on.doc", action: copyToClipboard)
            ActionButton(title: "scan", systemName: "qrcode.viewfinder", action: toggleScanning)
        }
    }

    @ViewBuilder private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(white: 0.2).opacity(0.95), in: Capsule())
                .padding(.horizontal, 32)
                .padding(.bottom, 110)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Scanning

    private func toggleScanning() {
        editorFocused = false
        if isScanning {
            stopScanning()
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startScanning()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { startScanning() } else { showPermissionAlert = true }
                }
            }
        default:
            showPermissionAlert = true
        }
    }

    private func startScanning() {
        if scanner.start() {
            isScanning = true
        } else {
            showToast("error_scanning_qr")
        }
    }

    private func stopScanning() {
        guard isScanning else { return }
        scanner.stop()
        isScanning = false
    }

    private func scanImage(from item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                showToast("error_scanning_qr")
                return
            }
            let result = await Task.detached { Result { try QRCodec.decode(imageData: data) } }.value
            switch result {
            case .success(let code?): text += code
            case .success(nil): showToast("no_qr_detected")
            case .failure: showToast("error_scanning_qr")
            }
        }
    }

    // MARK: - Generating

    private func generateQRCode() {
        editorFocused = false
        let images = QRCodec.makeQRImages(for: text)
        if images.isEmpty {
            showToast("error_creating_qr")
        } else {
            qrImages = images
        }
    }

    private func saveQRCodes() {
        let images = qrImages
        qrImages = []
        PhotoSaver.save(images) { success in
            showToast(success ? "qr_saved" : "error_saving_qr")
        }
    }

    private func copyToClipboard() {
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        showToast("copied")
    }

    private func showToast(_ key: String.LocalizationValue) {
        toastTask?.cancel()
        toast = String(localized: key)
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }
}

// MARK: - Components

private struct CircleIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 22, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 56, height: 56)
            .background(Color.accentColor, in: Circle())
    }
}

private struct ActionButton: View {
    let title: LocalizedStringKey
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                CircleIcon(systemName: systemName)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Palette (light / dark values carried over from the Android resources)

extension Color {
    static let mainBackground = Color(light: 0xF5F5F5, dark: 0x333333)
    static let textAreaBackground = Color(light: 0xF0F0F0, dark: 0x424242)
    static let textColor = Color(light: 0x000000, dark: 0xE0E0E0)
    static let stroke = Color(light: 0xDDDDDD, dark: 0x666666)
    static let scanPlaceholder = Color(light: 0x7F7F7F, dark: 0x1C1C1C)
    static let dialogBackground = Color(light: 0xF5F5F5, dark: 0x424242)

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

#Preview {
    ContentView()
}
