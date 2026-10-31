import CoreGraphics
import Foundation

/// Mathematical transformation model handling zoom (scale), pan (shift), and viewport mapping.
/// Provides forward and inverse transformation matrices connecting:
/// 1. Screen Viewport Coordinates (mouse pointer, clicks, gestures)
/// 2. Wall Canvas Coordinates (fitted wall aspect ratio)
/// 3. Physical Wall World Coordinates (xCm, yCm in real life)
struct WallZoomTransform: Sendable, Equatable {
    let fittedSize: CGSize
    let viewportSize: CGSize
    let zoomScale: CGFloat
    let panOffset: CGSize

    init(
        fittedSize: CGSize,
        viewportSize: CGSize,
        zoomScale: CGFloat,
        panOffset: CGSize
    ) {
        self.fittedSize = fittedSize
        self.viewportSize = viewportSize
        self.zoomScale = max(0.1, zoomScale)
        self.panOffset = panOffset
    }

    // MARK: - Transformation Matrices

    /// The 3x3 forward affine transformation matrix mapping from local wall canvas points
    /// [0..fittedSize.width, 0..fittedSize.height] to screen viewport coordinates [0..viewportSize.width, 0..viewportSize.height].
    var matrix: CGAffineTransform {
        var t = CGAffineTransform.identity
        // 1. Translate to viewport center plus pan offset (shift)
        t = t.translatedBy(
            x: (viewportSize.width / 2.0) + panOffset.width,
            y: (viewportSize.height / 2.0) + panOffset.height
        )
        // 2. Scale around the center of the canvas
        t = t.scaledBy(x: zoomScale, y: zoomScale)
        // 3. Move origin from center to top-left of wall canvas
        t = t.translatedBy(
            x: -(fittedSize.width / 2.0),
            y: -(fittedSize.height / 2.0)
        )
        return t
    }

    /// The inverse 3x3 transformation matrix mapping screen viewport coordinates back to local wall canvas points.
    var inverseMatrix: CGAffineTransform {
        matrix.inverted()
    }

    // MARK: - Point Transformations

    /// Maps a point on the wall canvas to screen viewport coordinates.
    func wallToViewport(_ point: CGPoint) -> CGPoint {
        point.applying(matrix)
    }

    /// Maps a point in the screen viewport (e.g. mouse cursor, click location) to the wall canvas.
    func viewportToWall(_ point: CGPoint) -> CGPoint {
        point.applying(inverseMatrix)
    }

    // MARK: - World Coordinates (cm) Mapping

    /// Converts physical wall world coordinates (xCm, yCm) to local point on the wall canvas.
    func worldCmToWall(xCm: Double, yCm: Double) -> CGPoint {
        let x = (xCm / WallSpec.widthCm) * fittedSize.width
        let y = (1.0 - (yCm / WallSpec.totalHeightCm)) * fittedSize.height
        return CGPoint(x: x, y: y)
    }

    /// Converts a local point on the wall canvas to physical wall world coordinates (xCm, yCm).
    func wallToWorldCm(_ point: CGPoint) -> (xCm: Double, yCm: Double) {
        let xRatio = Double(point.x / max(1.0, fittedSize.width))
        let yRatio = Double(point.y / max(1.0, fittedSize.height))
        let xCm = min(WallSpec.widthCm, max(0, xRatio * WallSpec.widthCm))
        let yCm = min(WallSpec.totalHeightCm, max(0, (1.0 - yRatio) * WallSpec.totalHeightCm))
        return (xCm: xCm, yCm: yCm)
    }

    /// Converts physical wall world coordinates (xCm, yCm) directly to screen viewport coordinates
    /// fully accounting for zoom scale and pan shift.
    func worldCmToViewport(xCm: Double, yCm: Double) -> CGPoint {
        let wallPt = worldCmToWall(xCm: xCm, yCm: yCm)
        return wallToViewport(wallPt)
    }

    /// Converts a point in the screen viewport directly to physical wall world coordinates (xCm, yCm)
    /// fully inverting zoom scale and pan shift.
    func viewportToWorldCm(_ point: CGPoint) -> (xCm: Double, yCm: Double) {
        let wallPt = viewportToWall(point)
        return wallToWorldCm(wallPt)
    }

    // MARK: - Spatial Hit-Testing on Screen

    /// Finds the closest hold whose visual marker on the screen is within `maxScreenDistance` points
    /// of the given viewport point (e.g. mouse cursor or tap point).
    func closestHold(
        near viewportPoint: CGPoint,
        in holds: [Hold],
        maxScreenDistance: CGFloat = 24.0
    ) -> (hold: Hold, distance: CGFloat)? {
        var closest: Hold? = nil
        var minDistance = maxScreenDistance

        for hold in holds {
            let screenPt = worldCmToViewport(xCm: hold.xCm, yCm: hold.yCm)
            let dist = hypot(viewportPoint.x - screenPt.x, viewportPoint.y - screenPt.y)
            if dist <= minDistance {
                minDistance = dist
                closest = hold
            }
        }

        if let closest {
            return (hold: closest, distance: minDistance)
        }
        return nil
    }

    // MARK: - Reusable Zoom Geometry & Clamping Math

    /// Computes fitted wall dimensions preserving aspect ratio inside a given viewport.
    static func computeFittedSize(in viewport: CGSize) -> CGSize {
        let wallAspect: CGFloat = WallSpec.widthCm / WallSpec.totalHeightCm
        if (viewport.width / max(1, viewport.height)) > wallAspect {
            let fitHeight = max(10, viewport.height)
            return CGSize(width: fitHeight * wallAspect, height: fitHeight)
        } else {
            let fitWidth = max(10, viewport.width)
            return CGSize(width: fitWidth, height: fitWidth / wallAspect)
        }
    }

    /// Clamps pan translation offset so the wall canvas never pans completely off-screen.
    static func clampedOffset(
        _ candidate: CGSize,
        fittedSize: CGSize,
        viewportSize: CGSize,
        scale: CGFloat
    ) -> CGSize {
        let scaledWidth = fittedSize.width * scale
        let scaledHeight = fittedSize.height * scale

        let maxPanX = max(0, (scaledWidth - viewportSize.width) / 2)
        let clampedX = min(maxPanX, max(-maxPanX, candidate.width))

        let maxPanY = max(0, (scaledHeight - viewportSize.height) / 2)
        let clampedY = min(maxPanY, max(-maxPanY, candidate.height))

        return CGSize(width: clampedX, height: clampedY)
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
        let previousScale = currentScale
        let newScale = min(maxScale, max(minScale, currentScale + (delta * currentScale)))
        guard abs(newScale - previousScale) > 0.001 else { return nil }

        if newScale <= 1.0 {
            return (newScale: 1.0, newOffset: .zero)
        }

        let mouseFromCenterX = mouseLocation.x - (viewportSize.width / 2)
        let mouseFromCenterY = mouseLocation.y - (viewportSize.height / 2)

        let scaleRatio = newScale / previousScale
        let targetX = mouseFromCenterX - ((mouseFromCenterX - currentOffset.width) * scaleRatio)
        let targetY = mouseFromCenterY - ((mouseFromCenterY - currentOffset.height) * scaleRatio)

        let clamped = clampedOffset(
            CGSize(width: targetX, height: targetY),
            fittedSize: fittedSize,
            viewportSize: viewportSize,
            scale: newScale
        )
        return (newScale: newScale, newOffset: clamped)
    }

    /// Computes screen position for the floating magnifying loupe clamped safely within viewport boundaries.
    static func computeLoupePosition(
        anchorPoint: CGPoint,
        loupeConfig: HoldLoupeConfig,
        viewportSize: CGSize
    ) -> CGPoint {
        let loupeW = loupeConfig.size.width
        let loupeH = loupeConfig.size.height + (loupeConfig.showBadge ? 28 : 0)

        let halfW = loupeW / 2
        let halfH = loupeH / 2

        var candidateX = anchorPoint.x + loupeConfig.offsetFromMarker.width
        var candidateY = anchorPoint.y + loupeConfig.offsetFromMarker.height

        // If too close to top edge, flip below anchor
        if candidateY - halfH < 12 {
            candidateY = anchorPoint.y + abs(loupeConfig.offsetFromMarker.height)
        }

        // Clamp inside viewport bounds
        let minX = halfW + 12
        let maxX = max(minX, viewportSize.width - halfW - 12)
        candidateX = min(maxX, max(minX, candidateX))

        let minY = halfH + 12
        let maxY = max(minY, viewportSize.height - halfH - 12)
        candidateY = min(maxY, max(minY, candidateY))

        return CGPoint(x: candidateX, y: candidateY)
    }
}

