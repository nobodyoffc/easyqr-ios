import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

/// QR encoding/decoding. Deliberately free of UIKit so it can be exercised from a plain Swift script.
enum QRCodec {
    /// Maximum UTF-8 bytes carried by a single QR code; longer content is split across several codes.
    static let maxBytesPerCode = 400

    private static let context = CIContext()

    // MARK: - Generation

    /// One QR image per chunk. Chunks carry no sequencing header: reassembly relies on scanning them in order.
    static func makeQRImages(for content: String) -> [CGImage] {
        guard !content.isEmpty else { return [] }
        let chunks = content.utf8.count > maxBytesPerCode ? split(content) : [content]
        let images = chunks.compactMap(makeQRImage)
        return images.count == chunks.count ? images : []
    }

    /// Splits on Unicode scalar boundaries so that no chunk exceeds `maxBytes` of UTF-8.
    static func split(_ content: String, maxBytes: Int = maxBytesPerCode) -> [String] {
        var chunks: [String] = []
        var current = String.UnicodeScalarView()
        var currentBytes = 0
        for scalar in content.unicodeScalars {
            let size = UTF8.width(scalar)
            if currentBytes + size > maxBytes, !current.isEmpty {
                chunks.append(String(current))
                current.removeAll()
                currentBytes = 0
            }
            current.append(scalar)
            currentBytes += size
        }
        if !current.isEmpty {
            chunks.append(String(current))
        }
        return chunks
    }

    /// UTF-8 payload, error correction M, 2-module quiet zone, rendered with crisp module edges.
    static func makeQRImage(_ text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        // The generator emits one pixel per module, including a 1-module quiet zone.
        let modules = Int(output.extent.width)
        let scale = max(1, 1024 / (modules + 2))
        let side = CGFloat((modules + 2) * scale)
        let canvas = CGRect(x: 0, y: 0, width: side, height: side)

        let code = output
            .samplingNearest()
            .transformed(by: CGAffineTransform(translationX: -output.extent.minX, y: -output.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
            .transformed(by: CGAffineTransform(translationX: CGFloat(scale), y: CGFloat(scale)))
        let background = CIImage(color: .white).cropped(to: canvas)
        return context.createCGImage(code.composited(over: background), from: canvas)
    }

    // MARK: - Decoding

    enum DecodeError: Error {
        case unreadableImage
    }

    /// Returns the payload of the first QR code in the image, or nil when the image contains none.
    static func decode(imageData: Data) throws -> String? {
        guard let image = CIImage(data: imageData, options: [.applyOrientationProperty: true]) else {
            throw DecodeError.unreadableImage
        }
        return decode(image: image)
    }

    static func decode(image: CIImage) -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try? VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
        if let payload = request.results?.compactMap(\.payloadStringValue).first {
            return payload
        }

        // Vision can be unavailable (e.g. some simulators); CoreImage's detector covers that case.
        let detector = CIDetector(ofType: CIDetectorTypeQRCode,
                                  context: context,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: image) ?? []
        return features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
}
