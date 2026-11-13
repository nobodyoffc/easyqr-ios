import Photos
import SwiftUI

/// Centered dialog paging through the generated QR codes, with Save and OK actions.
struct QRDisplayDialog: View {
    let images: [CGImage]
    let onSave: () -> Void
    let onClose: () -> Void

    @State private var page = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 8) {
                TabView(selection: $page) {
                    ForEach(images.indices, id: \.self) { index in
                        Image(decorative: images[index], scale: 1)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                            .tag(index)
                            .accessibilityLabel(Text("qr_code"))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .aspectRatio(1, contentMode: .fit)

                if images.count > 1 {
                    Text(verbatim: "\(page + 1)/\(images.count)")
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                }

                HStack {
                    Button("save", action: onSave)
                    Spacer()
                    Button("ok", action: onClose)
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.top, 8)
            }
            .padding(16)
            .background(Color.dialogBackground, in: RoundedRectangle(cornerRadius: 28))
            .padding(.horizontal, 28)
            .frame(maxWidth: 480)
        }
    }
}

enum PhotoSaver {
    /// Saves the images to the photo library as PNG. `completion` runs on the main queue.
    static func save(_ images: [CGImage], completion: @escaping (Bool) -> Void) {
        let pngs = images.compactMap { UIImage(cgImage: $0).pngData() }
        guard !pngs.isEmpty, pngs.count == images.count else {
            completion(false)
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                for png in pngs {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: nil)
                }
            } completionHandler: { success, _ in
                DispatchQueue.main.async { completion(success) }
            }
        }
    }
}
