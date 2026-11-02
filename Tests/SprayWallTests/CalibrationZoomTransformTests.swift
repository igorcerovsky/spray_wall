import CoreGraphics
import Foundation
import Testing
@testable import SprayWall

@Suite("Calibration Zoom & Pan Transformation Matrix Tests")
struct CalibrationZoomTransformTests {

    private let sampleImageSize = CGSize(width: 4032, height: 3024)
    private let sampleViewport = CGSize(width: 1200, height: 900)

    private let testPoints: [CalibrationPoint] = [
        CalibrationPoint(id: "kb_bl", label: "Kickboard Bottom Left", xPx: 690, yPx: 161),
        CalibrationPoint(id: "kb_br", label: "Kickboard Bottom Right", xPx: 2996, yPx: 98),
        CalibrationPoint(id: "mw_tl", label: "Main Wall Top Left", xPx: 103, yPx: 2751),
        CalibrationPoint(id: "mw_tr", label: "Main Wall Top Right", xPx: 3841, yPx: 2467)
    ]

    @Test("Aspect ratio fitting preserves photo proportions")
    func aspectFitting() {
        let transform = CalibrationZoomTransform(
            imageSize: sampleImageSize,
            viewportSize: sampleViewport,
            zoomScale: 1.0,
            panOffset: .zero
        )

        let photoAspect = sampleImageSize.width / sampleImageSize.height
        let fittedAspect = transform.fittedSize.width / transform.fittedSize.height
        #expect(abs(photoAspect - fittedAspect) < 0.001)
        #expect(transform.fittedSize.width <= sampleViewport.width)
        #expect(transform.fittedSize.height <= sampleViewport.height)
    }

    @Test("Photo pixel to canvas and back roundtrips accurately")
    func photoPxToCanvasRoundtrip() {
        let transform = CalibrationZoomTransform(
            imageSize: sampleImageSize,
            viewportSize: sampleViewport,
            zoomScale: 1.0,
            panOffset: .zero
        )

        let originalX: Double = 1250.0
        let originalY: Double = 2100.0

        let canvasPt = transform.photoPxToCanvas(xPx: originalX, yPx: originalY)
        let roundtrip = transform.canvasToPhotoPx(canvasPt)

        #expect(abs(roundtrip.xPx - originalX) < 0.01)
        #expect(abs(roundtrip.yPx - originalY) < 0.01)
    }

    @Test("Viewport to photo pixel inverts zoom scale and pan shift perfectly")
    func viewportInversionUnderZoom() {
        let transform = CalibrationZoomTransform(
            imageSize: sampleImageSize,
            viewportSize: sampleViewport,
            zoomScale: 2.5,
            panOffset: CGSize(width: -80, height: 45)
        )

        for pt in testPoints {
            let screenPt = transform.photoPxToViewport(xPx: pt.xPx, yPx: pt.yPx)
            let inverted = transform.viewportToPhotoPx(screenPt)

            #expect(abs(inverted.xPx - pt.xPx) < 0.05)
            #expect(abs(inverted.yPx - pt.yPx) < 0.05)
        }
    }

    @Test("Spatial hit-testing finds closest point near cursor")
    func closestPointHitTesting() {
        let transform = CalibrationZoomTransform(
            imageSize: sampleImageSize,
            viewportSize: sampleViewport,
            zoomScale: 1.8,
            panOffset: CGSize(width: 30, height: -20)
        )

        let target = testPoints[2] // mw_tl
        let targetScreenPt = transform.photoPxToViewport(xPx: target.xPx, yPx: target.yPx)

        // Point near mw_tl screen position (within 10 pt)
        let nearCursor = CGPoint(x: targetScreenPt.x + 8, y: targetScreenPt.y - 6)
        let match = transform.closestPoint(near: nearCursor, in: testPoints, maxScreenDistance: 25.0)

        #expect(match != nil)
        #expect(match?.point.id == "mw_tl")
        #expect((match?.distance ?? 999) < 15.0)

        // Point far away
        let farCursor = CGPoint(x: targetScreenPt.x + 300, y: targetScreenPt.y + 300)
        let noMatch = transform.closestPoint(near: farCursor, in: testPoints, maxScreenDistance: 25.0)
        #expect(noMatch == nil)
    }

    @Test("CalibrationPointTemplates identifies joint kickboard and main wall common seam partners")
    func commonSeamPartners() {
        // Main wall bottom left + kickboard top left
        #expect(CalibrationPointTemplates.commonPartnerID(for: "mw_bl") == "kb_tl")
        #expect(CalibrationPointTemplates.commonPartnerID(for: "kb_tl") == "mw_bl")
        #expect(CalibrationPointTemplates.isCommonSeamPair("mw_bl", "kb_tl"))
        #expect(CalibrationPointTemplates.isCommonSeamPair("kb_tl", "mw_bl"))

        // Main wall bottom right + kickboard top right
        #expect(CalibrationPointTemplates.commonPartnerID(for: "mw_br") == "kb_tr")
        #expect(CalibrationPointTemplates.commonPartnerID(for: "kb_tr") == "mw_br")
        #expect(CalibrationPointTemplates.isCommonSeamPair("mw_br", "kb_tr"))
        #expect(CalibrationPointTemplates.isCommonSeamPair("kb_tr", "mw_br"))

        // Non-seam points should have no partner
        #expect(CalibrationPointTemplates.commonPartnerID(for: "mw_tl") == nil)
        #expect(CalibrationPointTemplates.commonPartnerID(for: "mw_tr") == nil)
        #expect(CalibrationPointTemplates.commonPartnerID(for: "kb_bl") == nil)
        #expect(CalibrationPointTemplates.commonPartnerID(for: "kb_br") == nil)
        #expect(!CalibrationPointTemplates.isCommonSeamPair("mw_bl", "mw_br"))
        #expect(!CalibrationPointTemplates.isCommonSeamPair("mw_tl", "kb_tl"))
    }
}
