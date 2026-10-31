import CoreGraphics
import Foundation
import Testing
@testable import SprayWall

@Suite("Hold Backward Transform & Loupe Tests")
struct HoldBackwardTransformServiceTests {

    private let sampleCalibrationPoints: [CalibrationPoint] = [
        CalibrationPoint(id: "kb_bl", label: "Kickboard Bottom Left", xPx: 690, yPx: 161, xCm: 0, yCm: 0),
        CalibrationPoint(id: "kb_br", label: "Kickboard Bottom Right", xPx: 2996, yPx: 98, xCm: 360, yCm: 0),
        CalibrationPoint(id: "kb_tl", label: "Kickboard Top Left", xPx: 739, yPx: 474, xCm: 0, yCm: 40),
        CalibrationPoint(id: "kb_tr", label: "Kickboard Top Right", xPx: 2979, yPx: 396, xCm: 360, yCm: 40),
        CalibrationPoint(id: "mw_bl", label: "Main Wall Bottom Left", xPx: 745, yPx: 471, xCm: 0, yCm: 40),
        CalibrationPoint(id: "mw_br", label: "Main Wall Bottom Right", xPx: 2976, yPx: 397, xCm: 360, yCm: 40),
        CalibrationPoint(id: "mw_tl", label: "Main Wall Top Left", xPx: 103, yPx: 2751, xCm: 0, yCm: 360),
        CalibrationPoint(id: "mw_tr", label: "Main Wall Top Right", xPx: 3841, yPx: 2467, xCm: 360, yCm: 360)
    ]

    @Test("SquareToQuadMapping maps all 4 unit corners precisely")
    func squareToQuadCorners() {
        let p0 = HoldBackwardTransformService.Point2D(x: 100, y: 150)
        let p1 = HoldBackwardTransformService.Point2D(x: 900, y: 120)
        let p2 = HoldBackwardTransformService.Point2D(x: 850, y: 800)
        let p3 = HoldBackwardTransformService.Point2D(x: 150, y: 780)

        let mapping = HoldBackwardTransformService.SquareToQuadMapping(p0: p0, p1: p1, p2: p2, p3: p3)

        let res0 = mapping.transform(u: 0, v: 0)
        let res1 = mapping.transform(u: 1, v: 0)
        let res2 = mapping.transform(u: 1, v: 1)
        let res3 = mapping.transform(u: 0, v: 1)

        #expect(abs(res0.x - p0.x) < 0.001)
        #expect(abs(res0.y - p0.y) < 0.001)

        #expect(abs(res1.x - p1.x) < 0.001)
        #expect(abs(res1.y - p1.y) < 0.001)

        #expect(abs(res2.x - p2.x) < 0.001)
        #expect(abs(res2.y - p2.y) < 0.001)

        #expect(abs(res3.x - p3.x) < 0.001)
        #expect(abs(res3.y - p3.y) < 0.001)
    }

    @Test("Kickboard hold backward transform maps to kickboard photo coordinates")
    func kickboardHoldMapping() {
        // Test corner 1: Bottom Left (0, 0)
        let blHold = Hold(holdID: 1, xCm: 0, yCm: 0, plane: .kickboard, role: .hand)
        let blLoc = HoldBackwardTransformService.photoPixelLocation(for: blHold, calibrationPoints: sampleCalibrationPoints)
        #expect(blLoc != nil)
        #expect(abs((blLoc?.x ?? 0) - 690) < 0.1)
        #expect(abs((blLoc?.y ?? 0) - 161) < 0.1)

        // Test corner 2: Top Right (360, 40)
        let trHold = Hold(holdID: 2, xCm: 360, yCm: 40, plane: .kickboard, role: .hand)
        let trLoc = HoldBackwardTransformService.photoPixelLocation(for: trHold, calibrationPoints: sampleCalibrationPoints)
        #expect(trLoc != nil)
        #expect(abs((trLoc?.x ?? 0) - 2979) < 0.1)
        #expect(abs((trLoc?.y ?? 0) - 396) < 0.1)
    }

    @Test("Main wall hold backward transform maps to main wall photo coordinates")
    func mainWallHoldMapping() {
        // Test corner 1: Bottom Left (0, 40)
        let blHold = Hold(holdID: 10, xCm: 0, yCm: 40, plane: .main, role: .hand)
        let blLoc = HoldBackwardTransformService.photoPixelLocation(for: blHold, calibrationPoints: sampleCalibrationPoints)
        #expect(blLoc != nil)
        #expect(abs((blLoc?.x ?? 0) - 745) < 0.1)
        #expect(abs((blLoc?.y ?? 0) - 471) < 0.1)

        // Test corner 2: Top Right (360, 360)
        let trHold = Hold(holdID: 11, xCm: 360, yCm: 360, plane: .main, role: .hand)
        let trLoc = HoldBackwardTransformService.photoPixelLocation(for: trHold, calibrationPoints: sampleCalibrationPoints)
        #expect(trLoc != nil)
        #expect(abs((trLoc?.x ?? 0) - 3841) < 0.1)
        #expect(abs((trLoc?.y ?? 0) - 2467) < 0.1)

        // Test interior point: Center (180, 200)
        let centerHold = Hold(holdID: 12, xCm: 180, yCm: 200, plane: .main, role: .hand)
        let centerLoc = HoldBackwardTransformService.photoPixelLocation(for: centerHold, calibrationPoints: sampleCalibrationPoints)
        #expect(centerLoc != nil)
        // Center x should be roughly in the middle between left (745..103) and right (2976..3841)
        #expect((centerLoc?.x ?? 0) > 1500 && (centerLoc?.x ?? 0) < 2500)
        // Center y should be between bottom (471) and top (2751)
        #expect((centerLoc?.y ?? 0) > 1000 && (centerLoc?.y ?? 0) < 2000)
    }

    @Test("cropHold crops high-resolution sub-image of requested span")
    func cropHoldHighResolution() throws {
        // Create a synthetic 4000x3000 image
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: 4000,
            height: 3000,
            bitsPerComponent: 8,
            bytesPerRow: 4000 * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            Issue.record("Failed to create test graphics context")
            return
        }

        ctx.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))

        guard let testImage = ctx.makeImage() else {
            Issue.record("Failed to make CGImage")
            return
        }

        let hold = Hold(holdID: 25, xCm: 180, yCm: 200, plane: .main, role: .hand)
        let cropSpan: CGFloat = 320

        let cropped = HoldBackwardTransformService.cropHold(
            from: testImage,
            hold: hold,
            calibrationPoints: sampleCalibrationPoints,
            cropSpan: cropSpan
        )

        #expect(cropped != nil)
        #expect(cropped?.width == Int(cropSpan))
        #expect(cropped?.height == Int(cropSpan))
    }

    @Test("HoldLoupeConfig presets provide configurable shapes and dimensions")
    func loupeConfigPresets() {
        let defaultCircle = HoldLoupeConfig.defaultCircle
        #expect(defaultCircle.shape == .circle)
        #expect(defaultCircle.size.width == 190)

        let roundedCard = HoldLoupeConfig.roundedCard
        #expect(roundedCard.shape == .roundedRectangle)
        #expect(roundedCard.size.width == 210)
        #expect(roundedCard.cornerRadius == 16)
        #expect(roundedCard.isEnabled == true)

        var custom = HoldLoupeConfig()
        custom.shape = .roundedRectangle
        custom.size = CGSize(width: 250, height: 250)
        custom.cropPixelSpan = 500
        custom.isEnabled = false
        #expect(custom.shape == .roundedRectangle)
        #expect(custom.size.width == 250)
        #expect(custom.cropPixelSpan == 500)
        #expect(custom.isEnabled == false)
    }

    @Test("cropLocation crops arbitrary coordinate precisely")
    func cropLocationCoordinate() {
        let width = 4000
        let height = 3000
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ), let testImage = context.makeImage() else {
            Issue.record("Failed to create mock test image")
            return
        }

        let cropped = HoldBackwardTransformService.cropLocation(
            from: testImage,
            xCm: 180,
            yCm: 200,
            plane: .main,
            calibrationPoints: sampleCalibrationPoints,
            cropSpan: 240
        )

        #expect(cropped != nil)
        #expect(cropped?.width == 240)
        #expect(cropped?.height == 240)
    }
}

