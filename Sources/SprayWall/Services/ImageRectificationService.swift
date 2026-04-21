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
    case invalidWorldMapping(String)
    case invalidImage(URL)
    case filterFailure(String)
    case renderFailure(String)
    case writeFailure(URL)

    var errorDescription: String? {
        switch self {
        case let .missingPoint(id):
            return "Missing calibration point: \(id)"
        case let .invalidWorldMapping(message):
            return "Invalid world coordinate mapping: \(message)"
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
    private typealias Quad = (
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomLeft: CGPoint,
        bottomRight: CGPoint
    )

    private struct RectificationPair {
        var image: CGPoint
        var world: CGPoint
    }

    private struct RectificationMapping {
        var quad: Quad
        var targetSize: CGSize
    }

    static func rectify(
        photoURL: URL,
        points: [CalibrationPoint],
        outputDirectory: URL
    ) throws -> RectificationOutput {
        let inputImage = try loadImage(at: photoURL)

        let pointLookup = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })

        let kickboardMapping = try mapping(
            from: pairs(
                ids: ["kb_tl", "kb_tr", "kb_bl", "kb_br"],
                from: pointLookup
            ),
            label: "kickboard"
        )

        let mainWallMapping = try mapping(
            from: pairs(
                ids: ["mw_tl", "mw_tr", "mw_bl", "mw_br"],
                from: pointLookup
            ),
            label: "main wall"
        )

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let context = CIContext(options: [.cacheIntermediates: false])

        let mainWallCorrected = try perspectiveCorrected(inputImage: inputImage, quad: mainWallMapping.quad)
        let kickboardCorrected = try perspectiveCorrected(inputImage: inputImage, quad: kickboardMapping.quad)

        let mainWallURL = outputDirectory.appendingPathComponent("main_wall_rectified.png")
        let kickboardURL = outputDirectory.appendingPathComponent("kickboard_rectified.png")
        let photoOriginalURL = outputDirectory.appendingPathComponent("photo_original.jpg")

        try copyOriginalPhoto(photoURL: photoURL, destinationURL: photoOriginalURL)

        let mainWallImage = try renderAndResize(
            image: mainWallCorrected,
            targetSize: mainWallMapping.targetSize,
            context: context,
            label: "main wall"
        )

        let kickboardImage = try renderAndResize(
            image: kickboardCorrected,
            targetSize: kickboardMapping.targetSize,
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

    private static func pairs(
        ids: [String],
        from lookup: [String: CalibrationPoint]
    ) throws -> [RectificationPair] {
        try ids.map { id in
            try pair(id: id, from: lookup)
        }
    }

    private static func pair(
        id: String,
        from lookup: [String: CalibrationPoint]
    ) throws -> RectificationPair {
        guard let point = lookup[id] else {
            throw ImageRectificationError.missingPoint(id)
        }

        return RectificationPair(
            image: CGPoint(x: point.xPx, y: point.yPx),
            world: CGPoint(x: point.xCm, y: point.yCm)
        )
    }

    private static func mapping(from pairs: [RectificationPair], label: String) throws -> RectificationMapping {
        guard pairs.count == 4 else {
            throw ImageRectificationError.invalidWorldMapping("Expected 4 points for \(label)")
        }

        let worldX = pairs.map(\.world.x)
        let worldY = pairs.map(\.world.y)

        guard let minX = worldX.min(),
              let maxX = worldX.max(),
              let minY = worldY.min(),
              let maxY = worldY.max()
        else {
            throw ImageRectificationError.invalidWorldMapping("Missing world coordinates for \(label)")
        }

        let widthCm = maxX - minX
        let heightCm = maxY - minY
        guard widthCm > 0, heightCm > 0 else {
            throw ImageRectificationError.invalidWorldMapping("Non-positive world area for \(label)")
        }

        var remaining = pairs
        let topLeft = try popClosestPair(to: CGPoint(x: minX, y: maxY), from: &remaining, label: label)
        let topRight = try popClosestPair(to: CGPoint(x: maxX, y: maxY), from: &remaining, label: label)
        let bottomLeft = try popClosestPair(to: CGPoint(x: minX, y: minY), from: &remaining, label: label)
        let bottomRight = try popClosestPair(to: CGPoint(x: maxX, y: minY), from: &remaining, label: label)

        return RectificationMapping(
            quad: (
                topLeft: topLeft.image,
                topRight: topRight.image,
                bottomLeft: bottomLeft.image,
                bottomRight: bottomRight.image
            ),
            targetSize: CGSize(
                width: widthCm * WallSpec.rectifiedPixelsPerCm,
                height: heightCm * WallSpec.rectifiedPixelsPerCm
            )
        )
    }

    private static func popClosestPair(
        to target: CGPoint,
        from pairs: inout [RectificationPair],
        label: String
    ) throws -> RectificationPair {
        guard let closestIndex = pairs.indices.min(by: { left, right in
            squaredDistance(from: pairs[left].world, to: target) < squaredDistance(from: pairs[right].world, to: target)
        }) else {
            throw ImageRectificationError.invalidWorldMapping("Could not resolve corners for \(label)")
        }

        return pairs.remove(at: closestIndex)
    }

    private static func squaredDistance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }

    private static func perspectiveCorrected(
        inputImage: CIImage,
        quad: Quad
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
