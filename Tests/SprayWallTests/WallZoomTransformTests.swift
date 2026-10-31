import CoreGraphics
import Foundation
import Testing
@testable import SprayWall

@Suite("Wall Zoom & Pan Transformation Matrix Tests")
struct WallZoomTransformTests {

    let fittedSize = CGSize(width: 800, height: 711.11)
    let viewportSize = CGSize(width: 1000, height: 800)

    @Test("Identity zoom centers wall canvas in viewport")
    func identityZoomCentersCanvas() {
        let transform = WallZoomTransform(
            fittedSize: fittedSize,
            viewportSize: viewportSize,
            zoomScale: 1.0,
            panOffset: .zero
        )

        // Center of wall canvas (400, 355.555) must map directly to center of viewport (500, 400)
        let wallCenter = CGPoint(x: fittedSize.width / 2.0, y: fittedSize.height / 2.0)
        let screenCenter = transform.wallToViewport(wallCenter)

        #expect(abs(screenCenter.x - 500.0) < 0.001)
        #expect(abs(screenCenter.y - 400.0) < 0.001)

        // Inverting screen center maps back to wall center
        let invertedWallCenter = transform.viewportToWall(screenCenter)
        #expect(abs(invertedWallCenter.x - wallCenter.x) < 0.001)
        #expect(abs(invertedWallCenter.y - wallCenter.y) < 0.001)
    }

    @Test("Zoom scale and pan translation invert perfectly")
    func zoomAndPanInvertibility() {
        let transform = WallZoomTransform(
            fittedSize: fittedSize,
            viewportSize: viewportSize,
            zoomScale: 2.5,
            panOffset: CGSize(width: 45.0, height: -30.0)
        )

        let arbitraryPoints: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 250),
            CGPoint(x: 400, y: 355),
            CGPoint(x: 750, y: 680)
        ]

        for pt in arbitraryPoints {
            let screenPt = transform.wallToViewport(pt)
            let backPt = transform.viewportToWall(screenPt)
            #expect(abs(backPt.x - pt.x) < 0.001)
            #expect(abs(backPt.y - pt.y) < 0.001)
        }
    }

    @Test("World cm coordinates roundtrip accurately")
    func worldCmRoundtrip() {
        let transform = WallZoomTransform(
            fittedSize: fittedSize,
            viewportSize: viewportSize,
            zoomScale: 1.8,
            panOffset: CGSize(width: -20, height: 15)
        )

        let testCases: [(xCm: Double, yCm: Double)] = [
            (xCm: 0, yCm: 0),
            (xCm: 360, yCm: 360),
            (xCm: 180, yCm: 180),
            (xCm: 90, yCm: 240)
        ]

        for tc in testCases {
            let screen = transform.worldCmToViewport(xCm: tc.xCm, yCm: tc.yCm)
            let world = transform.viewportToWorldCm(screen)
            #expect(abs(world.xCm - tc.xCm) < 0.01)
            #expect(abs(world.yCm - tc.yCm) < 0.01)
        }
    }

    @Test("Spatial hit testing finds hold under mouse when zoomed and shifted")
    func spatialHitTestingWhenZoomed() {
        let transform = WallZoomTransform(
            fittedSize: fittedSize,
            viewportSize: viewportSize,
            zoomScale: 3.0,
            panOffset: CGSize(width: 80, height: -40)
        )

        let hold1 = Hold(holdID: 1, xCm: 50, yCm: 100, plane: .main, role: .hand)
        let hold2 = Hold(holdID: 2, xCm: 180, yCm: 200, plane: .main, role: .hand)
        let hold3 = Hold(holdID: 3, xCm: 300, yCm: 320, plane: .main, role: .hand)
        let holds = [hold1, hold2, hold3]

        // Find exact screen location of hold2
        let hold2ScreenPt = transform.worldCmToViewport(xCm: hold2.xCm, yCm: hold2.yCm)

        // Mouse click slightly offset by (5px, -8px)
        let mouseClick = CGPoint(x: hold2ScreenPt.x + 5.0, y: hold2ScreenPt.y - 8.0)

        let match = transform.closestHold(near: mouseClick, in: holds, maxScreenDistance: 24.0)
        #expect(match != nil)
        #expect(match?.hold.holdID == 2)
        #expect(abs((match?.distance ?? 0) - hypot(5.0, 8.0)) < 0.001)

        // Click far away from any hold returns nil
        let farClick = CGPoint(x: hold2ScreenPt.x + 100.0, y: hold2ScreenPt.y + 100.0)
        let noMatch = transform.closestHold(near: farClick, in: holds, maxScreenDistance: 24.0)
        #expect(noMatch == nil)
    }
}
