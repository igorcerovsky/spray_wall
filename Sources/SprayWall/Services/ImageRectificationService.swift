import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct RectificationOutput {
    let photoOriginalURL: URL
    let mainWallURL: URL
    let kickboardURL: URL
}

enum ImageRectificationError: Error, LocalizedError {
    case missingPoint(String)
    case invalidImage(URL)
    case filterFailure(String)
    case renderFailure(String)
    case writeFailure(URL)

    var errorDescription: String? {
        switch self {
        case let .missingPoint(id):
            return "Missing calibration point: \(id)"
        case let .invalidImage(url):
            return "Could not load image from: \(url.path)"
        case let .filterFailure(message):
            return "Perspective correction failed: \(message)"
        case let .renderFailure(message):
            return "Image rendering failed: \(message)"
        case let .writeFailure(url):
            return "Could not write image to: \(url.path)"
        }
    }
}

enum ImageRectificationService {
    static func rectify(
        photoURL: URL,
        points: [CalibrationPoint],
        outputDirectory: URL
    ) throws -> RectificationOutput {
        let inputImage = try loadImage(at: photoURL)
        let imageHeight = inputImage.extent.height

        let pointLookup = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })

        let kickboardQuad = try quad(
            topLeft: point(id: "kb_tl", from: pointLookup, imageHeight: imageHeight),
            topRight: point(id: "kb_tr", from: pointLookup, imageHeight: imageHeight),
            bottomLeft: point(id: "kb_bl", from: pointLookup, imageHeight: imageHeight),
            bottomRight: point(id: "kb_br", from: pointLookup, imageHeight: imageHeight)
        )

        let mainWallQuad = try quad(
            topLeft: point(id: "mw_tl", from: pointLookup, imageHeight: imageHeight),
            topRight: point(id: "mw_tr", from: pointLookup, imageHeight: imageHeight),
            bottomLeft: point(id: "mw_bl", from: pointLookup, imageHeight: imageHeight),
            bottomRight: point(id: "mw_br", from: pointLookup, imageHeight: imageHeight)
        )

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let context = CIContext(options: [.cacheIntermediates: false])

        let mainWallCorrected = try perspectiveCorrected(inputImage: inputImage, quad: mainWallQuad)
        let kickboardCorrected = try perspectiveCorrected(inputImage: inputImage, quad: kickboardQuad)

        let mainWallURL = outputDirectory.appendingPathComponent("main_wall_rectified.png")
        let kickboardURL = outputDirectory.appendingPathComponent("kickboard_rectified.png")
        let photoOriginalURL = outputDirectory.appendingPathComponent("photo_original.jpg")

        try copyOriginalPhoto(photoURL: photoURL, destinationURL: photoOriginalURL)

        let mainWallImage = try renderAndResize(
            image: mainWallCorrected,
            targetSize: CGSize(
                width: WallSpec.widthCm * WallSpec.rectifiedPixelsPerCm,
                height: WallSpec.mainWallHeightCm * WallSpec.rectifiedPixelsPerCm
            ),
            context: context,
            label: "main wall"
        )

        let kickboardImage = try renderAndResize(
            image: kickboardCorrected,
            targetSize: CGSize(
                width: WallSpec.widthCm * WallSpec.rectifiedPixelsPerCm,
                height: WallSpec.kickboardHeightCm * WallSpec.rectifiedPixelsPerCm
            ),
            context: context,
            label: "kickboard"
        )

        try writePNG(mainWallImage, to: mainWallURL)
        try writePNG(kickboardImage, to: kickboardURL)

        return RectificationOutput(
            photoOriginalURL: photoOriginalURL,
            mainWallURL: mainWallURL,
            kickboardURL: kickboardURL
        )
    }

    private static func loadImage(at url: URL) throws -> CIImage {
        let options: [CIImageOption: Any] = [.applyOrientationProperty: true]
        guard let image = CIImage(contentsOf: url, options: options) else {
            throw ImageRectificationError.invalidImage(url)
        }
        return image
    }

    private static func point(
        id: String,
        from lookup: [String: CalibrationPoint],
        imageHeight: CGFloat
    ) throws -> CGPoint {
        guard let point = lookup[id] else {
            throw ImageRectificationError.missingPoint(id)
        }

        return CGPoint(x: point.xPx, y: imageHeight - point.yPx)
    }

    private static func quad(
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomLeft: CGPoint,
        bottomRight: CGPoint
    ) throws -> (topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint) {
        (topLeft, topRight, bottomLeft, bottomRight)
    }

    private static func perspectiveCorrected(
        inputImage: CIImage,
        quad: (topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint)
    ) throws -> CIImage {
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            throw ImageRectificationError.filterFailure("CIPerspectiveCorrection unavailable")
        }

        filter.setValue(inputImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: quad.topLeft), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: quad.topRight), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: quad.bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: quad.bottomRight), forKey: "inputBottomRight")

        guard let output = filter.outputImage else {
            throw ImageRectificationError.filterFailure("No output image")
        }

        return output
    }

    private static func renderAndResize(
        image: CIImage,
        targetSize: CGSize,
        context: CIContext,
        label: String
    ) throws -> CGImage {
        guard let rawCGImage = context.createCGImage(image, from: image.extent) else {
            throw ImageRectificationError.renderFailure("Cannot create CGImage for \(label)")
        }

        guard let resized = resize(image: rawCGImage, to: targetSize) else {
            throw ImageRectificationError.renderFailure("Cannot resize \(label) image")
        }

        return resized
    }

    private static func resize(image: CGImage, to targetSize: CGSize) -> CGImage? {
        let width = Int(targetSize.width.rounded())
        let height = Int(targetSize.height.rounded())

        guard width > 0, height > 0 else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: CGSize(width: width, height: height)))
        return context.makeImage()
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageRectificationError.writeFailure(url)
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageRectificationError.writeFailure(url)
        }
    }

    private static func copyOriginalPhoto(photoURL: URL, destinationURL: URL) throws {
        let manager = FileManager.default

        if manager.fileExists(atPath: destinationURL.path) {
            try manager.removeItem(at: destinationURL)
        }

        try manager.copyItem(at: photoURL, to: destinationURL)
    }
}
