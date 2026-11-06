import SwiftData
import SwiftUI

struct HoldEditorView: View {
    private static let adminEmail = "igor.cerovsky@gmail.com"
    private static let persistedEmailKey = "spraywall.last_logged_in_email"

    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var appModel
    @Query(sort: \WallCalibration.updatedAt, order: .reverse) private var calibrations: [WallCalibration]

    @State private var showHoldList = false
    @State private var isEditingHolds = false
    @State private var showDeleteAllConfirmation = false
    @State private var inlineStatusMessage: String?
    @State private var holds: [Hold] = []

    // Zoom & Pan state
    @State private var zoomScale: CGFloat = 1.0
    @State private var baseZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize? = nil

    // Loupe preview & selection state
    @State private var loupeConfig = HoldLoupeConfig.defaultCircle
    @State private var hoveredHold: Hold?
    @State private var selectedHoldID: Int?
    @State private var activeDragAction: HoldDragAction?
    @State private var activeCropCGImage: CGImage?
    @State private var croppedHoldID: Int? = nil
    @State private var croppedHoldCoord: CGPoint? = nil
    @State private var originalPhotoCGImage: CGImage?
    @State private var currentMouseLocation: CGPoint? = nil
    @State private var isShiftPressed: Bool = false

    private var isShiftActive: Bool {
        #if os(macOS)
        return isShiftPressed || NSEvent.modifierFlags.contains(.shift)
        #else
        return isShiftPressed
        #endif
    }

    private var activeDragHoldID: Int? {
        guard let action = activeDragAction else { return nil }
        switch action {
        case let .move(id), let .resizeMajor(id), let .resizeMinor(id), let .rotate(id):
            return id
        case .pan:
            return nil
        }
    }

    private var activeHoldForLoupe: Hold? {
        if let dragID = activeDragHoldID, let hold = holds.first(where: { $0.holdID == dragID }) {
            return hold
        }
        if isEditingHolds, let selID = selectedHoldID, let hold = holds.first(where: { $0.holdID == selID }) {
            return hold
        }
        if let hovered = hoveredHold {
            return hovered
        }
        if let selID = selectedHoldID, let hold = holds.first(where: { $0.holdID == selID }) {
            return hold
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                controls

                zoomableWallPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let inlineStatusMessage, !inlineStatusMessage.isEmpty {
                    Text(inlineStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(inlineStatusMessage.contains("failed") || inlineStatusMessage.contains("Only admin") ? .red : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                DisclosureGroup("Holds (\(holds.count))", isExpanded: $showHoldList) {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(holds) { hold in
                                HStack {
                                    Text("#\(hold.holdID)")
                                        .font(.headline.monospacedDigit())
                                    Text("\(Int(hold.xCm)), \(Int(hold.yCm)) cm")
                                        .font(.subheadline)
                                    Spacer()
                                    Text(hold.plane.rawValue.capitalized)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
                .padding(.horizontal, 4)
            }
            .padding()
            .navigationTitle("Hold Positions")
            .task {
                fetchHolds()
                loadOriginalPhoto()
            }
            .onChange(of: calibrations) { _, _ in
                loadOriginalPhoto()
            }
            #if os(macOS)
            .onAppear {
                NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                    isShiftPressed = event.modifierFlags.contains(.shift)
                    return event
                }
            }
            #endif
            .confirmationDialog(
                "Delete All Holds?",
                isPresented: $showDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete all and reset counter", role: .destructive) {
                    deleteAllHoldsAndResetCounter()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all \(holds.count) holds from the wall and reset the hold ID counter back to 1. This action cannot be undone.")
            }
        }
    }

    // MARK: - Zoomable Wall View with Exact Transformations & Loupe

    private var zoomableWallPreview: some View {
        GeometryReader { geometry in
            let viewportSize = geometry.size
            let fittedSize = WallZoomTransform.computeFittedSize(in: viewportSize)
            let zoomTransform = WallZoomTransform(
                fittedSize: fittedSize,
                viewportSize: viewportSize,
                zoomScale: zoomScale,
                panOffset: panOffset
            )

            ZStack {
                Color.clear

                // Wall Canvas rendered with zoom scale and pan shift
                ZStack {
                    WallBackgroundView(size: fittedSize)

                    // Visual hold markers rendered on the canvas
                    ForEach(holds) { hold in
                        let isHovered = (hoveredHold?.holdID == hold.holdID) || (activeDragHoldID == hold.holdID)
                        let isSelected = selectedHoldID == hold.holdID
                        let markerPos = zoomTransform.worldCmToWall(xCm: hold.xCm, yCm: hold.yCm)
                        let holdWidthWall = max(6.0, CGFloat(hold.majorCm) * (fittedSize.width / CGFloat(WallSpec.widthCm)))
                        let holdHeightWall = max(6.0, CGFloat(hold.minorCm) * (fittedSize.height / CGFloat(WallSpec.totalHeightCm)))

                        HoldPositionDotView(
                            holdID: hold.holdID,
                            widthPt: holdWidthWall,
                            heightPt: holdHeightWall,
                            rotationDeg: hold.rotationDeg,
                            zoomScale: zoomScale,
                            isHovered: isHovered,
                            isSelected: isSelected,
                            isEditing: isEditingHolds,
                            isShiftPressed: isShiftActive
                        )
                        .position(markerPos)
                        .allowsHitTesting(false)
                    }
                }
                .frame(width: fittedSize.width, height: fittedSize.height)
                .scaleEffect(zoomScale, anchor: .center)
                .offset(panOffset)
                .allowsHitTesting(false) // Let the outer viewport handle all mouse interaction using the transformation matrix

                // Floating Loupe Preview
                if loupeConfig.isEnabled, let activeHold = activeHoldForLoupe {
                    let anchorScreenPt = zoomTransform.worldCmToViewport(xCm: activeHold.xCm, yCm: activeHold.yCm)
                    let loupePosition: CGPoint = {
                        if isEditingHolds && (selectedHoldID != nil || activeDragAction != nil) {
                            return WallZoomTransform.computeEditingLoupePosition(
                                holdScreenPoint: anchorScreenPt,
                                loupeConfig: loupeConfig,
                                viewportSize: viewportSize,
                                fittedSize: fittedSize,
                                zoomScale: zoomScale,
                                panOffset: panOffset
                            )
                        } else {
                            return WallZoomTransform.computeLoupePosition(
                                anchorPoint: currentMouseLocation ?? anchorScreenPt,
                                loupeConfig: loupeConfig,
                                viewportSize: viewportSize
                            )
                        }
                    }()

                    HoldLoupeView(
                        croppedImage: activeCropCGImage,
                        hold: activeHold,
                        calibrationPoints: activeCalibrationPoints,
                        config: loupeConfig,
                        showCoordinates: true
                    )
                    .position(loupePosition)
                    .animation(.spring(response: 0.25, dampingFraction: 0.85), value: loupePosition)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .allowsHitTesting(false)
                }
            }
            .frame(width: viewportSize.width, height: viewportSize.height)
            .clipped()
            .contentShape(Rectangle())
            .contextMenu {
                let contextHold = hoveredHold ?? (selectedHoldID != nil ? holds.first(where: { $0.holdID == selectedHoldID }) : nil)
                if isEditingHolds, canEditWallLayout, let hold = contextHold {
                    Button("Delete Hold #\(hold.holdID)", role: .destructive) {
                        delete(hold: hold)
                    }
                }
            }
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        handleCanvasTap(at: value.location, zoomTransform: zoomTransform)
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        handleDragChanged(
                            value: value,
                            zoomTransform: zoomTransform,
                            fittedSize: fittedSize,
                            viewportSize: viewportSize
                        )
                    }
                    .onEnded { value in
                        handleDragEnded(value: value, zoomTransform: zoomTransform)
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
                            panOffset = WallZoomTransform.clampedOffset(
                                panOffset,
                                fittedSize: fittedSize,
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
                    handleMouseHover(at: viewportPoint, zoomTransform: zoomTransform)
                case .ended:
                    handleMouseExited()
                }
            }
            #if os(macOS)
            .background(
                ScrollWheelZoomModifier { delta, mouseLocation in
                    if let result = WallZoomTransform.focalZoom(
                        delta: delta,
                        mouseLocation: mouseLocation,
                        currentScale: zoomScale,
                        currentOffset: panOffset,
                        fittedSize: fittedSize,
                        viewportSize: viewportSize
                    ) {
                        zoomScale = result.newScale
                        baseZoomScale = result.newScale
                        panOffset = result.newOffset
                    }
                }
            )
            #endif
        }
    }

    // MARK: - Drag & Tap Handlers

    private func handleDragChanged(
        value: DragGesture.Value,
        zoomTransform: WallZoomTransform,
        fittedSize: CGSize,
        viewportSize: CGSize
    ) {
        currentMouseLocation = value.location

        // Check if starting a drag
        if activeDragAction == nil {
            if isEditingHolds && canEditWallLayout {
                if isShiftActive,
                   let selID = selectedHoldID,
                   let selectedHold = holds.first(where: { $0.holdID == selID }),
                   let handle = hitTestHandle(near: value.startLocation, hold: selectedHold, zoomTransform: zoomTransform, fittedSize: fittedSize) {
                    // Shift is pressed: edit the ellipse!
                    switch handle {
                    case .rotate:
                        activeDragAction = .rotate(selID)
                    case .resizeMajor:
                        activeDragAction = .resizeMajor(selID)
                    case .resizeMinor:
                        activeDragAction = .resizeMinor(selID)
                    case .move:
                        activeDragAction = .move(selID)
                    }
                } else if let match = zoomTransform.closestHold(near: value.startLocation, in: holds, maxScreenDistance: 24.0) {
                    // Shift not pressed (or tapped inside hold): drag the hold as before!
                    selectedHoldID = match.hold.holdID
                    activeDragAction = .move(match.hold.holdID)
                    updateCrop(for: match.hold)
                } else if zoomScale > 1.0 {
                    activeDragAction = .pan(panOffset)
                }
            } else if zoomScale > 1.0 {
                activeDragAction = .pan(panOffset)
            }
        }

        guard let action = activeDragAction else { return }

        switch action {
        case let .move(holdID):
            if let hold = holds.first(where: { $0.holdID == holdID }) {
                let world = zoomTransform.viewportToWorldCm(value.location)
                hold.xCm = max(0, min(WallSpec.widthCm, world.xCm))
                hold.yCm = max(0, min(WallSpec.totalHeightCm, world.yCm))
                hold.plane = hold.yCm <= WallSpec.kickboardHeightCm ? .kickboard : .main
                updateCrop(for: hold)
                inlineStatusMessage = "Moving hold #\(hold.holdID) to (\(Int(hold.xCm)), \(Int(hold.yCm))) cm"
            }

        case let .resizeMajor(holdID):
            if let hold = holds.first(where: { $0.holdID == holdID }) {
                let mouseWall = zoomTransform.viewportToWall(value.location)
                let holdWall = zoomTransform.worldCmToWall(xCm: hold.xCm, yCm: hold.yCm)
                let dx = mouseWall.x - holdWall.x
                let dy = mouseWall.y - holdWall.y
                let rad = CGFloat(hold.rotationDeg * .pi / 180.0)
                let localX = dx * cos(rad) - dy * sin(rad)
                let newA = max(2.0, abs(localX))
                let scaleCmToWall = fittedSize.width / CGFloat(WallSpec.widthCm)
                let newMajorCm = max(2.0, min(80.0, (2.0 * newA) / scaleCmToWall))
                hold.majorCm = (newMajorCm * 10).rounded() / 10
                if activeCropCGImage == nil || croppedHoldID != hold.holdID {
                    updateCrop(for: hold)
                }
                inlineStatusMessage = "Hold #\(hold.holdID) major axis: \(String(format: "%.1f", hold.majorCm)) cm"
            }

        case let .resizeMinor(holdID):
            if let hold = holds.first(where: { $0.holdID == holdID }) {
                let mouseWall = zoomTransform.viewportToWall(value.location)
                let holdWall = zoomTransform.worldCmToWall(xCm: hold.xCm, yCm: hold.yCm)
                let dx = mouseWall.x - holdWall.x
                let dy = mouseWall.y - holdWall.y
                let rad = CGFloat(hold.rotationDeg * .pi / 180.0)
                let localY = dx * sin(rad) + dy * cos(rad)
                let newB = max(2.0, abs(localY))
                let scaleCmToWall = fittedSize.height / CGFloat(WallSpec.totalHeightCm)
                let newMinorCm = max(2.0, min(80.0, (2.0 * newB) / scaleCmToWall))
                hold.minorCm = (newMinorCm * 10).rounded() / 10
                if activeCropCGImage == nil || croppedHoldID != hold.holdID {
                    updateCrop(for: hold)
                }
                inlineStatusMessage = "Hold #\(hold.holdID) minor axis: \(String(format: "%.1f", hold.minorCm)) cm"
            }

        case let .rotate(holdID):
            if let hold = holds.first(where: { $0.holdID == holdID }) {
                let mouseWall = zoomTransform.viewportToWall(value.location)
                let holdWall = zoomTransform.worldCmToWall(xCm: hold.xCm, yCm: hold.yCm)
                let dx = mouseWall.x - holdWall.x
                let dy = -(mouseWall.y - holdWall.y)
                var deg = atan2(dy, dx) * 180.0 / .pi
                if deg < 0 { deg += 360 }
                hold.rotationDeg = deg.rounded()
                if activeCropCGImage == nil || croppedHoldID != hold.holdID {
                    updateCrop(for: hold)
                }
                inlineStatusMessage = "Hold #\(hold.holdID) rotation: \(Int(hold.rotationDeg))°"
            }

        case let .pan(start):
            let candidate = CGSize(
                width: start.width + value.translation.width,
                height: start.height + value.translation.height
            )
            panOffset = WallZoomTransform.clampedOffset(
                candidate,
                fittedSize: fittedSize,
                viewportSize: viewportSize,
                scale: zoomScale
            )
        }
    }

    private func handleDragEnded(
        value: DragGesture.Value,
        zoomTransform: WallZoomTransform
    ) {
        if let action = activeDragAction {
            switch action {
            case let .move(holdID), let .resizeMajor(holdID), let .resizeMinor(holdID), let .rotate(holdID):
                if let hold = holds.first(where: { $0.holdID == holdID }) {
                    persistHoldGeometry(
                        holdID: hold.holdID,
                        xCm: hold.xCm,
                        yCm: hold.yCm,
                        majorCm: hold.majorCm,
                        minorCm: hold.minorCm,
                        rotationDeg: hold.rotationDeg
                    )
                    inlineStatusMessage = "Hold #\(hold.holdID): (\(String(format: "%.1f", hold.majorCm)), \(String(format: "%.1f", hold.minorCm))) cm, \(Int(hold.rotationDeg))°"
                }
            case .pan:
                break
            }
        }
        activeDragAction = nil
    }

    private func hitTestHandle(
        near location: CGPoint,
        hold: Hold,
        zoomTransform: WallZoomTransform,
        fittedSize: CGSize
    ) -> HoldHandleType? {
        let mouseWall = zoomTransform.viewportToWall(location)
        let holdWall = zoomTransform.worldCmToWall(xCm: hold.xCm, yCm: hold.yCm)

        let dx = mouseWall.x - holdWall.x
        let dy = mouseWall.y - holdWall.y

        let rad = CGFloat(hold.rotationDeg * .pi / 180.0)
        let localX = dx * cos(rad) - dy * sin(rad)
        let localY = dx * sin(rad) + dy * cos(rad)

        let holdWidthWall = max(6.0, CGFloat(hold.majorCm) * (fittedSize.width / CGFloat(WallSpec.widthCm)))
        let holdHeightWall = max(6.0, CGFloat(hold.minorCm) * (fittedSize.height / CGFloat(WallSpec.totalHeightCm)))

        let a = holdWidthWall / 2.0
        let b = holdHeightWall / 2.0
        let stemLen = 20.0 / zoomTransform.zoomScale

        let distRot = hypot(localX - (a + stemLen), localY) * zoomTransform.zoomScale
        let distMaj1 = hypot(localX - a, localY) * zoomTransform.zoomScale
        let distMaj2 = hypot(localX + a, localY) * zoomTransform.zoomScale
        let distMin1 = hypot(localX, localY - b) * zoomTransform.zoomScale
        let distMin2 = hypot(localX, localY + b) * zoomTransform.zoomScale

        if distRot <= 18 {
            return .rotate
        }
        if min(distMaj1, distMaj2) <= 16 {
            return .resizeMajor
        }
        if min(distMin1, distMin2) <= 16 {
            return .resizeMinor
        }

        let norm = (localX * localX) / max(1.0, a * a) + (localY * localY) / max(1.0, b * b)
        let centerDistScreen = hypot(dx, dy) * zoomTransform.zoomScale
        if norm <= 1.25 || centerDistScreen <= 24 {
            return .move
        }

        return nil
    }

    private func handleCanvasTap(at location: CGPoint, zoomTransform: WallZoomTransform) {
        guard canEditWallLayout else {
            // Read-only user: tapping a hold shows or hides the loupe on iPhone / touch screen
            if let match = zoomTransform.closestHold(near: location, in: holds, maxScreenDistance: 28.0) {
                if hoveredHold?.holdID == match.hold.holdID {
                    withAnimation(.easeOut(duration: 0.15)) {
                        hoveredHold = nil
                        activeCropCGImage = nil
                        croppedHoldID = nil
                        croppedHoldCoord = nil
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.15)) {
                        hoveredHold = match.hold
                        currentMouseLocation = location
                    }
                    updateCrop(for: match.hold)
                    inlineStatusMessage = "Hold #\(match.hold.holdID) at (\(Int(match.hold.xCm)), \(Int(match.hold.yCm))) cm (\(match.hold.plane.rawValue.capitalized))"
                }
            } else {
                withAnimation(.easeOut(duration: 0.15)) {
                    hoveredHold = nil
                    activeCropCGImage = nil
                    croppedHoldID = nil
                    croppedHoldCoord = nil
                }
            }
            return
        }

        guard isEditingHolds else {
            // In locked mode, tapping a hold selects it and opens high-res loupe
            if let match = zoomTransform.closestHold(near: location, in: holds, maxScreenDistance: 28.0) {
                if hoveredHold?.holdID == match.hold.holdID {
                    withAnimation(.easeOut(duration: 0.15)) {
                        hoveredHold = nil
                        activeCropCGImage = nil
                        croppedHoldID = nil
                        croppedHoldCoord = nil
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.15)) {
                        hoveredHold = match.hold
                        currentMouseLocation = location
                    }
                    updateCrop(for: match.hold)
                    inlineStatusMessage = "Hold #\(match.hold.holdID) at (\(Int(match.hold.xCm)), \(Int(match.hold.yCm))) cm (\(match.hold.plane.rawValue.capitalized))"
                }
            } else {
                withAnimation(.easeOut(duration: 0.15)) {
                    hoveredHold = nil
                    activeCropCGImage = nil
                    croppedHoldID = nil
                    croppedHoldCoord = nil
                }
            }
            return
        }

        // In edit mode: if tapped directly on an existing hold, select it
        if let match = zoomTransform.closestHold(near: location, in: holds, maxScreenDistance: 24.0) {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedHoldID = match.hold.holdID
                hoveredHold = match.hold
                currentMouseLocation = location
            }
            updateCrop(for: match.hold)
            inlineStatusMessage = "Hold #\(match.hold.holdID): (\(String(format: "%.1f", match.hold.majorCm)), \(String(format: "%.1f", match.hold.minorCm))) cm, \(Int(match.hold.rotationDeg))°. Drag to move, or hold Shift to edit ellipse."
            return
        }

        // If a hold was selected and user tapped empty wall, deselect it
        if selectedHoldID != nil {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedHoldID = nil
                hoveredHold = nil
                activeCropCGImage = nil
                croppedHoldID = nil
                croppedHoldCoord = nil
            }
            inlineStatusMessage = nil
            return
        }

        // Otherwise: add new hold at exact world coordinates
        let world = zoomTransform.viewportToWorldCm(location)
        addHold(xCm: world.xCm, yCm: world.yCm)
    }

    private func handleMouseHover(
        at viewportPoint: CGPoint,
        zoomTransform: WallZoomTransform
    ) {
        currentMouseLocation = viewportPoint

        guard activeDragAction == nil else { return }

        // When a hold is selected in edit mode, editing that hold has priority!
        if isEditingHolds, let selID = selectedHoldID, let selHold = holds.first(where: { $0.holdID == selID }) {
            if loupeConfig.isEnabled && (activeCropCGImage == nil || croppedHoldID != selHold.holdID) {
                updateCrop(for: selHold)
            }
            return
        }

        let hitRadius: CGFloat = 28.0
        if let match = zoomTransform.closestHold(near: viewportPoint, in: holds, maxScreenDistance: hitRadius) {
            let hold = match.hold
            if hoveredHold?.holdID != hold.holdID {
                withAnimation(.easeOut(duration: 0.12)) {
                    hoveredHold = hold
                }
                if loupeConfig.isEnabled {
                    updateCrop(for: hold)
                }
            }
        } else {
            if hoveredHold != nil {
                withAnimation(.easeOut(duration: 0.12)) {
                    hoveredHold = nil
                    if selectedHoldID == nil {
                        activeCropCGImage = nil
                        croppedHoldID = nil
                        croppedHoldCoord = nil
                    }
                }
            }
        }
    }

    private func handleMouseExited() {
        currentMouseLocation = nil
        if activeDragAction == nil {
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredHold = nil
                if !isEditingHolds || selectedHoldID == nil {
                    activeCropCGImage = nil
                    croppedHoldID = nil
                    croppedHoldCoord = nil
                }
            }
        }
    }

    // MARK: - Photo Loading & Backward Transform Cropping

    private var activeCalibrationPoints: [CalibrationPoint] {
        if let points = calibrations.first?.points, !points.isEmpty {
            return points
        }
        return CalibrationPointTemplates.all
    }

    private func loadOriginalPhoto() {
        let photoPath = calibrations.first?.photoPath ?? WallCalibration.defaultPhotoPath
        Task.detached {
            let image = await OriginalPhotoLoader.shared.loadPhoto(from: photoPath)
            await MainActor.run {
                self.originalPhotoCGImage = image
                if let active = self.activeHoldForLoupe {
                    self.updateCrop(for: active)
                }
            }
        }
    }

    private func updateCrop(for hold: Hold) {
        guard let originalImage = originalPhotoCGImage else {
            loadOriginalPhoto()
            return
        }
        if croppedHoldID == hold.holdID,
           let lastCoord = croppedHoldCoord,
           abs(lastCoord.x - CGFloat(hold.xCm)) < 0.1,
           abs(lastCoord.y - CGFloat(hold.yCm)) < 0.1,
           activeCropCGImage != nil {
            return
        }
        if let crop = HoldBackwardTransformService.cropLocation(
            from: originalImage,
            xCm: hold.xCm,
            yCm: hold.yCm,
            plane: hold.plane,
            calibrationPoints: activeCalibrationPoints,
            cropSpan: loupeConfig.cropPixelSpan
        ) {
            activeCropCGImage = crop
            croppedHoldID = hold.holdID
            croppedHoldCoord = CGPoint(x: hold.xCm, y: hold.yCm)
        }
    }

    // MARK: - Controls Toolbar

    private var controls: some View {
        VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    editButton
                    if isEditingHolds {
                        deleteAllButton
                    }
                    Spacer()
                    WallZoomControlsView(
                        zoomScale: $zoomScale,
                        panOffset: $panOffset,
                        baseZoomScale: $baseZoomScale,
                        loupeConfig: $loupeConfig
                    )
                }

                VStack(spacing: 6) {
                    HStack {
                        editButton
                        Spacer()
                        WallZoomControlsView(
                            zoomScale: $zoomScale,
                            panOffset: $panOffset,
                            baseZoomScale: $baseZoomScale,
                            loupeConfig: $loupeConfig
                        )
                    }
                    if isEditingHolds {
                        HStack {
                            deleteAllButton
                            Spacer()
                        }
                    }
                }
            }

            Text(isEditingHolds
                 ? (isShiftActive
                    ? "Shift held: drag cyan circle to rotate, white handles to resize ellipse."
                    : "Edit mode: drag holds to reposition them. Hold Shift to edit ellipse size and rotation.")
                 : "Locked mode: wall is read-only. Tap or hover over holds to view high-resolution loupe preview. Press Edit to modify.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !canEditWallLayout {
                Text("Wall layout is shared across all users. Only admin can edit it. Current user: \(appModel.currentUser?.email ?? "not logged in")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var editButton: some View {
        Button(isEditingHolds ? "Done" : "Edit") {
            if canEditWallLayout {
                isEditingHolds.toggle()
                inlineStatusMessage = nil
                if !isEditingHolds {
                    activeDragAction = nil
                    selectedHoldID = nil
                }
            } else {
                appModel.globalMessage = "Wall layout can be edited only by admin."
                inlineStatusMessage = "Only admin can edit wall layout. Signed in as: \(effectiveUserEmail ?? "unknown")"
            }
        }
        .buttonStyle(.borderedProminent)
    }

    private var deleteAllButton: some View {
        Button("Delete all and reset counter", role: .destructive) {
            if canEditWallLayout {
                showDeleteAllConfirmation = true
            } else {
                appModel.globalMessage = "Wall layout can be edited only by admin."
                inlineStatusMessage = "Only admin can edit wall layout. Signed in as: \(effectiveUserEmail ?? "unknown")"
            }
        }
        .buttonStyle(.bordered)
        .disabled(holds.isEmpty)
    }

    // MARK: - Data Management

    private func addHold(xCm: Double, yCm: Double) {
        guard canEditWallLayout else { return }

        let writeContext = ModelContext(modelContext.container)
        let existing = (try? writeContext.fetch(FetchDescriptor<Hold>(sortBy: [SortDescriptor(\.holdID)]))) ?? []
        let holdID = (existing.map(\.holdID).max() ?? 0) + 1
        let clampedX = max(0, min(WallSpec.widthCm, xCm))
        let clampedY = max(0, min(WallSpec.totalHeightCm, yCm))
        let plane: HoldPlane = clampedY <= WallSpec.kickboardHeightCm ? .kickboard : .main

        let hold = Hold(
            holdID: holdID,
            xCm: clampedX,
            yCm: clampedY,
            plane: plane,
            role: .hand,
            majorCm: Hold.defaultMajorCm,
            minorCm: Hold.defaultMinorCm,
            rotationDeg: Hold.defaultRotationDeg
        )
        writeContext.insert(hold)
        if persist(context: writeContext) {
            let afterCount = fetchHoldsAndReturnCount()
            let insertedPresent = isHoldPersisted(holdID: holdID)

            if insertedPresent {
                selectedHoldID = holdID
                inlineStatusMessage = "Added hold #\(holdID): (\(Int(clampedX)), \(Int(clampedY))) cm. Total holds: \(afterCount)."
                if let newHold = holds.first(where: { $0.holdID == holdID }) {
                    hoveredHold = newHold
                    updateCrop(for: newHold)
                }
            } else {
                inlineStatusMessage = "Insert attempted for hold #\(holdID), but DB verification failed."
                appModel.globalMessage = "Insert verification failed."
            }
        }
    }

    private func persistHoldGeometry(
        holdID: Int,
        xCm: Double,
        yCm: Double,
        majorCm: Double,
        minorCm: Double,
        rotationDeg: Double
    ) {
        let writeContext = ModelContext(modelContext.container)
        let id = holdID
        let descriptor = FetchDescriptor<Hold>(
            predicate: #Predicate<Hold> { item in
                item.holdID == id
            }
        )

        guard let target = try? writeContext.fetch(descriptor).first else {
            inlineStatusMessage = "Save failed: hold #\(holdID) not found in DB."
            return
        }

        target.xCm = max(0, min(WallSpec.widthCm, xCm))
        target.yCm = max(0, min(WallSpec.totalHeightCm, yCm))
        target.plane = target.yCm <= WallSpec.kickboardHeightCm ? .kickboard : .main
        target.majorCm = max(1.0, majorCm)
        target.minorCm = max(1.0, minorCm)
        target.rotationDeg = rotationDeg

        if persist(context: writeContext) {
            _ = fetchHoldsAndReturnCount()
        }
    }

    private func delete(hold: Hold) {
        guard canEditWallLayout else {
            appModel.globalMessage = "Wall layout can be edited only by admin."
            inlineStatusMessage = "Only admin can edit wall layout. Signed in as: \(effectiveUserEmail ?? "unknown")"
            return
        }

        let writeContext = ModelContext(modelContext.container)
        let id = hold.holdID
        let descriptor = FetchDescriptor<Hold>(
            predicate: #Predicate<Hold> { item in
                item.holdID == id
            }
        )
        if let target = try? writeContext.fetch(descriptor).first {
            writeContext.delete(target)
        }

        if persist(context: writeContext) {
            _ = fetchHoldsAndReturnCount()
            if selectedHoldID == hold.holdID {
                selectedHoldID = nil
            }
            if hoveredHold?.holdID == hold.holdID {
                hoveredHold = nil
                activeCropCGImage = nil
                croppedHoldID = nil
                croppedHoldCoord = nil
            }
            inlineStatusMessage = "Hold #\(id) deleted. Total holds: \(holds.count)."
        }
    }

    private func deleteAllHoldsAndResetCounter() {
        guard canEditWallLayout else {
            appModel.globalMessage = "Wall layout can be edited only by admin."
            inlineStatusMessage = "Only admin can edit wall layout. Signed in as: \(effectiveUserEmail ?? "unknown")"
            return
        }

        let writeContext = ModelContext(modelContext.container)
        do {
            let allHolds = try writeContext.fetch(FetchDescriptor<Hold>())
            for hold in allHolds {
                writeContext.delete(hold)
            }
            let allGrips = try writeContext.fetch(FetchDescriptor<Grip>())
            for grip in allGrips {
                writeContext.delete(grip)
            }
            try writeContext.save()

            _ = fetchHoldsAndReturnCount()
            hoveredHold = nil
            selectedHoldID = nil
            activeDragAction = nil
            activeCropCGImage = nil
            croppedHoldID = nil
            croppedHoldCoord = nil
            inlineStatusMessage = "All holds deleted. Hold counter reset to 1."
            appModel.globalMessage = "All holds deleted. Hold counter reset to 1."
        } catch {
            appModel.globalMessage = "Failed to delete holds: \(error.localizedDescription)"
            inlineStatusMessage = "Failed to delete holds: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func persist(context: ModelContext) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            appModel.globalMessage = "Save failed: \(error.localizedDescription)"
            inlineStatusMessage = "Save failed: \(error.localizedDescription)"
            return false
        }
    }

    private func fetchHolds() {
        _ = fetchHoldsAndReturnCount()
    }

    @discardableResult
    private func fetchHoldsAndReturnCount() -> Int {
        do {
            let readContext = ModelContext(modelContext.container)
            let descriptor = FetchDescriptor<Hold>(sortBy: [SortDescriptor(\.holdID)])
            holds = try readContext.fetch(descriptor)
            return holds.count
        } catch {
            holds = []
            appModel.globalMessage = "Could not load holds: \(error.localizedDescription)"
            inlineStatusMessage = "Could not load holds: \(error.localizedDescription)"
            return 0
        }
    }

    private func isHoldPersisted(holdID: Int) -> Bool {
        do {
            let readContext = ModelContext(modelContext.container)
            let id = holdID
            let descriptor = FetchDescriptor<Hold>(
                predicate: #Predicate<Hold> { hold in
                    hold.holdID == id
                }
            )
            return try readContext.fetch(descriptor).isEmpty == false
        } catch {
            return false
        }
    }

    private var canEditWallLayout: Bool {
        appModel.isAdmin
    }

    private var effectiveUserEmail: String? {
        if let runtimeEmail = appModel.currentUser?.email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !runtimeEmail.isEmpty {
            return runtimeEmail
        }

        let persistedEmail = UserDefaults.standard.string(forKey: Self.persistedEmailKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let persistedEmail, !persistedEmail.isEmpty {
            return persistedEmail
        }

        return nil
    }
}

// MARK: - Drag Actions & Handle Types

private enum HoldDragAction {
    case move(Int)
    case resizeMajor(Int)
    case resizeMinor(Int)
    case rotate(Int)
    case pan(CGSize)
}

private enum HoldHandleType {
    case rotate
    case resizeMajor
    case resizeMinor
    case move
}

// MARK: - Hold Position Visual Ellipse Dot

private struct HoldPositionDotView: View {
    let holdID: Int
    var widthPt: CGFloat = 16
    var heightPt: CGFloat = 16
    var rotationDeg: Double = 0
    var zoomScale: CGFloat = 1.0
    var isHovered: Bool = false
    var isSelected: Bool = false
    var isEditing: Bool = false
    var isShiftPressed: Bool = false

    var body: some View {
        let displayWidth = isHovered || isSelected ? max(widthPt * 1.05, widthPt + 2) : widthPt
        let displayHeight = isHovered || isSelected ? max(heightPt * 1.05, heightPt + 2) : heightPt
        let a = displayWidth / 2.0
        let b = displayHeight / 2.0
        let handleSize = 8.0 / zoomScale
        let rotHandleSize = 11.0 / zoomScale
        let stemLen = 20.0 / zoomScale
        let pencilLineWidth = (isSelected ? 1.4 : (isHovered ? 1.3 : 1.1)) / zoomScale

        ZStack(alignment: .center) {
            // Rotated hold ellipse, bounding box, and interactive visual handles
            ZStack {
                if isSelected && isEditing && isShiftPressed {
                    // 1. Rotated bounding box outline
                    Rectangle()
                        .stroke(
                            Color.cyan.opacity(0.85),
                            style: StrokeStyle(lineWidth: 1.0 / zoomScale, dash: [3.0 / zoomScale, 3.0 / zoomScale])
                        )
                        .frame(width: displayWidth, height: displayHeight)

                    // 2. Rotation stem line extending from major axis (+X end)
                    Rectangle()
                        .fill(Color.cyan)
                        .frame(width: stemLen, height: 1.2 / zoomScale)
                        .offset(x: a + stemLen / 2.0)

                    // 3. Rotation handle (cyan circle with white stroke)
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: rotHandleSize, height: rotHandleSize)
                        .overlay {
                            Circle().stroke(Color.white, lineWidth: 1.2 / zoomScale)
                        }
                        .offset(x: a + stemLen)

                    // 4. Major axis handles (two white squares on left and right)
                    RoundedRectangle(cornerRadius: 1.5 / zoomScale)
                        .fill(Color.white)
                        .frame(width: handleSize, height: handleSize)
                        .overlay {
                            RoundedRectangle(cornerRadius: 1.5 / zoomScale).stroke(Color.cyan, lineWidth: 1.2 / zoomScale)
                        }
                        .offset(x: a)

                    RoundedRectangle(cornerRadius: 1.5 / zoomScale)
                        .fill(Color.white)
                        .frame(width: handleSize, height: handleSize)
                        .overlay {
                            RoundedRectangle(cornerRadius: 1.5 / zoomScale).stroke(Color.cyan, lineWidth: 1.2 / zoomScale)
                        }
                        .offset(x: -a)

                    // 5. Minor axis handles (two white squares on top and bottom)
                    RoundedRectangle(cornerRadius: 1.5 / zoomScale)
                        .fill(Color.white)
                        .frame(width: handleSize, height: handleSize)
                        .overlay {
                            RoundedRectangle(cornerRadius: 1.5 / zoomScale).stroke(Color.blue, lineWidth: 1.2 / zoomScale)
                        }
                        .offset(y: -b)

                    RoundedRectangle(cornerRadius: 1.5 / zoomScale)
                        .fill(Color.white)
                        .frame(width: handleSize, height: handleSize)
                        .overlay {
                            RoundedRectangle(cornerRadius: 1.5 / zoomScale).stroke(Color.blue, lineWidth: 1.2 / zoomScale)
                        }
                        .offset(y: b)
                }

                // Hold ellipse shape - fine pencil thickness that does not increase when zoomed
                Ellipse()
                    .fill(isSelected ? Color.cyan.opacity(0.35) : (isHovered ? Color.cyan.opacity(0.25) : Color.purple.opacity(0.20)))
                    .overlay {
                        Ellipse().stroke(
                            isSelected ? Color.cyan : (isHovered ? Color.cyan : Color.purple),
                            lineWidth: pencilLineWidth
                        )
                    }
                    .frame(width: displayWidth, height: displayHeight)
            }
            .rotationEffect(.degrees(-rotationDeg))
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered || isSelected)

            // Bolt center point marker (constant pencil-scale dot, never increases with zoom)
            Circle()
                .fill(isSelected ? Color.yellow : (isHovered ? Color.white : Color.white.opacity(0.85)))
                .frame(width: 3.0 / zoomScale, height: 3.0 / zoomScale)
        }
        .shadow(color: isSelected ? Color.cyan.opacity(0.5) : (isHovered ? Color.cyan.opacity(0.3) : .clear), radius: 2.0 / zoomScale)
    }
}
