import CoreGraphics
import Foundation

/// Mathematical transformation model handling zoom (scale), pan (shift), and viewport mapping
/// specifically for raw camera photo pixels during interactive calibration and rectification.
///
/// Origin conventions:
/// - Photo pixel coordinates (xPx, yPx): CoreImage standard (origin at bottom-left, y increasing upward).
/// - Canvas coordinates: Local view frame [0..fittedSize.width, 0..fittedSize.height] (origin at top-left, y increasing downward).
/// - Screen viewport coordinates: GeometryReader bounds [0..viewportSize.width, 0..viewportSize.height].
struct CalibrationZoomTransform: Sendable, Equatable {
    let imageSize: CGSize
    let fittedSize: CGSize
    let viewportSize: CGSize
    let zoomScale: CGFloat
    let panOffset: CGSize

    init(
        imageSize: CGSize,
        viewportSize: CGSize,
        zoomScale: CGFloat,
        panOffset: CGSize
    ) {
        self.imageSize = imageSize
        self.viewportSize = viewportSize
        self.zoomScale = max(0.1, zoomScale)
        self.panOffset = panOffset

        let imageAspect = imageSize.width / max(1, imageSize.height)
        let viewportAspect = viewportSize.width / max(1, viewportSize.height)
        if viewportAspect > imageAspect {
            let fitH = max(10, viewportSize.height)
            self.fittedSize = CGSize(width: fitH * imageAspect, height: fitH)
        } else {
            let fitW = max(10, viewportSize.width)
            self.fittedSize = CGSize(width: fitW, height: fitW / imageAspect)
        }
    }

    // MARK: - Transformation Matrices

    /// The 3x3 forward affine transformation matrix mapping from local photo canvas points
    /// [0..fittedSize.width, 0..fittedSize.height] to screen viewport coordinates [0..viewportSize.width, 0..viewportSize.height].
    var matrix: CGAffineTransform {
        var t = CGAffineTransform.identity
        t = t.translatedBy(
            x: (viewportSize.width / 2.0) + panOffset.width,
            y: (viewportSize.height / 2.0) + panOffset.height
        )
        t = t.scaledBy(x: zoomScale, y: zoomScale)
        t = t.translatedBy(
            x: -(fittedSize.width / 2.0),
            y: -(fittedSize.height / 2.0)
        )
        return t
    }

    /// The inverse 3x3 transformation matrix mapping screen viewport coordinates back to local photo canvas points.
    var inverseMatrix: CGAffineTransform {
        matrix.inverted()
    }

    // MARK: - Coordinate Conversions

    /// Converts raw photo pixel coordinates (xPx, yPx) [bottom-left origin] to local canvas coordinates [top-left origin].
    func photoPxToCanvas(xPx: Double, yPx: Double) -> CGPoint {
        let x = (CGFloat(xPx) / max(1, imageSize.width)) * fittedSize.width
        let y = (1.0 - (CGFloat(yPx) / max(1, imageSize.height))) * fittedSize.height
        return CGPoint(x: x, y: y)
    }

    /// Converts local canvas coordinates [top-left origin] back to raw photo pixel coordinates (xPx, yPx) [bottom-left origin].
    func canvasToPhotoPx(_ point: CGPoint) -> (xPx: Double, yPx: Double) {
        let normX = Double(point.x / max(1, fittedSize.width))
        let normY = Double(point.y / max(1, fittedSize.height))
        let clampedX = min(Double(imageSize.width), max(0, normX * Double(imageSize.width)))
        let clampedY = min(Double(imageSize.height), max(0, (1.0 - normY) * Double(imageSize.height)))
        return (xPx: clampedX, yPx: clampedY)
    }

    /// Converts raw photo pixel coordinates (xPx, yPx) directly to screen viewport coordinates,
    /// fully accounting for zoom scale and pan shift.
    func photoPxToViewport(xPx: Double, yPx: Double) -> CGPoint {
        let canvasPt = photoPxToCanvas(xPx: xPx, yPx: yPx)
        return canvasPt.applying(matrix)
    }

    /// Converts screen viewport coordinates (mouse cursor, click, drag location) directly to raw photo pixel coordinates (xPx, yPx),
    /// fully inverting zoom scale and pan shift.
    func viewportToPhotoPx(_ viewportPoint: CGPoint) -> (xPx: Double, yPx: Double) {
        let canvasPt = viewportPoint.applying(inverseMatrix)
        return canvasToPhotoPx(canvasPt)
    }

    // MARK: - Spatial Hit-Testing

    /// Finds the closest calibration point whose visual marker on the screen is within `maxScreenDistance` points
    /// of the given viewport point (e.g. mouse cursor or tap point).
    func closestPoint(
        near viewportPoint: CGPoint,
        in points: [CalibrationPoint],
        maxScreenDistance: CGFloat = 30.0
    ) -> (point: CalibrationPoint, distance: CGFloat)? {
        var closest: CalibrationPoint? = nil
        var minDistance = maxScreenDistance

        for pt in points {
            let screenPt = photoPxToViewport(xPx: pt.xPx, yPx: pt.yPx)
            let dist = hypot(viewportPoint.x - screenPt.x, viewportPoint.y - screenPt.y)
            if dist <= minDistance {
                minDistance = dist
                closest = pt
            }
        }

        if let closest {
            return (point: closest, distance: minDistance)
        }
        return nil
    }

    // MARK: - Clamping & Zoom Logic

    /// Clamps pan translation offset so the image canvas never pans completely off-screen.
    static func clampedOffset(
        _ candidate: CGSize,
        fittedSize: CGSize,
        viewportSize: CGSize,
        scale: CGFloat
    ) -> CGSize {
        WallZoomTransform.clampedOffset(candidate, fittedSize: fittedSize, viewportSize: viewportSize, scale: scale)
    }

    /// Calculates new scale and pan offset for focal zooming towards a given mouse location.
    static func focalZoom(
        delta: CGFloat,
        mouseLocation: CGPoint,
        currentScale: CGFloat,
        currentOffset: CGSize,
        fittedSize: CGSize,
        viewportSize: CGSize,
        minScale: CGFloat = 1.0,
        maxScale: CGFloat = 5.0
    ) -> (newScale: CGFloat, newOffset: CGSize)? {
        WallZoomTransform.focalZoom(
            delta: delta,
            mouseLocation: mouseLocation,
            currentScale: currentScale,
            currentOffset: currentOffset,
            fittedSize: fittedSize,
            viewportSize: viewportSize,
            minScale: minScale,
            maxScale: maxScale
        )
    }
}
