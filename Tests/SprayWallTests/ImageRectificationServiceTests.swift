import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SprayWall

@Test("Rectification writes expected output dimensions")
func rectificationWritesExpectedSizes() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("spraywall-rectification-\(UUID().uuidString)", isDirectory: true)
    let outputDirectory = root.appendingPathComponent("wall_project", isDirectory: true)
    let inputPhotoURL = root.appendingPathComponent("photo.png")

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try makeSyntheticImage(at: inputPhotoURL, size: CGSize(width: 1200, height: 900))

    let points: [CalibrationPoint] = [
        CalibrationPoint(id: "kb_bl", label: "", xPx: 110, yPx: 790),
        CalibrationPoint(id: "kb_br", label: "", xPx: 1090, yPx: 780),
        CalibrationPoint(id: "kb_tl", label: "", xPx: 130, yPx: 700),
        CalibrationPoint(id: "kb_tr", label: "", xPx: 1070, yPx: 695),
        CalibrationPoint(id: "mw_bl", label: "", xPx: 130, yPx: 700),
        CalibrationPoint(id: "mw_br", label: "", xPx: 1070, yPx: 695),
        CalibrationPoint(id: "mw_tl", label: "", xPx: 260, yPx: 120),
        CalibrationPoint(id: "mw_tr", label: "", xPx: 900, yPx: 118)
    ]

    let output = try ImageRectificationService.rectify(
        photoURL: inputPhotoURL,
        points: points,
        outputDirectory: outputDirectory
    )

    let mainSize = try imageSize(at: output.mainWallURL)
    let kickboardSize = try imageSize(at: output.kickboardURL)

    #expect(mainSize.width == Int(WallSpec.widthCm * WallSpec.rectifiedPixelsPerCm))
    #expect(mainSize.height == Int(WallSpec.mainWallHeightCm * WallSpec.rectifiedPixelsPerCm))

    #expect(kickboardSize.width == Int(WallSpec.widthCm * WallSpec.rectifiedPixelsPerCm))
    #expect(kickboardSize.height == Int(WallSpec.kickboardHeightCm * WallSpec.rectifiedPixelsPerCm))
}

@Test("Rectification fails if calibration points are missing")
func rectificationRequiresAllPoints() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("spraywall-rectification-missing-\(UUID().uuidString)", isDirectory: true)
    let outputDirectory = root.appendingPathComponent("wall_project", isDirectory: true)
    let inputPhotoURL = root.appendingPathComponent("photo.png")

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try makeSyntheticImage(at: inputPhotoURL, size: CGSize(width: 1200, height: 900))

    let incompletePoints = CalibrationPointTemplates.all.filter { $0.id != "mw_tr" }

    #expect(throws: ImageRectificationError.self) {
        try ImageRectificationService.rectify(
            photoURL: inputPhotoURL,
            points: incompletePoints,
            outputDirectory: outputDirectory
        )
    }
}

private func makeSyntheticImage(at url: URL, size: CGSize) throws {
    let width = Int(size.width)
    let height = Int(size.height)

    guard width > 0, height > 0 else { return }

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
        throw NSError(domain: "RectificationTests", code: 1)
    }

    context.setFillColor(CGColor(red: 0.14, green: 0.16, blue: 0.21, alpha: 1.0))
    context.fill(CGRect(origin: .zero, size: size))

    context.setFillColor(CGColor(red: 0.83, green: 0.58, blue: 0.31, alpha: 1.0))
    context.fill(CGRect(x: 100, y: 100, width: 1000, height: 120))

    context.setFillColor(CGColor(red: 0.22, green: 0.48, blue: 0.82, alpha: 1.0))
    context.fill(CGRect(x: 250, y: 220, width: 700, height: 560))

    guard let image = context.makeImage() else {
        throw NSError(domain: "RectificationTests", code: 2)
    }

    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw NSError(domain: "RectificationTests", code: 3)
    }

    CGImageDestinationAddImage(destination, image, nil)

    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "RectificationTests", code: 4)
    }
}

private func imageSize(at url: URL) throws -> (width: Int, height: Int) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw NSError(domain: "RectificationTests", code: 5)
    }

    return (image.width, image.height)
}
