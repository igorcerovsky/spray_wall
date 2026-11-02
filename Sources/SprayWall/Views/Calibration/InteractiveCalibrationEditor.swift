import CoreGraphics
import CoreImage
import ImageIO
import SwiftUI

/// High-precision interactive calibration and rectification editor.
/// Allows defining and fine-tuning the 8 corner points of the kickboard and main wall
/// directly on the raw unwarped photo with a real-time magnifying loupe, direct point dragging,
/// zoom & pan, and single-pixel nudge controls.
///
/// Note: There is NO rectification transformation here because this view defines the rectification.
/// All coordinates are direct pixel coordinates (xPx, yPx) on the original camera photo.
struct InteractiveCalibrationEditor: View {
    @Binding var points: [CalibrationPoint]
    let photoURL: URL?
    var onSave: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    enum LoadState {
        case loading
        case loaded(CGImage, CGSize)
        case failed(String)
    }

    @State private var loadState: LoadState = .loading
    @State private var editedPoints: [CalibrationPoint] = []
    @State private var selectedPointID: String? = nil
    @State private var draggedPointID: String? = nil
    @State private var hoveredPointID: String? = nil
    @State private var hoveredCursorLocation: CGPoint? = nil
    @State private var hoveredCursorPx: CGPoint? = nil

    // Zoom & Pan state
    @State private var zoomScale: CGFloat = 1.0
    @State private var baseZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var dragStartPan: CGSize? = nil

    // Loupe state & configuration
    @State private var loupeConfig = HoldLoupeConfig.defaultCircle
    @State private var loupeCropCGImage: CGImage? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch loadState {
                case .loading:
                    ProgressView("Loading high-resolution photo...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case let .failed(error):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("Could not load calibration image.")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case let .loaded(cgImage, imageSize):
                    GeometryReader { geo in
                        let baseScale = min(geo.size.width / imageSize.width, geo.size.height / imageSize.height)
                        let effectiveScale = baseScale * zoomScale
                        let displayedSize = CGSize(width: imageSize.width * effectiveScale, height: imageSize.height * effectiveScale)
                        let offsetX = (geo.size.width - displayedSize.width) / 2 + panOffset.width
                        let offsetY = (geo.size.height - displayedSize.height) / 2 + panOffset.height
                        let displayedHeight = displayedSize.height

                        ZStack(alignment: .topLeading) {
                            // Layer 1: Background & Raw Photo
                            Color.black.ignoresSafeArea()

                            Image(decorative: cgImage, scale: 1.0)
                                .resizable()
                                .scaledToFit()
                                .frame(width: displayedSize.width, height: displayedSize.height)
                                .position(x: offsetX + displayedSize.width / 2, y: offsetY + displayedSize.height / 2)

                            // Layer 2: Wall plane quadrilateral outlines
                            wallPlanePolygons(
                                scale: effectiveScale,
                                offsetX: offsetX,
                                offsetY: offsetY,
                                displayedHeight: displayedHeight
                            )

                            // Layer 3: Draggable Point Markers
                            ForEach($editedPoints) { $point in
                                PointMarkerDraggableView(
                                    point: $point,
                                    scale: effectiveScale,
                                    offsetX: offsetX,
                                    offsetY: offsetY,
                                    imageSize: imageSize,
                                    displayedHeight: displayedHeight,
                                    isSelected: selectedPointID == point.id,
                                    isDragged: draggedPointID == point.id,
                                    zoomScale: zoomScale,
                                    onSelect: {
                                        selectPoint(id: point.id, cgImage: cgImage)
                                    },
                                    onDragStart: {
                                        draggedPointID = point.id
                                        selectedPointID = point.id
                                        updateCrop(xPx: point.xPx, yPx: point.yPx, cgImage: cgImage)
                                    },
                                    onDragChanged: {
                                        updateCrop(xPx: point.xPx, yPx: point.yPx, cgImage: cgImage)
                                    },
                                    onDragEnded: {
                                        draggedPointID = nil
                                        updateCrop(xPx: point.xPx, yPx: point.yPx, cgImage: cgImage)
                                    },
                                    onHover: { isHovered in
                                        if isHovered {
                                            hoveredPointID = point.id
                                            updateCrop(xPx: point.xPx, yPx: point.yPx, cgImage: cgImage)
                                        } else if hoveredPointID == point.id {
                                            hoveredPointID = nil
                                            if let selected = selectedPoint {
                                                updateCrop(xPx: selected.xPx, yPx: selected.yPx, cgImage: cgImage)
                                            }
                                        }
                                    }
                                )
                            }

                            // Layer 4: Floating Magnifying Loupe
                            if loupeConfig.isEnabled,
                               let info = currentLoupeInfo(
                                   scale: effectiveScale,
                                   offsetX: offsetX,
                                   offsetY: offsetY,
                                   displayedHeight: displayedHeight
                               ) {
                                let loupePos = WallZoomTransform.computeLoupePosition(
                                    anchorPoint: info.anchor,
                                    loupeConfig: loupeConfig,
                                    viewportSize: geo.size
                                )

                                HoldLoupeView(
                                    croppedImage: loupeCropCGImage,
                                    title: info.title,
                                    subtitle: info.subtitle,
                                    config: loupeConfig
                                )
                                .position(loupePos)
                                .transition(.scale(scale: 0.85).combined(with: .opacity))
                                .allowsHitTesting(false)
                            }

                            // Layer 5: Bottom Fine-Nudge Bar
                            if let selected = selectedPoint {
                                VStack {
                                    Spacer()
                                    fineNudgeBar(
                                        point: selected,
                                        imageSize: imageSize,
                                        cgImage: cgImage
                                    )
                                    .padding(.bottom, 12)
                                    .frame(maxWidth: .infinity)
                                }
                                .allowsHitTesting(true)
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .contentShape(Rectangle())
                        // Background drag gesture for panning when zoomed
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 4)
                                .onChanged { value in
                                    guard draggedPointID == nil, zoomScale > 1.0 else { return }
                                    if dragStartPan == nil {
                                        dragStartPan = panOffset
                                    }
                                    if let start = dragStartPan {
                                        let maxPanX = max(0, (displayedSize.width - geo.size.width) / 2)
                                        let maxPanY = max(0, (displayedSize.height - geo.size.height) / 2)
                                        let candX = start.width + value.translation.width
                                        let candY = start.height + value.translation.height
                                        panOffset = CGSize(
                                            width: min(maxPanX, max(-maxPanX, candX)),
                                            height: min(maxPanY, max(-maxPanY, candY))
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    dragStartPan = nil
                                }
                        )
                        // Pinch to zoom gesture
                        .simultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let targetScale = min(5.0, max(1.0, baseZoomScale * value))
                                    zoomScale = targetScale
                                    if zoomScale <= 1.0 {
                                        panOffset = .zero
                                    } else {
                                        let maxPanX = max(0, (displayedSize.width - geo.size.width) / 2)
                                        let maxPanY = max(0, (displayedSize.height - geo.size.height) / 2)
                                        panOffset = CGSize(
                                            width: min(maxPanX, max(-maxPanX, panOffset.width)),
                                            height: min(maxPanY, max(-maxPanY, panOffset.height))
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    baseZoomScale = zoomScale
                                }
                        )
                        // Mouse hover tracking over background photo
                        .onContinuousHover(coordinateSpace: .local) { phase in
                            switch phase {
                            case let .active(location):
                                handleBackgroundHover(
                                    at: location,
                                    scale: effectiveScale,
                                    offsetX: offsetX,
                                    offsetY: offsetY,
                                    displayedHeight: displayedHeight,
                                    imageSize: imageSize,
                                    cgImage: cgImage
                                )
                            case .ended:
                                hoveredCursorLocation = nil
                                hoveredCursorPx = nil
                            }
                        }
                        #if os(macOS)
                        .background(
                            ScrollWheelZoomModifier { delta, mouseLocation in
                                let previousScale = zoomScale
                                let newScale = min(5.0, max(1.0, zoomScale + (delta * zoomScale)))
                                guard abs(newScale - previousScale) > 0.001 else { return }
                                if newScale <= 1.0 {
                                    zoomScale = 1.0
                                    baseZoomScale = 1.0
                                    panOffset = .zero
                                } else {
                                    zoomScale = newScale
                                    baseZoomScale = newScale
                                    let maxPanX = max(0, (imageSize.width * baseScale * newScale - geo.size.width) / 2)
                                    let maxPanY = max(0, (imageSize.height * baseScale * newScale - geo.size.height) / 2)
                                    panOffset = CGSize(
                                        width: min(maxPanX, max(-maxPanX, panOffset.width)),
                                        height: min(maxPanY, max(-maxPanY, panOffset.height))
                                    )
                                }
                            }
                        )
                        .focusable()
                        .focusEffectDisabled()
                        .onKeyPress { press in
                            handleKeyPress(press: press, imageSize: imageSize, cgImage: cgImage)
                        }
                        #endif
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 900, idealWidth: 1200, minHeight: 650, idealHeight: 900)
            #endif
            .navigationTitle("Interactive Rectification")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .principal) {
                    if ifcaseLoaded {
                        WallZoomControlsView(
                            zoomScale: $zoomScale,
                            panOffset: $panOffset,
                            baseZoomScale: $baseZoomScale,
                            loupeConfig: $loupeConfig
                        )
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            resetToDefaults()
                        } label: {
                            Label("Reset Points to Defaults", systemImage: "arrow.counterclockwise")
                        }

                        if zoomScale > 1.0 {
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    zoomScale = 1.0
                                    baseZoomScale = 1.0
                                    panOffset = .zero
                                }
                            } label: {
                                Label("Reset Zoom to Fit", systemImage: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        points = editedPoints
                        dismiss()
                        onSave?()
                    }
                    .disabled(ifcaseLoaded == false)
                    .buttonStyle(.borderedProminent)
                }
            }
            .task {
                load()
            }
        }
    }

    private var ifcaseLoaded: Bool {
        if case .loaded = loadState { return true }
        return false
    }

    private var selectedPoint: CalibrationPoint? {
        guard let selectedPointID else { return nil }
        return editedPoints.first(where: { $0.id == selectedPointID })
    }

    // MARK: - Loupe Target Determination

    private struct LoupeDisplayInfo {
        let title: String
        let subtitle: String
        let anchor: CGPoint
    }

    private func currentLoupeInfo(
        scale: CGFloat,
        offsetX: CGFloat,
        offsetY: CGFloat,
        displayedHeight: CGFloat
    ) -> LoupeDisplayInfo? {
        // Priority 1: Point being dragged
        if let point = editedPoints.first(where: { $0.id == draggedPointID }) {
            let pos = pointScreenPos(point: point, scale: scale, offsetX: offsetX, offsetY: offsetY, displayedHeight: displayedHeight)
            return LoupeDisplayInfo(
                title: point.label,
                subtitle: "X: \(Int(round(point.xPx))), Y: \(Int(round(point.yPx))) px",
                anchor: pos
            )
        }

        // Priority 2: Point being hovered
        if let point = editedPoints.first(where: { $0.id == hoveredPointID }) {
            let pos = pointScreenPos(point: point, scale: scale, offsetX: offsetX, offsetY: offsetY, displayedHeight: displayedHeight)
            return LoupeDisplayInfo(
                title: point.label,
                subtitle: "X: \(Int(round(point.xPx))), Y: \(Int(round(point.yPx))) px",
                anchor: pos
            )
        }

        // Priority 3: Hovering cursor over photo background
        if let cursorLoc = hoveredCursorLocation, let cursorPx = hoveredCursorPx {
            return LoupeDisplayInfo(
                title: "Photo",
                subtitle: "X: \(Int(round(cursorPx.x))), Y: \(Int(round(cursorPx.y))) px",
                anchor: cursorLoc
            )
        }

        // Priority 4: Selected point (e.g. while fine-nudging)
        if let point = selectedPoint {
            let pos = pointScreenPos(point: point, scale: scale, offsetX: offsetX, offsetY: offsetY, displayedHeight: displayedHeight)
            return LoupeDisplayInfo(
                title: point.label,
                subtitle: "X: \(Int(round(point.xPx))), Y: \(Int(round(point.yPx))) px",
                anchor: pos
            )
        }

        return nil
    }

    private func pointScreenPos(
        point: CalibrationPoint,
        scale: CGFloat,
        offsetX: CGFloat,
        offsetY: CGFloat,
        displayedHeight: CGFloat
    ) -> CGPoint {
        let x = offsetX + (point.xPx * scale)
        let y = offsetY + displayedHeight - (point.yPx * scale)
        return CGPoint(x: x, y: y)
    }

    // MARK: - Plane Outline Polygons

    @ViewBuilder
    private func wallPlanePolygons(
        scale: CGFloat,
        offsetX: CGFloat,
        offsetY: CGFloat,
        displayedHeight: CGFloat
    ) -> some View {
        let lookup = Dictionary(uniqueKeysWithValues: editedPoints.map { ($0.id, $0) })

        // Kickboard quad (kb_bl -> kb_br -> kb_tr -> kb_tl)
        if let bl = lookup["kb_bl"], let br = lookup["kb_br"],
           let tr = lookup["kb_tr"], let tl = lookup["kb_tl"] {
            let quad = QuadPolygonShape(
                p0: pointScreenPos(point: bl, scale: scale, offsetX: offsetX, offsetY: offsetY, displayedHeight: displayedHeight),
                p1: pointScreenPos(point: br, scale: scale, offsetX: offsetX, offsetY: offsetY, displayedHeight: displayedHeight),
                p2: pointScreenPos(point: tr, scale: scale, offsetX: offsetX, offsetY: offsetY, displayedHeight: displayedHeight),
                p3: pointScreenPos(point: tl, scale: scale, offsetX: offsetX, offsetY: offsetY, displayedHeight: displayedHeight)
            )
            quad.fill(Color.orange.opacity(0.12))
            quad.stroke(Color.orange.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }

        // Main Wall quad (mw_bl -> mw_br -> mw_tr -> mw_tl)
        if let bl = lookup["mw_bl"], let br = lookup["mw_br"],
           let tr = lookup["mw_tr"], let tl = lookup["mw_tl"] {
            let quad = QuadPolygonShape(
                p0: pointScreenPos(point: bl, scale: scale, offsetX: offsetX, offsetY: offsetY, displayedHeight: displayedHeight),
                p1: pointScreenPos(point: br, scale: scale, offsetX: offsetX, offsetY: offsetY, displayedHeight: displayedHeight),
                p2: pointScreenPos(point: tr, scale: scale, offsetX: offsetX, offsetY: offsetY, displayedHeight: displayedHeight),
                p3: pointScreenPos(point: tl, scale: scale, offsetX: offsetX, offsetY: offsetY, displayedHeight: displayedHeight)
            )
            quad.fill(Color.cyan.opacity(0.10))
            quad.stroke(Color.cyan.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
    }

    // MARK: - Fine Nudge Bar

    @ViewBuilder
    private func fineNudgeBar(
        point: CalibrationPoint,
        imageSize: CGSize,
        cgImage: CGImage
    ) -> some View {
        HStack(spacing: 10) {
            // Point selector menu
            Menu {
                ForEach(editedPoints) { pt in
                    Button {
                        selectPoint(id: pt.id, cgImage: cgImage)
                    } label: {
                        HStack {
                            Text(pt.label)
                            if pt.id == point.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(point.id.hasPrefix("kb") ? Color.orange : Color.cyan)
                        .frame(width: 8, height: 8)
                    Text(point.label)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            // Previous / Next point steppers
            HStack(spacing: 2) {
                Button {
                    cyclePoint(forward: false, cgImage: cgImage)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption2.weight(.bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Previous Point")

                Button {
                    cyclePoint(forward: true, cgImage: cgImage)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Next Point")
            }

            Divider().frame(height: 18)

            // X-Axis Nudge Buttons
            HStack(spacing: 4) {
                Text("X: \(Int(round(point.xPx)))")
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 64, alignment: .leading)

                nudgeButton(label: "-10", dx: -10, dy: 0, imageSize: imageSize, cgImage: cgImage)
                nudgeButton(label: "-1", dx: -1, dy: 0, imageSize: imageSize, cgImage: cgImage)
                nudgeButton(label: "+1", dx: 1, dy: 0, imageSize: imageSize, cgImage: cgImage)
                nudgeButton(label: "+10", dx: 10, dy: 0, imageSize: imageSize, cgImage: cgImage)
            }

            Divider().frame(height: 18)

            // Y-Axis Nudge Buttons
            HStack(spacing: 4) {
                Text("Y: \(Int(round(point.yPx)))")
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 64, alignment: .leading)

                nudgeButton(label: "-10", dx: 0, dy: -10, imageSize: imageSize, cgImage: cgImage)
                nudgeButton(label: "-1", dx: 0, dy: -1, imageSize: imageSize, cgImage: cgImage)
                nudgeButton(label: "+1", dx: 0, dy: 1, imageSize: imageSize, cgImage: cgImage)
                nudgeButton(label: "+10", dx: 0, dy: 10, imageSize: imageSize, cgImage: cgImage)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
    }

    private func nudgeButton(
        label: String,
        dx: Double,
        dy: Double,
        imageSize: CGSize,
        cgImage: CGImage
    ) -> some View {
        Button(label) {
            nudgeSelected(dx: dx, dy: dy, imageSize: imageSize, cgImage: cgImage)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .font(.caption2.monospacedDigit())
    }

    // MARK: - Interaction & Crop Updates

    private func handleBackgroundHover(
        at location: CGPoint,
        scale: CGFloat,
        offsetX: CGFloat,
        offsetY: CGFloat,
        displayedHeight: CGFloat,
        imageSize: CGSize,
        cgImage: CGImage
    ) {
        guard draggedPointID == nil, hoveredPointID == nil else { return }

        let pxX = (location.x - offsetX) / scale
        let pxY = (offsetY + displayedHeight - location.y) / scale

        if pxX >= 0, pxX <= imageSize.width, pxY >= 0, pxY <= imageSize.height {
            hoveredCursorLocation = location
            hoveredCursorPx = CGPoint(x: pxX, y: pxY)
            updateCrop(xPx: pxX, yPx: pxY, cgImage: cgImage)
        } else {
            hoveredCursorLocation = nil
            hoveredCursorPx = nil
        }
    }

    private func nudgeSelected(
        dx: Double,
        dy: Double,
        imageSize: CGSize,
        cgImage: CGImage
    ) {
        guard let id = selectedPointID,
              let idx = editedPoints.firstIndex(where: { $0.id == id }) else { return }

        let newX = round(min(Double(imageSize.width), max(0, editedPoints[idx].xPx + dx)))
        let newY = round(min(Double(imageSize.height), max(0, editedPoints[idx].yPx + dy)))

        editedPoints[idx].xPx = newX
        editedPoints[idx].yPx = newY
        updateCrop(xPx: newX, yPx: newY, cgImage: cgImage)
    }

    private func selectPoint(id: String, cgImage: CGImage) {
        selectedPointID = id
        hoveredCursorLocation = nil
        hoveredCursorPx = nil
        if let pt = editedPoints.first(where: { $0.id == id }) {
            updateCrop(xPx: pt.xPx, yPx: pt.yPx, cgImage: cgImage)
        }
    }

    private func cyclePoint(forward: Bool, cgImage: CGImage) {
        guard !editedPoints.isEmpty else { return }
        let currentIndex = editedPoints.firstIndex(where: { $0.id == selectedPointID }) ?? 0
        let nextIndex: Int
        if forward {
            nextIndex = (currentIndex + 1) % editedPoints.count
        } else {
            nextIndex = (currentIndex - 1 + editedPoints.count) % editedPoints.count
        }
        let nextPoint = editedPoints[nextIndex]
        selectPoint(id: nextPoint.id, cgImage: cgImage)
    }

    /// Directly crops a 100% native resolution patch from the camera photo centered at (xPx, yPx).
    /// There is NO transformation or homography applied — raw photo pixels map directly to the bitmap.
    private func updateCrop(xPx: Double, yPx: Double, cgImage: CGImage) {
        guard loupeConfig.isEnabled else {
            loupeCropCGImage = nil
            return
        }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        // CoreImage / calibration standard has yPx origin at bottom.
        // CGImage bitmap has row 0 at top.
        let bitmapCenterX = CGFloat(xPx)
        let bitmapCenterY = imageHeight - CGFloat(yPx)

        let targetSpan = loupeConfig.cropPixelSpan.rounded()
        let halfSpan = (targetSpan / 2.0).rounded()
        var originX = (bitmapCenterX - halfSpan).rounded()
        var originY = (bitmapCenterY - halfSpan).rounded()

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

        guard effectiveWidth > 0, effectiveHeight > 0 else {
            loupeCropCGImage = nil
            return
        }

        let cropRect = CGRect(x: originX, y: originY, width: effectiveWidth, height: effectiveHeight)
        loupeCropCGImage = cgImage.cropping(to: cropRect)
    }

    #if os(macOS)
    private func handleKeyPress(
        press: KeyPress,
        imageSize: CGSize,
        cgImage: CGImage
    ) -> KeyPress.Result {
        guard selectedPointID != nil else { return .ignored }
        let step: Double = press.modifiers.contains(.shift) ? 10.0 : 1.0

        switch press.key {
        case .leftArrow:
            nudgeSelected(dx: -step, dy: 0, imageSize: imageSize, cgImage: cgImage)
            return .handled
        case .rightArrow:
            nudgeSelected(dx: step, dy: 0, imageSize: imageSize, cgImage: cgImage)
            return .handled
        case .upArrow:
            nudgeSelected(dx: 0, dy: step, imageSize: imageSize, cgImage: cgImage)
            return .handled
        case .downArrow:
            nudgeSelected(dx: 0, dy: -step, imageSize: imageSize, cgImage: cgImage)
            return .handled
        case .tab:
            cyclePoint(forward: !press.modifiers.contains(.shift), cgImage: cgImage)
            return .handled
        case .escape:
            selectedPointID = nil
            loupeCropCGImage = nil
            return .handled
        default:
            return .ignored
        }
    }
    #endif

    private func resetToDefaults() {
        let defaults = CalibrationPointTemplates.all
        let byID = Dictionary(uniqueKeysWithValues: defaults.map { ($0.id, $0) })
        for idx in editedPoints.indices {
            if let def = byID[editedPoints[idx].id] {
                editedPoints[idx].xPx = def.xPx
                editedPoints[idx].yPx = def.yPx
            }
        }
        if case let .loaded(cgImage, _) = loadState,
           let selected = selectedPoint {
            updateCrop(xPx: selected.xPx, yPx: selected.yPx, cgImage: cgImage)
        }
    }

    // MARK: - Loading

    private func load() {
        editedPoints = points

        if selectedPointID == nil {
            selectedPointID = editedPoints.first(where: { $0.id == "mw_tl" })?.id ?? editedPoints.first?.id
        }

        guard let url = photoURL else {
            loadState = .failed("No photo available. Please import or specify a valid photo in project resources.")
            return
        }

        Task.detached {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                await MainActor.run { loadState = .failed("Failed to open image file at \(url.path).") }
                return
            }
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false
            ]
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
                await MainActor.run { loadState = .failed("Failed to decode image from \(url.lastPathComponent).") }
                return
            }

            let width = CGFloat(image.width)
            let height = CGFloat(image.height)

            await MainActor.run {
                self.loadState = .loaded(image, CGSize(width: width, height: height))

                for index in self.editedPoints.indices {
                    self.editedPoints[index].xPx = round(max(0, min(width, self.editedPoints[index].xPx)))
                    self.editedPoints[index].yPx = round(max(0, min(height, self.editedPoints[index].yPx)))
                }

                if let selected = self.selectedPoint {
                    self.updateCrop(xPx: selected.xPx, yPx: selected.yPx, cgImage: image)
                }
            }
        }
    }
}

// MARK: - Supporting Shapes & Views

private struct QuadPolygonShape: Shape {
    let p0: CGPoint
    let p1: CGPoint
    let p2: CGPoint
    let p3: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: p0)
        path.addLine(to: p1)
        path.addLine(to: p2)
        path.addLine(to: p3)
        path.closeSubpath()
        return path
    }
}

private struct PointMarkerDraggableView: View {
    @Binding var point: CalibrationPoint
    let scale: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
    let imageSize: CGSize
    let displayedHeight: CGFloat
    let isSelected: Bool
    let isDragged: Bool
    let zoomScale: CGFloat
    var onSelect: () -> Void
    var onDragStart: () -> Void
    var onDragChanged: () -> Void
    var onDragEnded: () -> Void
    var onHover: (Bool) -> Void

    @State private var dragStartPoint: CGPoint? = nil

    var body: some View {
        let viewX = offsetX + (point.xPx * scale)
        let viewY = offsetY + displayedHeight - (point.yPx * scale)
        let isKickboard = point.id.hasPrefix("kb")
        let accentColor = isKickboard ? Color.orange : Color.cyan
        let isHighlighted = isSelected || isDragged

        ZStack(alignment: .center) {
            // Glowing outer accent ring if selected or dragged
            if isHighlighted {
                Circle()
                    .stroke(Color.yellow, lineWidth: 2.5)
                    .frame(width: 34, height: 34)
                    .shadow(color: Color.yellow.opacity(0.8), radius: 4)
            }

            // Main handle circle
            Circle()
                .fill(accentColor.opacity(isHighlighted ? 0.90 : 0.65))
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))

            // Center targeting red dot
            Circle()
                .fill(Color.red)
                .frame(width: 4, height: 4)

            // Label badge
            Text(point.label)
                .font(.system(size: 9, weight: .bold))
                .fixedSize()
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(isHighlighted ? 0.88 : 0.68))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .offset(y: -20)
        }
        .scaleEffect(1.0 / max(1.0, sqrt(zoomScale)))
        .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
        .position(x: viewX, y: viewY)
        .onHover { hovering in
            onHover(hovering)
        }
        .onTapGesture {
            onSelect()
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStartPoint == nil {
                        dragStartPoint = CGPoint(x: point.xPx, y: point.yPx)
                        onDragStart()
                    }
                    if let start = dragStartPoint {
                        let deltaXPx = value.translation.width / scale
                        let deltaYPx = -value.translation.height / scale

                        point.xPx = round(max(0, min(imageSize.width, start.x + deltaXPx)))
                        point.yPx = round(max(0, min(imageSize.height, start.y + deltaYPx)))
                        onDragChanged()
                    }
                }
                .onEnded { _ in
                    dragStartPoint = nil
                    onDragEnded()
                }
        )
    }
}
