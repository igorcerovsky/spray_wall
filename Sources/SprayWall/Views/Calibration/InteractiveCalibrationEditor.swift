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
    @State private var dragStartPointPx: CGPoint? = nil
    @State private var isNudgingActive = false

    // Joint moving of kickboard and main wall common seam points (mw_bl ↔ kb_tl, mw_br ↔ kb_tr)
    @AppStorage("interactiveCalibration_jointCommonPoints") private var jointCommonPoints: Bool = true

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
                            .allowsHitTesting(false)

                            // Layer 3: Visual Point Markers (interaction handled by canvas spatial gestures)
                            ForEach(editedPoints) { point in
                                PointMarkerVisualView(
                                    point: point,
                                    screenPos: pointScreenPos(
                                        point: point,
                                        scale: effectiveScale,
                                        offsetX: offsetX,
                                        offsetY: offsetY,
                                        displayedHeight: displayedHeight
                                    ),
                                    isSelected: isPointOrPartnerSelected(point.id),
                                    isHovered: isPointOrPartnerHovered(point.id),
                                    isDragged: isPointOrPartnerDragged(point.id),
                                    isJointLinked: jointCommonPoints && CalibrationPointTemplates.commonPartnerID(for: point.id) != nil,
                                    displayLabel: pointMarkerBadgeLabel(for: point),
                                    hideBadge: shouldHideDuplicateBadge(for: point),
                                    zoomScale: zoomScale
                                )
                            }
                            .allowsHitTesting(false)

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
                        // Tap gesture to select calibration point
                        .simultaneousGesture(
                            SpatialTapGesture()
                                .onEnded { value in
                                    if let match = closestPoint(
                                        near: value.location,
                                        in: editedPoints,
                                        scale: effectiveScale,
                                        offsetX: offsetX,
                                        offsetY: offsetY,
                                        displayedHeight: displayedHeight,
                                        maxScreenDistance: 28.0
                                    ) {
                                        selectPoint(id: match.point.id, cgImage: cgImage)
                                    }
                                }
                        )
                        // Drag gesture: drags calibration point if starting near one; pans canvas if starting outside when zoomed
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    if draggedPointID == nil && dragStartPan == nil {
                                        if let match = closestPoint(
                                            near: value.startLocation,
                                            in: editedPoints,
                                            scale: effectiveScale,
                                            offsetX: offsetX,
                                            offsetY: offsetY,
                                            displayedHeight: displayedHeight,
                                            maxScreenDistance: 28.0
                                        ) {
                                            draggedPointID = match.point.id
                                            selectedPointID = match.point.id
                                            dragStartPointPx = CGPoint(x: match.point.xPx, y: match.point.yPx)
                                            hoveredPointID = nil
                                            hoveredCursorLocation = nil
                                            isNudgingActive = false
                                            updateCrop(xPx: match.point.xPx, yPx: match.point.yPx, cgImage: cgImage)
                                        } else if zoomScale > 1.0 {
                                            dragStartPan = panOffset
                                        }
                                    }

                                    if let pointID = draggedPointID, let startPx = dragStartPointPx,
                                       let idx = editedPoints.firstIndex(where: { $0.id == pointID }) {
                                        let deltaXPx = value.translation.width / effectiveScale
                                        let deltaYPx = -value.translation.height / effectiveScale

                                        let newX = round(max(0, min(imageSize.width, startPx.x + deltaXPx)))
                                        let newY = round(max(0, min(imageSize.height, startPx.y + deltaYPx)))

                                        editedPoints[idx].xPx = newX
                                        editedPoints[idx].yPx = newY

                                        // If joint moving of common seam points is enabled, sync partner point in real-time
                                        if jointCommonPoints,
                                           let partnerID = CalibrationPointTemplates.commonPartnerID(for: pointID),
                                           let partnerIdx = editedPoints.firstIndex(where: { $0.id == partnerID }) {
                                            editedPoints[partnerIdx].xPx = newX
                                            editedPoints[partnerIdx].yPx = newY
                                        }

                                        updateCrop(xPx: newX, yPx: newY, cgImage: cgImage)
                                    } else if let startPan = dragStartPan {
                                        let maxPanX = max(0, (displayedSize.width - geo.size.width) / 2)
                                        let maxPanY = max(0, (displayedSize.height - geo.size.height) / 2)
                                        let candX = startPan.width + value.translation.width
                                        let candY = startPan.height + value.translation.height
                                        panOffset = CGSize(
                                            width: min(maxPanX, max(-maxPanX, candX)),
                                            height: min(maxPanY, max(-maxPanY, candY))
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    if let pointID = draggedPointID,
                                       let pt = editedPoints.first(where: { $0.id == pointID }) {
                                        if jointCommonPoints,
                                           let partnerID = CalibrationPointTemplates.commonPartnerID(for: pointID),
                                           let partnerIdx = editedPoints.firstIndex(where: { $0.id == partnerID }) {
                                            editedPoints[partnerIdx].xPx = pt.xPx
                                            editedPoints[partnerIdx].yPx = pt.yPx
                                        }
                                        updateCrop(xPx: pt.xPx, yPx: pt.yPx, cgImage: cgImage)
                                    }
                                    draggedPointID = nil
                                    dragStartPointPx = nil
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
                        // Continuous mouse hover tracking over background photo and calibration markers
                        .onContinuousHover(coordinateSpace: .local) { phase in
                            switch phase {
                            case let .active(location):
                                handleContinuousHover(
                                    at: location,
                                    scale: effectiveScale,
                                    offsetX: offsetX,
                                    offsetY: offsetY,
                                    displayedHeight: displayedHeight,
                                    imageSize: imageSize,
                                    cgImage: cgImage
                                )
                            case .ended:
                                hoveredPointID = nil
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
                                    // Focal zoom towards mouse cursor position
                                    let oldScale = effectiveScale
                                    let curPxX = (mouseLocation.x - offsetX) / oldScale
                                    let curPxY = (displayedHeight + offsetY - mouseLocation.y) / oldScale

                                    zoomScale = newScale
                                    baseZoomScale = newScale

                                    let newEffectiveScale = baseScale * newScale
                                    let newDisplayedW = imageSize.width * newEffectiveScale
                                    let newDisplayedH = imageSize.height * newEffectiveScale

                                    let targetOffsetX = mouseLocation.x - (curPxX * newEffectiveScale)
                                    let targetOffsetY = mouseLocation.y - (imageSize.height - curPxY) * newEffectiveScale

                                    let candPanX = targetOffsetX - (geo.size.width - newDisplayedW) / 2
                                    let candPanY = targetOffsetY - (geo.size.height - newDisplayedH) / 2

                                    let maxPanX = max(0, (newDisplayedW - geo.size.width) / 2)
                                    let maxPanY = max(0, (newDisplayedH - geo.size.height) / 2)

                                    panOffset = CGSize(
                                        width: min(maxPanX, max(-maxPanX, candPanX)),
                                        height: min(maxPanY, max(-maxPanY, candPanY))
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
                        HStack(spacing: 12) {
                            WallZoomControlsView(
                                zoomScale: $zoomScale,
                                panOffset: $panOffset,
                                baseZoomScale: $baseZoomScale,
                                loupeConfig: $loupeConfig
                            )

                            #if os(macOS)
                            HStack(spacing: 6) {
                                Toggle(isOn: $jointCommonPoints) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "link")
                                            .font(.caption2)
                                        Text("Joint Common Seam")
                                            .font(.caption)
                                    }
                                }
                                .toggleStyle(.checkbox)
                                .help("Joint moving kickboard & main wall common points:\n• Main Wall Bottom Left + Kickboard Top Left (mw_bl ↔ kb_tl)\n• Main Wall Bottom Right + Kickboard Top Right (mw_br ↔ kb_tr)")
                                .onChange(of: jointCommonPoints) { _, isJoint in
                                    if isJoint {
                                        syncCommonPointsIfNeeded()
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            #endif
                        }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Toggle(isOn: $jointCommonPoints) {
                            Label("Joint Common Seam (mw_bl ↔ kb_tl, mw_br ↔ kb_tr)", systemImage: "link")
                        }
                        .onChange(of: jointCommonPoints) { _, isJoint in
                            if isJoint {
                                syncCommonPointsIfNeeded()
                            }
                        }

                        Divider()

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

    private func isPointOrPartnerSelected(_ id: String) -> Bool {
        if selectedPointID == id { return true }
        if jointCommonPoints, let partnerID = CalibrationPointTemplates.commonPartnerID(for: id), selectedPointID == partnerID {
            return true
        }
        return false
    }

    private func isPointOrPartnerHovered(_ id: String) -> Bool {
        if hoveredPointID == id { return true }
        if jointCommonPoints, let partnerID = CalibrationPointTemplates.commonPartnerID(for: id), hoveredPointID == partnerID {
            return true
        }
        return false
    }

    private func isPointOrPartnerDragged(_ id: String) -> Bool {
        if draggedPointID == id { return true }
        if jointCommonPoints, let partnerID = CalibrationPointTemplates.commonPartnerID(for: id), draggedPointID == partnerID {
            return true
        }
        return false
    }

    private func pointDisplayName(for point: CalibrationPoint) -> String {
        if jointCommonPoints {
            if point.id == "mw_bl" || point.id == "kb_tl" {
                return "Seam Left (MW BL + KB TL)"
            } else if point.id == "mw_br" || point.id == "kb_tr" {
                return "Seam Right (MW BR + KB TR)"
            }
        }
        return point.label
    }

    private func pointMarkerBadgeLabel(for point: CalibrationPoint) -> String {
        if jointCommonPoints {
            if point.id == "mw_bl" || point.id == "kb_tl" {
                return "Seam Left (MW BL / KB TL)"
            } else if point.id == "mw_br" || point.id == "kb_tr" {
                return "Seam Right (MW BR / KB TR)"
            }
        }
        return point.label
    }

    private func shouldHideDuplicateBadge(for point: CalibrationPoint) -> Bool {
        guard jointCommonPoints else { return false }
        if point.id == "kb_tl" || point.id == "kb_tr" {
            if let partnerID = CalibrationPointTemplates.commonPartnerID(for: point.id),
               let partner = editedPoints.first(where: { $0.id == partnerID }),
               partner.xPx == point.xPx && partner.yPx == point.yPx {
                return true
            }
        }
        return false
    }

    private func syncCommonPointsIfNeeded() {
        guard jointCommonPoints else { return }

        // Sync Left seam (mw_bl + kb_tl)
        if let mwBL = editedPoints.first(where: { $0.id == "mw_bl" }),
           let kbTLIdx = editedPoints.firstIndex(where: { $0.id == "kb_tl" }) {
            if selectedPointID == "kb_tl" {
                if let mwBLIdx = editedPoints.firstIndex(where: { $0.id == "mw_bl" }) {
                    editedPoints[mwBLIdx].xPx = editedPoints[kbTLIdx].xPx
                    editedPoints[mwBLIdx].yPx = editedPoints[kbTLIdx].yPx
                }
            } else {
                editedPoints[kbTLIdx].xPx = mwBL.xPx
                editedPoints[kbTLIdx].yPx = mwBL.yPx
            }
        }

        // Sync Right seam (mw_br + kb_tr)
        if let mwBR = editedPoints.first(where: { $0.id == "mw_br" }),
           let kbTRIdx = editedPoints.firstIndex(where: { $0.id == "kb_tr" }) {
            if selectedPointID == "kb_tr" {
                if let mwBRIdx = editedPoints.firstIndex(where: { $0.id == "mw_br" }) {
                    editedPoints[mwBRIdx].xPx = editedPoints[kbTRIdx].xPx
                    editedPoints[mwBRIdx].yPx = editedPoints[kbTRIdx].yPx
                }
            } else {
                editedPoints[kbTRIdx].xPx = mwBR.xPx
                editedPoints[kbTRIdx].yPx = mwBR.yPx
            }
        }
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
                title: pointDisplayName(for: point),
                subtitle: "X: \(Int(round(point.xPx))), Y: \(Int(round(point.yPx))) px",
                anchor: pos
            )
        }

        // Priority 2: Point handle being hovered
        if let point = editedPoints.first(where: { $0.id == hoveredPointID }) {
            let pos = pointScreenPos(point: point, scale: scale, offsetX: offsetX, offsetY: offsetY, displayedHeight: displayedHeight)
            return LoupeDisplayInfo(
                title: pointDisplayName(for: point),
                subtitle: "X: \(Int(round(point.xPx))), Y: \(Int(round(point.yPx))) px",
                anchor: pos
            )
        }

        // Priority 3: Hovering cursor over photo background (outside calibration points)
        if let cursorLoc = hoveredCursorLocation, let cursorPx = hoveredCursorPx {
            return LoupeDisplayInfo(
                title: "Photo",
                subtitle: "X: \(Int(round(cursorPx.x))), Y: \(Int(round(cursorPx.y))) px",
                anchor: cursorLoc
            )
        }

        // Priority 4: Active fine-nudge on selected point (via keyboard arrows or nudge bar)
        if isNudgingActive, let point = selectedPoint {
            let pos = pointScreenPos(point: point, scale: scale, offsetX: offsetX, offsetY: offsetY, displayedHeight: displayedHeight)
            return LoupeDisplayInfo(
                title: pointDisplayName(for: point),
                subtitle: "X: \(Int(round(point.xPx))), Y: \(Int(round(point.yPx))) px",
                anchor: pos
            )
        }

        return nil
    }

    private func closestPoint(
        near screenPoint: CGPoint,
        in points: [CalibrationPoint],
        scale: CGFloat,
        offsetX: CGFloat,
        offsetY: CGFloat,
        displayedHeight: CGFloat,
        maxScreenDistance: CGFloat = 28.0
    ) -> (point: CalibrationPoint, distance: CGFloat)? {
        var closest: CalibrationPoint? = nil
        var minDistance = maxScreenDistance

        for pt in points {
            let ptScreen = pointScreenPos(
                point: pt,
                scale: scale,
                offsetX: offsetX,
                offsetY: offsetY,
                displayedHeight: displayedHeight
            )
            let dist = hypot(screenPoint.x - ptScreen.x, screenPoint.y - ptScreen.y)
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

            // Joint common points toggle button
            Button {
                jointCommonPoints.toggle()
                if jointCommonPoints {
                    syncCommonPointsIfNeeded()
                    if let selected = selectedPoint {
                        updateCrop(xPx: selected.xPx, yPx: selected.yPx, cgImage: cgImage)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: jointCommonPoints ? "checkmark.square.fill" : "square")
                        .font(.caption)
                        .foregroundStyle(jointCommonPoints ? Color.accentColor : Color.secondary)
                    Image(systemName: "link")
                        .font(.caption2)
                    Text("Joint Seam")
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(jointCommonPoints ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Joint moving kickboard & main wall common points (mw_bl ↔ kb_tl, mw_br ↔ kb_tr)")

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

    private func handleContinuousHover(
        at location: CGPoint,
        scale: CGFloat,
        offsetX: CGFloat,
        offsetY: CGFloat,
        displayedHeight: CGFloat,
        imageSize: CGSize,
        cgImage: CGImage
    ) {
        // While dragging a point, dragging logic manages crop and position
        guard draggedPointID == nil else { return }
        isNudgingActive = false

        // Check if mouse is hovering near one of the 8 calibration points
        if let match = closestPoint(
            near: location,
            in: editedPoints,
            scale: scale,
            offsetX: offsetX,
            offsetY: offsetY,
            displayedHeight: displayedHeight,
            maxScreenDistance: 24.0
        ) {
            hoveredPointID = match.point.id
            hoveredCursorLocation = nil
            hoveredCursorPx = nil
            updateCrop(xPx: match.point.xPx, yPx: match.point.yPx, cgImage: cgImage)
            return
        }

        // Mouse is outside all rectification points -> hover over raw photo
        hoveredPointID = nil

        let pxX = (location.x - offsetX) / scale
        let pxY = (offsetY + displayedHeight - location.y) / scale

        // Allow hovering slightly past edges (within 60px of photo boundary) so corner inspection is comfortable
        let padding: CGFloat = 60.0
        if pxX >= -padding, pxX <= imageSize.width + padding,
           pxY >= -padding, pxY <= imageSize.height + padding {
            let clampedPxX = max(0, min(imageSize.width, pxX))
            let clampedPxY = max(0, min(imageSize.height, pxY))
            hoveredCursorLocation = location
            hoveredCursorPx = CGPoint(x: clampedPxX, y: clampedPxY)
            updateCrop(xPx: pxX, yPx: pxY, cgImage: cgImage)
        } else {
            hoveredCursorLocation = nil
            hoveredCursorPx = nil
            loupeCropCGImage = nil
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

        isNudgingActive = true
        hoveredCursorLocation = nil
        hoveredCursorPx = nil
        hoveredPointID = nil

        let newX = round(max(0, min(Double(imageSize.width), editedPoints[idx].xPx + dx)))
        let newY = round(max(0, min(Double(imageSize.height), editedPoints[idx].yPx + dy)))

        editedPoints[idx].xPx = newX
        editedPoints[idx].yPx = newY

        // If joint common points is enabled, sync partner point
        if jointCommonPoints,
           let partnerID = CalibrationPointTemplates.commonPartnerID(for: id),
           let partnerIdx = editedPoints.firstIndex(where: { $0.id == partnerID }) {
            editedPoints[partnerIdx].xPx = newX
            editedPoints[partnerIdx].yPx = newY
        }

        updateCrop(xPx: newX, yPx: newY, cgImage: cgImage)
    }

    private func selectPoint(id: String, cgImage: CGImage) {
        selectedPointID = id
        isNudgingActive = true
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
        loupeCropCGImage = HoldBackwardTransformService.cropPhotoPixel(
            from: cgImage,
            xPx: xPx,
            yPx: yPx,
            cropSpan: loupeConfig.cropPixelSpan
        )
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
        if jointCommonPoints {
            syncCommonPointsIfNeeded()
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

                if self.jointCommonPoints {
                    self.syncCommonPointsIfNeeded()
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

private struct PointMarkerVisualView: View {
    let point: CalibrationPoint
    let screenPos: CGPoint
    let isSelected: Bool
    let isHovered: Bool
    let isDragged: Bool
    let isJointLinked: Bool
    let displayLabel: String
    let hideBadge: Bool
    let zoomScale: CGFloat

    var body: some View {
        let isKickboard = point.id.hasPrefix("kb")
        let baseColor = isKickboard ? Color.orange : Color.cyan
        let isHighlighted = isSelected || isHovered || isDragged

        ZStack(alignment: .center) {
            // Glowing outer accent ring if selected or hovered or dragged
            if isHighlighted {
                Circle()
                    .stroke(isSelected ? Color.yellow : (isJointLinked ? Color.green : baseColor), lineWidth: 2.5)
                    .frame(width: 34, height: 34)
                    .shadow(color: (isSelected ? Color.yellow : (isJointLinked ? Color.green : baseColor)).opacity(0.8), radius: 4)
            }

            // Main handle circle
            if isJointLinked {
                // Dual-color gradient for linked kickboard & main wall common seam point
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color.cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(isHighlighted ? 0.95 : 0.75)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
            } else {
                Circle()
                    .fill(baseColor.opacity(isHighlighted ? 0.92 : 0.65))
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
            }

            // Center targeting red dot
            Circle()
                .fill(Color.red)
                .frame(width: 4, height: 4)

            // Label badge
            if !hideBadge {
                HStack(spacing: 3) {
                    if isJointLinked {
                        Image(systemName: "link")
                            .font(.system(size: 8, weight: .bold))
                    }
                    Text(displayLabel)
                        .font(.system(size: 9, weight: .bold))
                        .fixedSize()
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(isHighlighted ? 0.90 : 0.70))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .offset(y: -22)
            }
        }
        .scaleEffect(1.0 / max(1.0, sqrt(zoomScale)))
        .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
        .position(screenPos)
    }
}
