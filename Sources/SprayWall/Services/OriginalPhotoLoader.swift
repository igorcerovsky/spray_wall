import CoreGraphics
import Foundation
import ImageIO

/// Actor providing thread-safe, cached decoding of the high-resolution wall photo.
actor OriginalPhotoLoader {
    static let shared = OriginalPhotoLoader()

    private var cachedImage: CGImage?
    private var cachedPath: String?

    private init() {}

    /// Loads and decodes the original high-resolution photo for hold cropping.
    /// Returns the cached image if already loaded for the same path.
    func loadPhoto(from photoPath: String? = nil) -> CGImage? {
        let path = photoPath ?? WallCalibration.defaultPhotoPath
        if let cachedImage, cachedPath == path {
            return cachedImage
        }

        guard let url = try? WallProjectPaths.resolvePhotoURL(from: path) else {
            return nil
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        self.cachedImage = image
        self.cachedPath = path
        return image
    }
}
