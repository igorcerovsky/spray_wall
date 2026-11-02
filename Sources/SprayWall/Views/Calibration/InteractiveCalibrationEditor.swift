import CoreGraphics
import CoreImage
import ImageIO
import SwiftUI

/// High-precision interactive calibration and rectification editor.
/// Allows fine-tuning the 8 corner points defining the kickboard and main wall planes
/// on the raw unwarped photo with a real-time floating magnifying loupe, focal zoom,
/// panning, and single-pixel nudge controls.
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
    @State private var dragStartPointPx: CGPoint? = nil
    @State private var dragStartPanOffset: CGSize? = nil
    @State private var currentScreenAnchor: CGPoint? = nil

    // Zoom & Pan state
    @State private var zoomScale: CGFloat = 1.0
    @State private var baseZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero

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
                        let viewportSize = geo.size
                        let transform = CalibrationZoomTransform(
                            imageSize: imageSize,
                            viewportSize: viewportSize,
                            zoomScale: zoomScale,
                            panOffset: panOffset
                        )

                        ZStack {
                            // Layer 1: Background & Scaled Photo Canvas
                            Color.black.ignoresSafeArea()

                            canvasContent(
                                cgImage: cgImage,
                                imageSize: imageSize,
                                transform: transform
                            )
                            .frame(width: transform.fittedSize.width, height: transform.fittedSize.height)
                            .scaleEffect(zoomScale, anchor: .center)
                            .offset(panOffset)
                            .allowsHitTesting(false) // Viewport gestures handle all interactions

                            // Layer 2: Floating Magnifying Loupe
                            if loupeConfig.isEnabled, let activePoint = currentActivePoint {
                                let anchorScreenPt = transform.photoPxToViewport(xPx: activePoint.xPx, yPx: activePoint.yPx)
                                let loupePos = WallZoomTransform.computeLoupePosition(
                                    anchorPoint: currentScreenAnchor ?? anchorScreenPt,
                                    loupeConfig: loupeConfig,
                                    viewportSize: viewportSize
                                )

                                HoldLoupeView(
                                    croppedImage: loupeCropCGImage,
                                    title: activePoint.label,
                                    subtitle: "X: \(Int(round(activePoint.xPx))), Y: \(Int(round(activePoint.yPx))) px • (\(Int(activePoint.xCm)), \(Int(activePoint.yCm))) cm",
                                    config: loupeConfig
                                )
                                .position(loupePos)
                                .transition(.scale(scale: 0.85).combined(with: .opacity))
                                .allowsHitTesting(false)
                            }

                            // Layer 3: Bottom Fine-Nudge Bar
                            if let selected = selectedPoint {
                                VStack {
                                    Spacer()
                                    fineNudgeBar(
                                        point: selected,
                                        imageSize: imageSize,
                                        cgImage: cgImage,
                                        transform: transform
                                    )
                                    .padding(.bottom, 12)
                                }
                            }
                        }
                        .frame(width: viewportSize.width, height: viewportSize.height)
                        .clipped()
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { value in
                                    handleCanvasTap(
                                        at: value.location,
                                        transform: transform,
                                        cgImage: cgImage
                                    )
                                }
                        )
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 3)
                                .onChanged { value in
                                    handleDragChanged(
                                        value: value,
                                        transform: transform,
                                        imageSize: imageSize,
                                        cgImage: cgImage,
                                        viewportSize: viewportSize
                                    )
                                }
                                .onEnded { value in
                                    handleDragEnded(
                                        value: value,
                                        transform: transform,
                                        imageSize: imageSize,
                                        cgImage: cgImage
                                    )
                                }
                        )
                        .simultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let targetScale = min(5.0, max(1.0, baseZoomScale * value))
                                    zoomScale = targetScale
                                    if zoomScale <= 1.0 {
                                        panOffset = .zero
                                    } else {
                                        panOffset = CalibrationZoomTransform.clampedOffset(
                                            panOffset,
                                            fittedSize: transform.fittedSize,
                                            viewportSize: viewportSize,
                                            scale: zoomScale
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    baseZoomScale = zoomScale
                                }
                        )
                        .onContinuousHover(coordinateSpace: .local) { phase in
                            switch phase {
                            case let .active(viewportPoint):
                                handleMouseHover(
                                    at: viewportPoint,
                                    transform: transform,
                                    cgImage: cgImage
                                )
                            case .ended:
                                handleMouseExited()
                            }
                        }
                        #if os(macOS)
                        .background(
                            ScrollWheelZoomModifier { delta, mouseLocation in
                                if let result = CalibrationZoomTransform.focalZoom(
                                    delta: delta,
                                    mouseLocation: mouseLocation,
                                    currentScale: zoomScale,
                                    currentOffset: panOffset,
                                    fittedSize: transform.fittedSize,
                                    viewportSize: viewportSize
                                ) {
                                    zoomScale = result.newScale
                                    baseZoomScale = result.newScale
                                    panOffset = result.newOffset
                                }
                            }
                        )
                        .focusable()
                        .focusEffectDisabled()
                        .onKeyPress { press in
                            handleKeyPress(
                                press: press,
                                imageSize: imageSize,
                                cgImage: cgImage,
                                transform: transform
                            )
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

    private var currentActivePoint: CalibrationPoint? {
        if let draggedPointID {
            return editedPoints.first(where: { $0.id == draggedPointID })
        }
        if let hoveredPointID {
            return editedPoints.first(where: { $0.id == hoveredPointID })
        }
        if let selectedPointID {
            return editedPoints.first(where: { $0.id == selectedPointID })
        }
        return nil
    }

    // MARK: - Canvas Rendering

    @ViewBuilder
    private func canvasContent(
        cgImage: CGImage,
        imageSize: CGSize,
        transform: CalibrationZoomTransform
    ) -> some View {
        ZStack(alignment: .topLeading) {
            // Unwarped native photo
            Image(decorative: cgImage, scale: 1.0)
                .resizable()
                .scaledToFit()
                .frame(width: transform.fittedSize.width, height: transform.fittedSize.height)

            // Wall plane quadrilateral outlines
            wallPlanePolygons(transform: transform)

            // Calibration point markers
            ForEach(editedPoints) { point in
                let canvasPos = transform.photoPxToCanvas(xPx: point.xPx, yPx: point.yPx)
                let isSelected = selectedPointID == point.id
                let isHovered = hoveredPointID == point.id
                let isDragged = draggedPointID == point.id
                let isKickboard = point.id.hasPrefix("kb")

                CalibrationMarkerDotView(
                    point: point,
                    isKickboard: isKickboard,
                    isSelected: isSelected,
                    isHovered: isHovered,
                    isDragged: isDragged,
                    zoomScale: zoomScale
                )
                .position(canvasPos)
            }
        }
    }

    @ViewBuilder
    private func wallPlanePolygons(transform: CalibrationZoomTransform) -> some View {
        let lookup = Dictionary(uniqueKeysWithValues: editedPoints.map { ($0.id, $0) })

        // Kickboard quad (kb_bl -> kb_br -> kb_tr -> kb_tl)
        if let bl = lookup["kb_bl"], let br = lookup["kb_br"],
           let tr = lookup["kb_tr"], let tl = lookup["kb_tl"] {
            let quad = QuadPolygonShape(
                p0: transform.photoPxToCanvas(xPx: bl.xPx, yPx: bl.yPx),
                p1: transform.photoPxToCanvas(xPx: br.xPx, yPx: br.yPx),
                p2: transform.photoPxToCanvas(xPx: tr.xPx, yPx: tr.yPx),
                p3: transform.photoPxToCanvas(xPx: tl.xPx, yPx: tl.yPx)
            )
            quad.fill(Color.orange.opacity(0.12))
            quad.stroke(Color.orange.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }

        // Main Wall quad (mw_bl -> mw_br -> mw_tr -> mw_tl)
        if let bl = lookup["mw_bl"], let br = lookup["mw_br"],
           let tr = lookup["mw_tr"], let tl = lookup["mw_tl"] {
            let quad = QuadPolygonShape(
                p0: transform.photoPxToCanvas(xPx: bl.xPx, yPx: bl.yPx),
                p1: transform.photoPxToCanvas(xPx: br.xPx, yPx: br.yPx),
                p2: transform.photoPxToCanvas(xPx: tr.xPx, yPx: tr.yPx),
                p3: transform.photoPxToCanvas(xPx: tl.xPx, yPx: tl.yPx)
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
        cgImage: CGImage,
        transform: CalibrationZoomTransform
    ) -> some View {
        HStack(spacing: 10) {
            // Point selector menu
            Menu {
                ForEach(editedPoints) { pt in
                    Button {
                        selectPoint(id: pt.id, transform: transform, cgImage: cgImage)
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
                    cyclePoint(forward: false, transform: transform, cgImage: cgImage)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption2.weight(.bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Previous Point (Shift+Tab)")

                Button {
                    cyclePoint(forward: true, transform: transform, cgImage: cgImage)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Next Point (Tab)")
            }

            Divider().frame(height: 18)

            // X-Axis Nudge Buttons
            HStack(spacing: 4) {
                Text("X: \(Int(round(point.xPx)))")
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 64, alignment: .leading)

                nudgeButton(label: "-10", dx: -10, dy: 0, imageSize: imageSize, cgImage: cgImage, transform: transform)
                nudgeButton(label: "-1", dx: -1, dy: 0, imageSize: imageSize, cgImage: cgImage, transform: transform)
                nudgeButton(label: "+1", dx: 1, dy: 0, imageSize: imageSize, cgImage: cgImage, transform: transform)
                nudgeButton(label: "+10", dx: 10, dy: 0, imageSize: imageSize, cgImage: cgImage, transform: transform)
            }

            Divider().frame(height: 18)

            // Y-Axis Nudge Buttons
            HStack(spacing: 4) {
                Text("Y: \(Int(round(point.yPx)))")
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 64, alignment: .leading)

                nudgeButton(label: "-10", dx: 0, dy: -10, imageSize: imageSize, cgImage: cgImage, transform: transform)
                nudgeButton(label: "-1", dx: 0, dy: -1, imageSize: imageSize, cgImage: cgImage, transform: transform)
                nudgeButton(label: "+1", dx: 0, dy: 1, imageSize: imageSize, cgImage: cgImage, transform: transform)
                nudgeButton(label: "+10", dx: 0, dy: 10, imageSize: imageSize, cgImage: cgImage, transform: transform)
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
        cgImage: CGImage,
        transform: CalibrationZoomTransform
    ) -> some View {
        Button(label) {
            nudgeSelected(
                dx: dx,
                dy: dy,
                imageSize: imageSize,
                cgImage: cgImage,
                transform: transform
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .font(.caption2.monospacedDigit())
    }

    // MARK: - Interaction Handlers

    private func handleCanvasTap(
        at location: CGPoint,
        transform: CalibrationZoomTransform,
        cgImage: CGImage
    ) {
        if let match = transform.closestPoint(near: location, in: editedPoints, maxScreenDistance: 32.0) {
            selectPoint(id: match.point.id, transform: transform, cgImage: cgImage)
        } else {
            // Tapping empty background deselects
            selectedPointID = nil
            currentScreenAnchor = nil
            loupeCropCGImage = nil
        }
    }

    private func handleDragChanged(
        value: DragGesture.Value,
        transform: CalibrationZoomTransform,
        imageSize: CGSize,
        cgImage: CGImage,
        viewportSize: CGSize
    ) {
        // Start dragging
        if draggedPointID == nil && dragStartPanOffset == nil {
            if let match = transform.closestPoint(near: value.startLocation, in: editedPoints, maxScreenDistance: 30.0) {
                draggedPointID = match.point.id
                selectedPointID = match.point.id
                dragStartPointPx = CGPoint(x: match.point.xPx, y: match.point.yPx)
            } else if zoomScale > 1.0 {
                dragStartPanOffset = panOffset
            }
        }

        if let pointID = draggedPointID, let startPx = dragStartPointPx {
            // Convert translation from screen viewport points to raw photo pixels
            let pxPerViewportPt = (imageSize.width / transform.fittedSize.width) / zoomScale
            let deltaXPx = Double(value.translation.width * pxPerViewportPt)
            let deltaYPx = Double(-value.translation.height * pxPerViewportPt) // CoreImage Y is inverted

            let newXPx = round(min(Double(imageSize.width), max(0, startPx.x + deltaXPx)))
            let newYPx = round(min(Double(imageSize.height), max(0, startPx.y + deltaYPx)))

            if let idx = editedPoints.firstIndex(where: { $0.id == pointID }) {
                editedPoints[idx].xPx = newXPx
                editedPoints[idx].yPx = newYPx

                let pt = editedPoints[idx]
                currentScreenAnchor = transform.photoPxToViewport(xPx: pt.xPx, yPx: pt.yPx)
                updateCrop(for: pt, cgImage: cgImage)
            }
        } else if let startPan = dragStartPanOffset {
            let candidate = CGSize(
                width: startPan.width + value.translation.width,
                height: startPan.height + value.translation.height
            )
            panOffset = CalibrationZoomTransform.clampedOffset(
                candidate,
                fittedSize: transform.fittedSize,
                viewportSize: viewportSize,
                scale: zoomScale
            )
        }
    }

    private func handleDragEnded(
        value: DragGesture.Value,
        transform: CalibrationZoomTransform,
        imageSize: CGSize,
        cgImage: CGImage
    ) {
        if let pointID = draggedPointID,
           let pt = editedPoints.first(where: { $0.id == pointID }) {
            currentScreenAnchor = transform.photoPxToViewport(xPx: pt.xPx, yPx: pt.yPx)
            updateCrop(for: pt, cgImage: cgImage)
        }
        draggedPointID = nil
        dragStartPointPx = nil
        dragStartPanOffset = nil
    }

    private func handleMouseHover(
        at viewportPoint: CGPoint,
        transform: CalibrationZoomTransform,
        cgImage: CGImage
    ) {
        guard draggedPointID == nil else { return }

        if let match = transform.closestPoint(near: viewportPoint, in: editedPoints, maxScreenDistance: 28.0) {
            hoveredPointID = match.point.id
            currentScreenAnchor = transform.photoPxToViewport(xPx: match.point.xPx, yPx: match.point.yPx)
            updateCrop(for: match.point, cgImage: cgImage)
        } else {
            hoveredPointID = nil
            if let selected = selectedPoint {
                currentScreenAnchor = transform.photoPxToViewport(xPx: selected.xPx, yPx: selected.yPx)
                updateCrop(for: selected, cgImage: cgImage)
            } else {
                currentScreenAnchor = nil
                loupeCropCGImage = nil
            }
        }
    }

    private func handleMouseExited() {
        guard draggedPointID == nil else { return }
        hoveredPointID = nil
        if let selected = selectedPoint {
            // Keep selected point cropped in loupe
            if case let .loaded(cgImage, _) = loadState {
                updateCrop(for: selected, cgImage: cgImage)
            }
        } else {
            currentScreenAnchor = nil
            loupeCropCGImage = nil
        }
    }

    #if os(macOS)
    private func handleKeyPress(
        press: KeyPress,
        imageSize: CGSize,
        cgImage: CGImage,
        transform: CalibrationZoomTransform
    ) -> KeyPress.Result {
        guard selectedPointID != nil else { return .ignored }

        let step: Double = press.modifiers.contains(.shift) ? 10.0 : 1.0

        switch press.key {
        case .leftArrow:
            nudgeSelected(dx: -step, dy: 0, imageSize: imageSize, cgImage: cgImage, transform: transform)
            return .handled
        case .rightArrow:
            nudgeSelected(dx: step, dy: 0, imageSize: imageSize, cgImage: cgImage, transform: transform)
            return .handled
        case .upArrow:
            nudgeSelected(dx: 0, dy: step, imageSize: imageSize, cgImage: cgImage, transform: transform)
            return .handled
        case .downArrow:
            nudgeSelected(dx: 0, dy: -step, imageSize: imageSize, cgImage: cgImage, transform: transform)
            return .handled
        case .tab:
            cyclePoint(forward: !press.modifiers.contains(.shift), transform: transform, cgImage: cgImage)
            return .handled
        case .escape:
            selectedPointID = nil
            currentScreenAnchor = nil
            loupeCropCGImage = nil
            return .handled
        default:
            return .ignored
        }
    }
    #endif

    private func nudgeSelected(
        dx: Double,
        dy: Double,
        imageSize: CGSize,
        cgImage: CGImage,
        transform: CalibrationZoomTransform
    ) {
        guard let id = selectedPointID,
              let idx = editedPoints.firstIndex(where: { $0.id == id }) else { return }

        let newX = round(min(Double(imageSize.width), max(0, editedPoints[idx].xPx + dx)))
        let newY = round(min(Double(imageSize.height), max(0, editedPoints[idx].yPx + dy)))

        editedPoints[idx].xPx = newX
        editedPoints[idx].yPx = newY

        let pt = editedPoints[idx]
        currentScreenAnchor = transform.photoPxToViewport(xPx: pt.xPx, yPx: pt.yPx)
        updateCrop(for: pt, cgImage: cgImage)
    }

    private func selectPoint(
        id: String,
        transform: CalibrationZoomTransform,
        cgImage: CGImage
    ) {
        selectedPointID = id
        if let pt = editedPoints.first(where: { $0.id == id }) {
            currentScreenAnchor = transform.photoPxToViewport(xPx: pt.xPx, yPx: pt.yPx)
            updateCrop(for: pt, cgImage: cgImage)
        }
    }

    private func cyclePoint(
        forward: Bool,
        transform: CalibrationZoomTransform,
        cgImage: CGImage
    ) {
        guard !editedPoints.isEmpty else { return }
        let currentIndex = editedPoints.firstIndex(where: { $0.id == selectedPointID }) ?? 0
        let nextIndex: Int
        if forward {
            nextIndex = (currentIndex + 1) % editedPoints.count
        } else {
            nextIndex = (currentIndex - 1 + editedPoints.count) % editedPoints.count
        }
        let nextPoint = editedPoints[nextIndex]
        selectPoint(id: nextPoint.id, transform: transform, cgImage: cgImage)
    }

    private func updateCrop(for point: CalibrationPoint, cgImage: CGImage) {
        guard loupeConfig.isEnabled else {
            loupeCropCGImage = nil
            return
        }
        loupeCropCGImage = HoldBackwardTransformService.cropPhotoPixel(
            from: cgImage,
            xPx: point.xPx,
            yPx: point.yPx,
            cropSpan: loupeConfig.cropPixelSpan
        )
    }

    private func resetToDefaults() {
        let defaults = CalibrationPointTemplates.all
        let byID = Dictionary(uniqueKeysWithValues: defaults.map { ($0.id, $0) })
        for idx in editedPoints.indices {
            if let def = byID[editedPoints[idx].id] {
                editedPoints[idx].xPx = def.xPx
                editedPoints[idx].yPx = def.yPx
            }
        }
        if case let .loaded(cgImage, imageSize) = loadState,
           let selected = selectedPoint {
            let transform = CalibrationZoomTransform(
                imageSize: imageSize,
                viewportSize: CGSize(width: 800, height: 600),
                zoomScale: zoomScale,
                panOffset: panOffset
            )
            updateCrop(for: selected, cgImage: cgImage)
            currentScreenAnchor = transform.photoPxToViewport(xPx: selected.xPx, yPx: selected.yPx)
        }
    }

    // MARK: - Loading

    private func load() {
        editedPoints = points

        // Default selected point to mw_tl if available, or first point
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
                    self.updateCrop(for: selected, cgImage: image)
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

private struct CalibrationMarkerDotView: View {
    let point: CalibrationPoint
    let isKickboard: Bool
    let isSelected: Bool
    let isHovered: Bool
    let isDragged: Bool
    let zoomScale: CGFloat

    var body: some View {
        let accentColor = isKickboard ? Color.orange : Color.cyan
        let isHighlighted = isSelected || isHovered || isDragged

        ZStack(alignment: .center) {
            // Outer glowing accent ring if selected or dragged
            if isSelected || isDragged {
                Circle()
                    .stroke(Color.yellow, lineWidth: 2.5)
                    .frame(width: 32, height: 32)
                    .shadow(color: Color.yellow.opacity(0.8), radius: 4)
            } else if isHovered {
                Circle()
                    .stroke(accentColor, lineWidth: 2)
                    .frame(width: 28, height: 28)
            }

            // Main handle circle
            Circle()
                .fill(accentColor.opacity(isHighlighted ? 0.85 : 0.65))
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))

            // Center targeting cross-dot
            Circle()
                .fill(Color.red)
                .frame(width: 4, height: 4)

            // Point Label Badge
            Text(point.label)
                .font(.system(size: 9, weight: .bold))
                .fixedSize()
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(isHighlighted ? 0.88 : 0.68))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .offset(y: -18)
        }
        .scaleEffect(1.0 / max(1.0, sqrt(zoomScale)))
        .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
    }
}
