import CoreGraphics
import Foundation
import ImageIO

/// Service computing the backward projective transformation (inverse homography)
/// from wall physical coordinates (cm) back to the unwarped original photo's pixels.
enum HoldBackwardTransformService {

    /// 2D Point structure for matrix calculations.
    struct Point2D: Sendable, Equatable {
        var x: Double
        var y: Double

        init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        init(_ point: CGPoint) {
            self.x = Double(point.x)
            self.y = Double(point.y)
        }

        var cgPoint: CGPoint {
            CGPoint(x: x, y: y)
        }
    }

    /// Projective mapping from unit square [0,1]^2 to an arbitrary convex quadrilateral.
    /// Standard Heckbert 2D planar homography.
    struct SquareToQuadMapping: Sendable {
        let h00, h01, h02: Double
        let h10, h11, h12: Double
        let h20, h21, h22: Double

        /// Initializes mapping from (0,0)->p0, (1,0)->p1, (1,1)->p2, (0,1)->p3.
        init(p0: Point2D, p1: Point2D, p2: Point2D, p3: Point2D) {
            let dx1 = p1.x - p2.x
            let dx2 = p3.x - p2.x
            let sx = p0.x - p1.x + p2.x - p3.x
            let dy1 = p1.y - p2.y
            let dy2 = p3.y - p2.y
            let sy = p0.y - p1.y + p2.y - p3.y

            if abs(sx) < 1e-10 && abs(sy) < 1e-10 {
                // Affine case
                h00 = p1.x - p0.x
                h01 = p3.x - p0.x
                h02 = p0.x
                h10 = p1.y - p0.y
                h11 = p3.y - p0.y
                h12 = p0.y
                h20 = 0.0
                h21 = 0.0
                h22 = 1.0
            } else {
                let det = dx1 * dy2 - dy1 * dx2
                if abs(det) < 1e-10 {
                    // Degenerate fallback (identity-like)
                    h00 = 1; h01 = 0; h02 = p0.x
                    h10 = 0; h11 = 1; h12 = p0.y
                    h20 = 0; h21 = 0; h22 = 1
                } else {
                    let a20 = (sx * dy2 - sy * dx2) / det
                    let a21 = (dx1 * sy - dy1 * sx) / det
                    h00 = p1.x - p0.x + a20 * p1.x
                    h01 = p3.x - p0.x + a21 * p3.x
                    h02 = p0.x
                    h10 = p1.y - p0.y + a20 * p1.y
                    h11 = p3.y - p0.y + a21 * p3.y
                    h12 = p0.y
                    h20 = a20
                    h21 = a21
                    h22 = 1.0
                }
            }
        }

        /// Evaluates the projective transform at normalized unit coordinates (u, v).
        func transform(u: Double, v: Double) -> Point2D {
            let w = h20 * u + h21 * v + h22
            guard abs(w) > 1e-10 else {
                return Point2D(x: h02, y: h12)
            }
            let x = (h00 * u + h01 * v + h02) / w
            let y = (h10 * u + h11 * v + h12) / w
            return Point2D(x: x, y: y)
        }
    }

    /// Evaluates the backward transform to find the exact pixel location (photoX, photoY)
    /// in the original image's CoreImage coordinates (origin at bottom-left).
    static func photoPixelLocation(
        xCm: Double,
        yCm: Double,
        plane: HoldPlane,
        calibrationPoints: [CalibrationPoint]
    ) -> CGPoint? {
        let lookup = Dictionary(uniqueKeysWithValues: calibrationPoints.map { ($0.id, $0) })

        let isKickboard: Bool
        if plane == .kickboard {
            isKickboard = true
        } else if plane == .main {
            isKickboard = false
        } else {
            isKickboard = yCm < WallSpec.kickboardHeightCm
        }

        let p0: Point2D
        let p1: Point2D
        let p2: Point2D
        let p3: Point2D
        let normU: Double
        let normV: Double

        if isKickboard {
            guard let bl = lookup["kb_bl"],
                  let br = lookup["kb_br"],
                  let tr = lookup["kb_tr"],
                  let tl = lookup["kb_tl"] else {
                return nil
            }
            p0 = Point2D(x: bl.xPx, y: bl.yPx)
            p1 = Point2D(x: br.xPx, y: br.yPx)
            p2 = Point2D(x: tr.xPx, y: tr.yPx)
            p3 = Point2D(x: tl.xPx, y: tl.yPx)

            let clampedX = min(WallSpec.widthCm, max(0, xCm))
            let clampedY = min(WallSpec.kickboardHeightCm, max(0, yCm))
            normU = clampedX / max(1, WallSpec.widthCm)
            normV = clampedY / max(1, WallSpec.kickboardHeightCm)
        } else {
            guard let bl = lookup["mw_bl"],
                  let br = lookup["mw_br"],
                  let tr = lookup["mw_tr"],
                  let tl = lookup["mw_tl"] else {
                return nil
            }
            p0 = Point2D(x: bl.xPx, y: bl.yPx)
            p1 = Point2D(x: br.xPx, y: br.yPx)
            p2 = Point2D(x: tr.xPx, y: tr.yPx)
            p3 = Point2D(x: tl.xPx, y: tl.yPx)

            let clampedX = min(WallSpec.widthCm, max(0, xCm))
            let clampedY = min(WallSpec.totalHeightCm, max(WallSpec.kickboardHeightCm, yCm))
            normU = clampedX / max(1, WallSpec.widthCm)
            normV = (clampedY - WallSpec.kickboardHeightCm) / max(1, WallSpec.mainWallHeightCm)
        }

        let mapper = SquareToQuadMapping(p0: p0, p1: p1, p2: p2, p3: p3)
        let result = mapper.transform(u: normU, v: normV)
        return result.cgPoint
    }

    /// Convenience overload taking a `Hold` instance.
    static func photoPixelLocation(
        for hold: Hold,
        calibrationPoints: [CalibrationPoint]
    ) -> CGPoint? {
        photoPixelLocation(
            xCm: hold.xCm,
            yCm: hold.yCm,
            plane: hold.plane,
            calibrationPoints: calibrationPoints
        )
    }

    /// Extracts a high-resolution sub-image centered at the physical wall coordinate (xCm, yCm).
    ///
    /// - Parameters:
    ///   - cgImage: The decoded high-resolution original image.
    ///   - xCm: Horizontal coordinate in centimeters.
    ///   - yCm: Vertical coordinate from wall bottom in centimeters.
    ///   - plane: Kickboard or main wall plane.
    ///   - calibrationPoints: Calibration points defining the geometric transform.
    ///   - cropSpan: Side length of the square cropped area in original photo pixels.
    /// - Returns: Cropped `CGImage` at native resolution, or nil if out of bounds or points missing.
    static func cropLocation(
        from cgImage: CGImage,
        xCm: Double,
        yCm: Double,
        plane: HoldPlane,
        calibrationPoints: [CalibrationPoint],
        cropSpan: CGFloat
    ) -> CGImage? {
        guard let location = photoPixelLocation(
            xCm: xCm,
            yCm: yCm,
            plane: plane,
            calibrationPoints: calibrationPoints
        ) else {
            return nil
        }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        // Convert CoreImage (origin bottom-left) to CGImage (row 0 at top)
        let bitmapCenterX = location.x
        let bitmapCenterY = imageHeight - location.y

        let targetSpan = cropSpan.rounded()
        let halfSpan = (targetSpan / 2.0).rounded()
        var originX = (bitmapCenterX - halfSpan).rounded()
        var originY = (bitmapCenterY - halfSpan).rounded()

        // Clamp crop rectangle within image boundaries
        if originX < 0 {
            originX = 0
        } else if originX + targetSpan > imageWidth {
            originX = max(0, imageWidth - targetSpan)
        }

        if originY < 0 {
            originY = 0
        } else if originY + targetSpan > imageHeight {
            originY = max(0, imageHeight - targetSpan)
        }

        let effectiveWidth = min(targetSpan, imageWidth - originX)
        let effectiveHeight = min(targetSpan, imageHeight - originY)

        guard effectiveWidth > 0 && effectiveHeight > 0 else { return nil }

        let cropRect = CGRect(x: originX, y: originY, width: effectiveWidth, height: effectiveHeight)
        return cgImage.cropping(to: cropRect)
    }

    /// Extracts a high-resolution sub-image centered at the hold's original photo position.
    ///
    /// - Parameters:
    ///   - cgImage: The decoded high-resolution original image.
    ///   - hold: The hold to locate and crop.
    ///   - calibrationPoints: Calibration points defining the geometric transform.
    ///   - cropSpan: Side length of the square cropped area in original photo pixels.
    /// - Returns: Cropped `CGImage` at native resolution, or nil if out of bounds or points missing.
    static func cropHold(
        from cgImage: CGImage,
        hold: Hold,
        calibrationPoints: [CalibrationPoint],
        cropSpan: CGFloat
    ) -> CGImage? {
        cropLocation(
            from: cgImage,
            xCm: hold.xCm,
            yCm: hold.yCm,
            plane: hold.plane,
            calibrationPoints: calibrationPoints,
            cropSpan: cropSpan
        )
    }
}
