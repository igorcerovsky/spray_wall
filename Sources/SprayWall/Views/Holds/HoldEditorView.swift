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

    // Loupe preview state
    @State private var loupeConfig = HoldLoupeConfig.defaultCircle
    @State private var hoveredHold: Hold?
    @State private var draggedHold: Hold?
    @State private var hoveredCropCGImage: CGImage?
    @State private var originalPhotoCGImage: CGImage?
    @State private var currentMouseLocation: CGPoint? = nil

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
                        let isHovered = (hoveredHold?.holdID == hold.holdID) || (draggedHold?.holdID == hold.holdID)
                        let markerPos = zoomTransform.worldCmToWall(xCm: hold.xCm, yCm: hold.yCm)

                        HoldPositionDotView(
                            holdID: hold.holdID,
                            xCm: hold.xCm,
                            yCm: hold.yCm,
                            isHovered: isHovered,
                            isEditing: isEditingHolds
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
                if loupeConfig.isEnabled, let activeHold = draggedHold ?? hoveredHold {
                    let anchorScreenPt = zoomTransform.worldCmToViewport(xCm: activeHold.xCm, yCm: activeHold.yCm)
                    let loupePosition = WallZoomTransform.computeLoupePosition(
                        anchorPoint: currentMouseLocation ?? anchorScreenPt,
                        loupeConfig: loupeConfig,
                        viewportSize: viewportSize
                    )

                    HoldLoupeView(
                        croppedImage: hoveredCropCGImage,
                        title: "Hold #\(activeHold.holdID)",
                        subtitle: "(\(Int(activeHold.xCm)), \(Int(activeHold.yCm))) cm",
                        config: loupeConfig
                    )
                    .position(loupePosition)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .allowsHitTesting(false)
                }
            }
            .frame(width: viewportSize.width, height: viewportSize.height)
            .clipped()
            .contentShape(Rectangle())
            .contextMenu {
                if isEditingHolds, canEditWallLayout, let hold = hoveredHold {
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

        // Check if starting a drag on a hold (or continuing dragging one)
        if draggedHold == nil && dragStartOffset == nil {
            if isEditingHolds && canEditWallLayout,
               let match = zoomTransform.closestHold(near: value.startLocation, in: holds, maxScreenDistance: 24.0) {
                draggedHold = match.hold
            } else if zoomScale > 1.0 {
                dragStartOffset = panOffset
            }
        }

        if let hold = draggedHold {
            // Dragging hold in physical world coordinates (cm)
            let world = zoomTransform.viewportToWorldCm(value.location)
            hold.xCm = max(0, min(WallSpec.widthCm, world.xCm))
            hold.yCm = max(0, min(WallSpec.totalHeightCm, world.yCm))
            hold.plane = hold.yCm <= WallSpec.kickboardHeightCm ? .kickboard : .main
            updateCrop(for: hold)
            inlineStatusMessage = "Moving hold #\(hold.holdID) to (\(Int(hold.xCm)), \(Int(hold.yCm))) cm"
        } else if let start = dragStartOffset {
            // Panning canvas
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
        if let hold = draggedHold {
            let world = zoomTransform.viewportToWorldCm(value.location)
            let finalX = max(0, min(WallSpec.widthCm, world.xCm))
            let finalY = max(0, min(WallSpec.totalHeightCm, world.yCm))
            persistMove(holdID: hold.holdID, xCm: finalX, yCm: finalY)
            inlineStatusMessage = "Moved hold #\(hold.holdID) to (\(Int(finalX)), \(Int(finalY))) cm"
            draggedHold = nil
        }
        dragStartOffset = nil
    }

    private func handleCanvasTap(at location: CGPoint, zoomTransform: WallZoomTransform) {
        guard canEditWallLayout else {
            // Read-only user: tapping a hold shows or hides the loupe on iPhone / touch screen
            if let match = zoomTransform.closestHold(near: location, in: holds, maxScreenDistance: 28.0) {
                if hoveredHold?.holdID == match.hold.holdID {
                    withAnimation(.easeOut(duration: 0.15)) {
                        hoveredHold = nil
                        hoveredCropCGImage = nil
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
                    hoveredCropCGImage = nil
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
                        hoveredCropCGImage = nil
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
                    hoveredCropCGImage = nil
                }
            }
            return
        }

        // In edit mode: if tapped directly on an existing hold, select it
        if let match = zoomTransform.closestHold(near: location, in: holds, maxScreenDistance: 24.0) {
            withAnimation(.easeOut(duration: 0.15)) {
                hoveredHold = match.hold
                currentMouseLocation = location
            }
            updateCrop(for: match.hold)
            inlineStatusMessage = "Selected hold #\(match.hold.holdID) at (\(Int(match.hold.xCm)), \(Int(match.hold.yCm))) cm. Drag to move, or right-click / context-menu to delete."
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

        guard draggedHold == nil else { return }

        guard loupeConfig.isEnabled else {
            if hoveredHold != nil {
                hoveredHold = nil
                hoveredCropCGImage = nil
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
                updateCrop(for: hold)
            }
        } else {
            if hoveredHold != nil {
                withAnimation(.easeOut(duration: 0.12)) {
                    hoveredHold = nil
                    hoveredCropCGImage = nil
                }
            }
        }
    }

    private func handleMouseExited() {
        currentMouseLocation = nil
        if draggedHold == nil {
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredHold = nil
                hoveredCropCGImage = nil
            }
        }
    }

    // MARK: - Photo Loading & Backward Transform Cropping

    private var activeCalibrationPoints: [CalibrationPoint] {
        calibrations.first?.points ?? CalibrationPointTemplates.all
    }

    private func loadOriginalPhoto() {
        let photoPath = calibrations.first?.photoPath ?? WallCalibration.defaultPhotoPath
        Task.detached {
            let image = await OriginalPhotoLoader.shared.loadPhoto(from: photoPath)
            await MainActor.run {
                self.originalPhotoCGImage = image
                if let active = self.draggedHold ?? self.hoveredHold {
                    self.updateCrop(for: active)
                }
            }
        }
    }

    private func updateCrop(for hold: Hold) {
        guard let originalImage = originalPhotoCGImage else { return }
        hoveredCropCGImage = HoldBackwardTransformService.cropLocation(
            from: originalImage,
            xCm: hold.xCm,
            yCm: hold.yCm,
            plane: hold.plane,
            calibrationPoints: activeCalibrationPoints,
            cropSpan: loupeConfig.cropPixelSpan
        )
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
                 ? "Edit mode: tap wall to add hold, drag to reposition (loupe shows exact bolt position), right-click or long-press to remove."
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
                    draggedHold = nil
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
            role: .hand
        )
        writeContext.insert(hold)
        if persist(context: writeContext) {
            let afterCount = fetchHoldsAndReturnCount()
            let insertedPresent = isHoldPersisted(holdID: holdID)

            if insertedPresent {
                inlineStatusMessage = "Added hold #\(holdID) at (\(Int(clampedX)), \(Int(clampedY))) cm. Total holds: \(afterCount)."
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

    private func persistMove(holdID: Int, xCm: Double, yCm: Double) {
        let writeContext = ModelContext(modelContext.container)
        let id = holdID
        let descriptor = FetchDescriptor<Hold>(
            predicate: #Predicate<Hold> { item in
                item.holdID == id
            }
        )

        guard let target = try? writeContext.fetch(descriptor).first else {
            inlineStatusMessage = "Move failed: hold #\(holdID) not found in DB."
            return
        }

        target.xCm = max(0, min(WallSpec.widthCm, xCm))
        target.yCm = max(0, min(WallSpec.totalHeightCm, yCm))
        target.plane = target.yCm <= WallSpec.kickboardHeightCm ? .kickboard : .main

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
            if hoveredHold?.holdID == hold.holdID {
                hoveredHold = nil
                hoveredCropCGImage = nil
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
            draggedHold = nil
            hoveredCropCGImage = nil
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

// MARK: - Hold Position Visual Marker Dot

private struct HoldPositionDotView: View {
    let holdID: Int
    var xCm: Double = 0
    var yCm: Double = 0
    var isHovered: Bool = false
    var isEditing: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            Circle()
                .fill(isHovered ? Color.cyan.opacity(0.35) : Color.purple.opacity(0.25))
                .frame(width: isHovered ? 16 : 10, height: isHovered ? 16 : 10)
                .overlay {
                    Circle().stroke(isHovered ? Color.cyan : Color.purple, lineWidth: isHovered ? 2 : 1)
                }
                .shadow(color: isHovered ? Color.cyan.opacity(0.8) : .clear, radius: 4)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)

            Text("\(holdID)")
                .font(.caption2.monospacedDigit().weight(isHovered ? .bold : .regular))
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Color.black.opacity(isHovered ? 0.9 : 0.65))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .offset(y: isHovered ? -16 : -12)
        }
    }
}
