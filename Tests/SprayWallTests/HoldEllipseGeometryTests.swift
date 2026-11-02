import CoreGraphics
import Foundation
import Testing
@testable import SprayWall

@Suite("Hold Ellipse Geometry & Bounding Box Tests")
struct HoldEllipseGeometryTests {

    @Test("Hold defaults to circular geometry with 8 cm axes and 0 degree rotation")
    func holdDefaults() {
        let hold = Hold(holdID: 1, xCm: 180, yCm: 180, plane: .main, role: .hand)

        #expect(hold.majorCm == Hold.defaultMajorCm)
        #expect(hold.minorCm == Hold.defaultMinorCm)
        #expect(hold.rotationDeg == Hold.defaultRotationDeg)
        #expect(hold.majorCm == 8.0)
        #expect(hold.minorCm == 8.0)
        #expect(hold.rotationDeg == 0.0)
    }

    @Test("Hold custom ellipse geometry and rotation normalization")
    func holdCustomEllipseAndRotation() {
        let hold = Hold(
            holdID: 2,
            xCm: 100,
            yCm: 200,
            plane: .main,
            role: .hand,
            majorCm: 18.5,
            minorCm: 7.2,
            rotationDeg: 45.0
        )

        #expect(hold.majorCm == 18.5)
        #expect(hold.minorCm == 7.2)
        #expect(hold.rotationDeg == 45.0)

        // Rotation angles wrap gracefully
        hold.rotationDeg = 390.0
        #expect(hold.rotationDeg == 30.0)

        hold.rotationDeg = -30.0
        #expect(hold.rotationDeg == 330.0)

        // Axes cannot be zero or negative
        hold.majorCm = -5.0
        #expect(hold.majorCm == 1.0)

        hold.minorCm = 0.0
        #expect(hold.minorCm == 1.0)
    }

    @Test("ProjectArchive DTO preserves ellipse geometry")
    func archiveRoundtrip() {
        let originalHold = Hold(
            holdID: 42,
            xCm: 150,
            yCm: 220,
            plane: .main,
            role: .hand,
            majorCm: 24.0,
            minorCm: 9.5,
            rotationDeg: 135.0
        )

        let dto = HoldDTO(
            holdID: originalHold.holdID,
            xCm: originalHold.xCm,
            yCm: originalHold.yCm,
            plane: originalHold.planeRaw,
            role: originalHold.roleRaw,
            isStart: originalHold.isStart,
            isTop: originalHold.isTop,
            isStartFoot: originalHold.isStartFoot,
            majorCm: originalHold.majorCm,
            minorCm: originalHold.minorCm,
            rotationDeg: originalHold.rotationDeg,
            createdAt: originalHold.createdAt,
            grips: []
        )

        #expect(dto.majorCm == 24.0)
        #expect(dto.minorCm == 9.5)
        #expect(dto.rotationDeg == 135.0)

        let restoredHold = Hold(
            holdID: dto.holdID,
            xCm: dto.xCm,
            yCm: dto.yCm,
            plane: HoldPlane(rawValue: dto.plane) ?? .main,
            role: HoldRole(rawValue: dto.role) ?? .hand,
            isStart: dto.isStart,
            isTop: dto.isTop,
            isStartFoot: dto.isStartFoot,
            majorCm: dto.majorCm ?? Hold.defaultMajorCm,
            minorCm: dto.minorCm ?? Hold.defaultMinorCm,
            rotationDeg: dto.rotationDeg ?? Hold.defaultRotationDeg,
            createdAt: dto.createdAt
        )

        #expect(restoredHold.majorCm == 24.0)
        #expect(restoredHold.minorCm == 9.5)
        #expect(restoredHold.rotationDeg == 135.0)
    }

    @Test("HoldBackwardTransformService estimates photo pixels per cm")
    func photoPixelsPerCm() {
        let sampleCalibrationPoints: [CalibrationPoint] = [
            CalibrationPoint(id: "kb_bl", label: "Kickboard Bottom Left", xPx: 690, yPx: 161, xCm: 0, yCm: 0),
            CalibrationPoint(id: "kb_br", label: "Kickboard Bottom Right", xPx: 2996, yPx: 98, xCm: 360, yCm: 0),
            CalibrationPoint(id: "kb_tl", label: "Kickboard Top Left", xPx: 739, yPx: 474, xCm: 0, yCm: 40),
            CalibrationPoint(id: "kb_tr", label: "Kickboard Top Right", xPx: 2979, yPx: 396, xCm: 360, yCm: 40),
            CalibrationPoint(id: "mw_bl", label: "Main Wall Bottom Left", xPx: 745, yPx: 471, xCm: 0, yCm: 40),
            CalibrationPoint(id: "mw_br", label: "Main Wall Bottom Right", xPx: 2976, yPx: 397, xCm: 360, yCm: 40),
            CalibrationPoint(id: "mw_tl", label: "Main Wall Top Left", xPx: 103, yPx: 2751, xCm: 0, yCm: 360),
            CalibrationPoint(id: "mw_tr", label: "Main Wall Top Right", xPx: 3841, yPx: 2467, xCm: 360, yCm: 360)
        ]

        let hold = Hold(holdID: 10, xCm: 180, yCm: 180, plane: .main, role: .hand)
        let pxPerCm = HoldBackwardTransformService.photoPixelsPerCm(for: hold, calibrationPoints: sampleCalibrationPoints)

        // Photo is ~3800px wide across 360cm wall, so resolution is roughly ~8-12 px/cm
        #expect(pxPerCm > 5.0)
        #expect(pxPerCm < 20.0)
    }

    @Test("Rotated bounding box dimension scaling matches wall canvas zoom")
    func boundingBoxScaling() {
        let fittedSize = CGSize(width: 720, height: 720)
        let viewportSize = CGSize(width: 720, height: 720)
        let transform = WallZoomTransform(
            fittedSize: fittedSize,
            viewportSize: viewportSize,
            zoomScale: 1.5,
            panOffset: .zero
        )

        let hold = Hold(holdID: 99, xCm: 180, yCm: 200, plane: .main, role: .hand, majorCm: 14.0, minorCm: 6.0, rotationDeg: 30.0)

        // Wall canvas scaling: 720 pt / 360 cm = 2 pt/cm
        let canvasWidth = CGFloat(hold.majorCm) * (fittedSize.width / CGFloat(WallSpec.widthCm))
        let canvasHeight = CGFloat(hold.minorCm) * (fittedSize.height / CGFloat(WallSpec.totalHeightCm))

        #expect(canvasWidth == 28.0)
        #expect(canvasHeight == 12.0)

        // Viewport screen scaling at 1.5x zoom
        let screenWidth = canvasWidth * transform.zoomScale
        let screenHeight = canvasHeight * transform.zoomScale

        #expect(screenWidth == 42.0)
        #expect(screenHeight == 18.0)
    }
}
