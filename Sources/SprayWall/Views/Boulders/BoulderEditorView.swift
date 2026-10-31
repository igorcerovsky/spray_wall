import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct BoulderEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Hold.holdID) private var holds: [Hold]
    @Query(sort: \WallCalibration.updatedAt, order: .reverse) private var calibrations: [WallCalibration]

    let boulder: Boulder

    @State private var name = ""
    @State private var grade = ""
    @State private var setter = ""
    @State private var tags = ""
    @State private var notes = ""
    @State private var rating = 0

    @State private var selectedGroup: BoulderHoldGroup = .hold
    @State private var editingHoldDetails: Hold?
    @State private var showDeleteConfirmation = false

    // Zoom and pan state
    @State private var zoomScale: CGFloat = 1.0
    @State private var baseZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize? = nil

    // Loupe preview state
    @State private var loupeConfig = HoldLoupeConfig.defaultCircle
    @State private var hoveredHold: Hold?
    @State private var hoveredCropCGImage: CGImage?
    @State private var originalPhotoCGImage: CGImage?
    @State private var currentMouseLocation: CGPoint? = nil

    var body: some View {
        Group {
            if canEditDraft {
                draftLayout
            } else {
                establishedLayout
            }
        }
        .navigationTitle("Boulder")
        .toolbar {
            if appModel.isAdmin {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Boulder", systemImage: "trash")
                    }
                    .help("Delete boulder (Admin)")
                }
            }
        }
        .confirmationDialog(
            "Delete Boulder?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Boulder", role: .destructive) {
                deleteBoulder()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete '\(displayName)'? This action cannot be undone.")
        }
        .task {
            load()
            loadOriginalPhoto()
        }
        .sheet(item: $editingHoldDetails) { hold in
            HoldDetailView(hold: hold)
        }
    }

    // MARK: - Draft Mode Layout (Wall Fits Window Client Area Without Scrolling)

    private var draftLayout: some View {
        GeometryReader { windowGeo in
            if windowGeo.size.width < 680 {
                VStack(spacing: 8) {
                    HStack {
                        roleButtons
                        Spacer()
                        zoomControls
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)

                    fittedZoomableWallView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    draftInspectorView
                        .frame(maxHeight: 250)
                }
            } else {
                HStack(spacing: 0) {
                    VStack(spacing: 8) {
                        HStack {
                            roleButtons
                            Spacer()
                            zoomControls
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        HStack {
                            Text("Click hold to assign role. Double-click to remove. Hold Ctrl + scroll wheel to zoom.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)

                        fittedZoomableWallView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    draftInspectorView
                        .frame(width: 320)
                }
            }
        }
    }

    // MARK: - Established Mode Layout

    private var establishedLayout: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(displayName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(displayGrade)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(displaySetter)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(starsText(for: boulder.rating))
                    .font(.subheadline)
                    .foregroundStyle(.yellow)
                Spacer(minLength: 0)
                zoomControls
            }
            .padding(.horizontal)
            .padding(.top, 6)

            fittedZoomableWallView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 8) {
                HStack {
                    Button("Log Attempt") {
                        logAttempt()
                    }
                    .disabled(boulder.ascentLogged)

                    Spacer()

                    if appModel.isAdmin {
                        Button("Delete Boulder", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)

                        Spacer()
                    }

                    Button("Log Ascent") {
                        logAscent()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(boulder.ascentLogged)
                }

                if let loggedAt = boulder.ascentLoggedAt {
                    Text("Ascent: \(loggedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Fitted & Zoomable Wall Canvas

    private var fittedZoomableWallView: some View {
        GeometryReader { geometry in
            let viewportSize = geometry.size
            let fittedSize = computeFittedSize(in: viewportSize)
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
                    wallBackground(size: fittedSize)

                    // Visual hold markers rendered on the canvas
                    ForEach(holdsForWallPreview) { hold in
                        let role = boulder.role(for: hold.holdID)
                        let isHovered = hoveredHold?.holdID == hold.holdID
                        let markerPos = zoomTransform.worldCmToWall(xCm: hold.xCm, yCm: hold.yCm)

                        BoulderWallHoldMarker(
                            holdID: hold.holdID,
                            role: role,
                            isDimmed: role == nil,
                            showHoldID: canEditDraft,
                            isHovered: isHovered
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
                if let hoveredHold {
                    let loupePosition = computeLoupePosition(
                        mousePoint: currentMouseLocation,
                        fallbackHold: hoveredHold,
                        zoomTransform: zoomTransform,
                        viewportSize: viewportSize
                    )
                    let role = boulder.role(for: hoveredHold.holdID)

                    HoldLoupeView(
                        croppedImage: hoveredCropCGImage,
                        hold: hoveredHold,
                        role: role,
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
            .gesture(
                SpatialTapGesture(count: 2)
                    .onEnded { value in
                        guard canEditDraft else { return }
                        if let match = zoomTransform.closestHold(near: value.location, in: holdsForWallPreview, maxScreenDistance: 24.0) {
                            removeFromDraftIfAllowed(holdID: match.hold.holdID)
                        }
                    }
                    .exclusively(
                        before: SpatialTapGesture(count: 1)
                            .onEnded { value in
                                guard canEditDraft else { return }
                                if let match = zoomTransform.closestHold(near: value.location, in: holdsForWallPreview, maxScreenDistance: 24.0) {
                                    handleRoleFirstTap(on: match.hold)
                                }
                            }
                    )
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        guard zoomScale > 1.0 else { return }
                        if dragStartOffset == nil {
                            dragStartOffset = panOffset
                        }
                        if let start = dragStartOffset {
                            let candidate = CGSize(
                                width: start.width + value.translation.width,
                                height: start.height + value.translation.height
                            )
                            panOffset = clampedOffset(
                                candidate,
                                fittedSize: fittedSize,
                                viewportSize: viewportSize,
                                scale: zoomScale
                            )
                        }
                    }
                    .onEnded { _ in
                        dragStartOffset = nil
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
                            panOffset = clampedOffset(
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
                guard canEditDraft else { return }
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
                    handleScrollZoom(
                        delta: delta,
                        mouseLocation: mouseLocation,
                        fittedSize: fittedSize,
                        viewportSize: viewportSize
                    )
                }
            )
            #endif
        }
    }

    // MARK: - Geometry & Zoom Math

    private func computeFittedSize(in viewport: CGSize) -> CGSize {
        let wallAspect: CGFloat = WallSpec.widthCm / WallSpec.totalHeightCm
        if (viewport.width / max(1, viewport.height)) > wallAspect {
            let fitHeight = max(10, viewport.height)
            return CGSize(width: fitHeight * wallAspect, height: fitHeight)
        } else {
            let fitWidth = max(10, viewport.width)
            return CGSize(width: fitWidth, height: fitWidth / wallAspect)
        }
    }

    private func handleScrollZoom(
        delta: CGFloat,
        mouseLocation: CGPoint,
        fittedSize: CGSize,
        viewportSize: CGSize
    ) {
        let minScale: CGFloat = 1.0
        let maxScale: CGFloat = 5.0

        let previousScale = zoomScale
        let newScale = min(maxScale, max(minScale, zoomScale + (delta * zoomScale)))
        guard abs(newScale - previousScale) > 0.001 else { return }

        if newScale <= 1.0 {
            withAnimation(.easeOut(duration: 0.15)) {
                zoomScale = 1.0
                baseZoomScale = 1.0
                panOffset = .zero
            }
            return
        }

        // Focal zoom towards mouse position
        let mouseFromCenterX = mouseLocation.x - (viewportSize.width / 2)
        let mouseFromCenterY = mouseLocation.y - (viewportSize.height / 2)

        let scaleRatio = newScale / previousScale
        let targetX = mouseFromCenterX - ((mouseFromCenterX - panOffset.width) * scaleRatio)
        let targetY = mouseFromCenterY - ((mouseFromCenterY - panOffset.height) * scaleRatio)

        zoomScale = newScale
        baseZoomScale = newScale
        panOffset = clampedOffset(
            CGSize(width: targetX, height: targetY),
            fittedSize: fittedSize,
            viewportSize: viewportSize,
            scale: newScale
        )
    }

    private func clampedOffset(
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

    private func stepZoom(by delta: CGFloat) {
        let newScale = min(5.0, max(1.0, zoomScale + delta))
        withAnimation(.easeOut(duration: 0.15)) {
            zoomScale = newScale
            baseZoomScale = newScale
            if newScale <= 1.0 {
                panOffset = .zero
            }
        }
    }

    // MARK: - Loupe Positioning Math & Configuration

    private func handleMouseHover(
        at viewportPoint: CGPoint,
        zoomTransform: WallZoomTransform
    ) {
        currentMouseLocation = viewportPoint

        let hitRadius: CGFloat = 28.0
        if let match = zoomTransform.closestHold(near: viewportPoint, in: holdsForWallPreview, maxScreenDistance: hitRadius) {
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
        withAnimation(.easeOut(duration: 0.12)) {
            hoveredHold = nil
            hoveredCropCGImage = nil
        }
    }

    private func computeLoupePosition(
        mousePoint: CGPoint?,
        fallbackHold: Hold,
        zoomTransform: WallZoomTransform,
        viewportSize: CGSize
    ) -> CGPoint {
        let anchorPoint: CGPoint
        if let mousePoint {
            anchorPoint = mousePoint
        } else {
            anchorPoint = zoomTransform.worldCmToViewport(xCm: fallbackHold.xCm, yCm: fallbackHold.yCm)
        }

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

    private var loupeMenu: some View {
        Menu {
            Section("Loupe Shape") {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        loupeConfig.shape = .circle
                    }
                } label: {
                    Label("Circle", systemImage: loupeConfig.shape == .circle ? "checkmark.circle.fill" : "circle")
                }

                Button {
                    withAnimation(.spring(response: 0.3)) {
                        loupeConfig.shape = .roundedRectangle
                    }
                } label: {
                    Label("Rounded Card", systemImage: loupeConfig.shape == .roundedRectangle ? "checkmark.circle.fill" : "app")
                }
            }

            Section("Loupe Size") {
                Button("Compact (150 pt)") {
                    withAnimation(.spring(response: 0.3)) {
                        loupeConfig.size = CGSize(width: 150, height: 150)
                        loupeConfig.cropPixelSpan = 300
                    }
                }

                Button("Standard (190 pt)") {
                    withAnimation(.spring(response: 0.3)) {
                        loupeConfig.size = CGSize(width: 190, height: 190)
                        loupeConfig.cropPixelSpan = 380
                    }
                }

                Button("Large (240 pt)") {
                    withAnimation(.spring(response: 0.3)) {
                        loupeConfig.size = CGSize(width: 240, height: 240)
                        loupeConfig.cropPixelSpan = 480
                    }
                }
            }

            Section("Details") {
                Toggle("Center Reticle", isOn: $loupeConfig.showCrosshair)
                Toggle("Hold Badge", isOn: $loupeConfig.showBadge)
            }
        } label: {
            Image(systemName: loupeConfig.shape == .circle ? "viewfinder.circle" : "viewfinder.rectangular")
                .font(.caption)
        }
        .buttonStyle(.plain)
        .help("Hold Loupe Settings (Shape & Size)")
    }

    // MARK: - Zoom Controls View

    private var zoomControls: some View {
        HStack(spacing: 6) {
            Button {
                stepZoom(by: -0.2)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .disabled(zoomScale <= 1.01)
            .help("Zoom out (Ctrl + scroll down)")

            Text("\(Int((zoomScale * 100).rounded()))%")
                .font(.caption.monospacedDigit().weight(.medium))
                .frame(minWidth: 38)

            Button {
                stepZoom(by: 0.2)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .disabled(zoomScale >= 4.99)
            .help("Zoom in (Ctrl + scroll up)")

            if zoomScale > 1.01 || panOffset != .zero {
                Button("Reset") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        zoomScale = 1.0
                        baseZoomScale = 1.0
                        panOffset = .zero
                    }
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Reset zoom to fit window")
            }

            Divider()
                .frame(height: 14)

            loupeMenu
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Draft Inspector View

    private var draftInspectorView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Section: Boulder Info
                VStack(alignment: .leading, spacing: 10) {
                    Text("Boulder Info")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Grade")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Grade", selection: $grade) {
                            ForEach(Boulder.availableGrades, id: \.self) { grade in
                                Text(grade).tag(grade)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rating")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        starRatingPicker
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Setter")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(setter.isEmpty ? "-" : setter)
                            .font(.subheadline)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tags (comma-separated)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Tags", text: $tags)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Notes", text: $notes, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                    }

                    HStack {
                        Text("Status:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(boulder.status.displayName)
                            .font(.caption.weight(.semibold))
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Section: Summary
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hold Summary")
                        .font(.headline)

                    LabeledContent("Start", value: listText(boulder.startHoldIDs))
                    LabeledContent("Holds", value: listText(boulder.holdIDs))
                    LabeledContent("Footholds", value: listText(boulder.footholdIDs))
                    LabeledContent("Top", value: listText(boulder.topHoldIDs))
                }
                .padding(12)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Section: Actions
                VStack(spacing: 8) {
                    Button("Save Draft") {
                        saveDraft()
                    }
                    .frame(maxWidth: .infinity)

                    Button("Mark Established") {
                        establish()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)

                    if appModel.isAdmin {
                        Button("Delete Boulder", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(12)
        }
    }

    private var roleButtons: some View {
        HStack(spacing: 8) {
            ForEach(BoulderHoldGroup.allCases) { group in
                Button(group.displayName) {
                    selectedGroup = group
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedGroup == group ? groupColor(for: group) : .gray.opacity(0.35))
            }
        }
    }

    private func handleRoleFirstTap(on hold: Hold) {
        guard canEditDraft else {
            appModel.globalMessage = "Established boulders are read-only. Edit a draft boulder."
            return
        }

        if let message = boulder.assign(hold.holdID, to: selectedGroup) {
            appModel.globalMessage = message
            return
        }

        persist(message: nil)
    }

    private func load() {
        name = boulder.name
        grade = Boulder.normalizedGrade(boulder.grade)
        rating = Boulder.clampedRating(boulder.rating)
        setter = resolvedSetter()
        tags = boulder.tags
        notes = boulder.notes
    }

    private var activeCalibrationPoints: [CalibrationPoint] {
        calibrations.first?.points ?? CalibrationPointTemplates.all
    }

    private func loadOriginalPhoto() {
        let photoPath = calibrations.first?.photoPath ?? WallCalibration.defaultPhotoPath
        Task.detached {
            guard let url = try? WallProjectPaths.resolvePhotoURL(from: photoPath) else {
                return
            }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return
            }
            let options: [CFString: Any] = [kCGImageSourceShouldCache: true]
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
                return
            }
            await MainActor.run {
                self.originalPhotoCGImage = image
                if let currentHold = self.hoveredHold {
                    self.updateCrop(for: currentHold)
                }
            }
        }
    }



    private func updateCrop(for hold: Hold) {
        guard let originalImage = originalPhotoCGImage else { return }
        hoveredCropCGImage = HoldBackwardTransformService.cropHold(
            from: originalImage,
            hold: hold,
            calibrationPoints: activeCalibrationPoints,
            cropSpan: loupeConfig.cropPixelSpan
        )
    }

    private func saveDraft() {
        updateModelFromForm()
        boulder.normalizeForDraft()
        boulder.status = .draft
        persist(message: "Boulder draft saved.")
    }

    private func establish() {
        updateModelFromForm()
        boulder.normalizeForDraft()

        let issues = boulder.validateForEstablish(existingHoldIDs: Set(holds.map(\.holdID)))
        guard issues.isEmpty else {
            appModel.globalMessage = "Cannot establish: \(issues.joined(separator: " "))"
            return
        }

        boulder.status = .established
        persist(message: "Boulder established.")
    }

    private func deleteBoulder() {
        guard appModel.isAdmin else {
            appModel.globalMessage = "Only admin (igor cerovsky) can delete boulders."
            return
        }

        let name = displayName
        modelContext.delete(boulder)
        do {
            try modelContext.save()
            appModel.globalMessage = "Boulder '\(name)' deleted."
            dismiss()
        } catch {
            appModel.globalMessage = "Could not delete boulder: \(error.localizedDescription)"
        }
    }

    private func updateModelFromForm() {
        boulder.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        boulder.grade = Boulder.normalizedGrade(grade)
        boulder.rating = Boulder.clampedRating(rating)
        boulder.setter = resolvedSetter()
        setter = boulder.setter
        boulder.tags = tags.trimmingCharacters(in: .whitespacesAndNewlines)
        boulder.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var starRatingPicker: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    rating = (rating == value) ? 0 : value
                } label: {
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .foregroundStyle(value <= rating ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func removeFromDraftIfAllowed(holdID: Int) {
        guard canEditDraft else {
            appModel.globalMessage = "Established boulders are read-only. Edit a draft boulder."
            return
        }

        boulder.remove(holdID)
        persist(message: nil)
    }

    private func logAttempt() {
        if let message = boulder.logAttempt() {
            appModel.globalMessage = message
            return
        }

        persist(message: "Attempt logged.")
    }

    private func logAscent() {
        if let message = boulder.logAscent(by: appModel.currentUser?.id) {
            appModel.globalMessage = message
            return
        }

        persist(message: "Ascent logged. Attempts are now locked.")
    }

    private func resolvedSetter() -> String {
        if let current = appModel.currentUser?.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
           !current.isEmpty {
            return current
        }

        return boulder.setter.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayName: String {
        let trimmed = boulder.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    private var displayGrade: String {
        Boulder.normalizedGrade(boulder.grade)
    }

    private var displaySetter: String {
        let trimmed = boulder.setter.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : trimmed
    }

    private func starsText(for rating: Int) -> String {
        let clamped = Boulder.clampedRating(rating)
        return String(repeating: "★", count: clamped) + String(repeating: "☆", count: 5 - clamped)
    }

    private func groupColor(for group: BoulderHoldGroup) -> Color {
        switch group {
        case .start:
            return .green
        case .hold:
            return .blue
        case .foothold:
            return .yellow
        case .top:
            return .red
        }
    }

    private var canEditDraft: Bool {
        boulder.status == .draft
    }

    private func persist(message: String?) {
        do {
            try modelContext.save()
            if let message {
                appModel.globalMessage = message
            }
        } catch {
            appModel.globalMessage = "Could not save boulder: \(error.localizedDescription)"
        }
    }

    private func wallBackground(size: CGSize) -> some View {
        let kickboardHeight = size.height * (WallSpec.kickboardHeightCm / WallSpec.totalHeightCm)
        let mainWallHeight = max(0, size.height - kickboardHeight)
        let mainWallImageURL = existingURL(for: { try WallProjectPaths.defaultMainWallRectifiedURL() })
        let kickboardImageURL = existingURL(for: { try WallProjectPaths.defaultKickboardRectifiedURL() })

        return ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                wallSectionBackground(
                    imageURL: mainWallImageURL,
                    fallbackColor: Color.gray.opacity(0.2)
                )
                .frame(height: mainWallHeight)

                wallSectionBackground(
                    imageURL: kickboardImageURL,
                    fallbackColor: Color.brown.opacity(0.22)
                )
                .frame(height: kickboardHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(height: 1)
                .offset(y: -kickboardHeight)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func wallSectionBackground(imageURL: URL?, fallbackColor: Color) -> some View {
        if let imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(fallbackColor)
                default:
                    Rectangle().fill(fallbackColor)
                }
            }
        } else {
            Rectangle().fill(fallbackColor)
        }
    }

    private func existingURL(for resolver: () throws -> URL) -> URL? {
        guard let resolved = try? resolver(),
              FileManager.default.fileExists(atPath: resolved.path) else {
            return nil
        }
        return resolved
    }

    private func position(for hold: Hold, size: CGSize) -> CGPoint {
        let x = (hold.xCm / WallSpec.widthCm) * size.width
        let y = (1 - (hold.yCm / WallSpec.totalHeightCm)) * size.height
        return CGPoint(x: x, y: y)
    }

    private func listText(_ values: [Int]) -> String {
        values.isEmpty ? "-" : values.map(String.init).joined(separator: ", ")
    }

    private var holdsForWallPreview: [Hold] {
        if canEditDraft {
            return holds
        }

        return holds.filter { boulder.contains($0.holdID) }
    }
}

// MARK: - AppKit Scroll Wheel Zoom Handler for macOS

#if os(macOS)
private struct ScrollWheelZoomModifier: NSViewRepresentable {
    var onZoom: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> ZoomWheelNSView {
        let view = ZoomWheelNSView()
        view.onZoom = onZoom
        return view
    }

    func updateNSView(_ nsView: ZoomWheelNSView, context: Context) {
        nsView.onZoom = onZoom
    }
}

private final class ZoomWheelNSView: NSView {
    var onZoom: ((CGFloat, CGPoint) -> Void)?
    private nonisolated(unsafe) var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self = self, let win = self.window, event.window == win else {
                    return event
                }

                if event.modifierFlags.contains(.control) {
                    let pointInWindow = event.locationInWindow
                    let pointInView = self.convert(pointInWindow, from: nil)

                    if self.bounds.contains(pointInView) {
                        let swiftUIPoint = CGPoint(x: pointInView.x, y: self.bounds.height - pointInView.y)
                        let delta: CGFloat
                        if event.hasPreciseScrollingDeltas {
                            delta = event.scrollingDeltaY * 0.005
                        } else {
                            let step: CGFloat = 0.12
                            if event.scrollingDeltaY != 0 {
                                delta = event.scrollingDeltaY > 0 ? step : -step
                            } else if event.deltaY != 0 {
                                delta = event.deltaY > 0 ? step : -step
                            } else {
                                delta = 0
                            }
                        }
                        self.onZoom?(delta, swiftUIPoint)
                        return nil
                    }
                }
                return event
            }
        } else if window == nil, let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    deinit {
        if let m = monitor {
            NSEvent.removeMonitor(m)
        }
    }
}
#endif

private struct BoulderWallHoldMarker: View {
    let holdID: Int
    let role: BoulderHoldGroup?
    let isDimmed: Bool
    let showHoldID: Bool
    var isHovered: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            markerView
                .frame(width: isHovered ? 20 : 16, height: isHovered ? 20 : 16)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)

            if showHoldID {
                Text("\(holdID)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(isHovered ? 0.9 : 0.65))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .offset(y: isHovered ? -16 : -14)
            }
        }
        .opacity(isDimmed && !isHovered ? 0.45 : 1.0)
        .shadow(color: isHovered ? markerColor.opacity(0.85) : .clear, radius: 4)
    }

    @ViewBuilder
    private var markerView: some View {
        switch role {
        case .start:
            RoundedRectangle(cornerRadius: 2)
                .fill(markerColor.opacity(0.22))
                .overlay {
                    RoundedRectangle(cornerRadius: 2).stroke(markerColor, lineWidth: 2)
                }
        case .hold:
            Circle()
                .fill(markerColor.opacity(0.22))
                .overlay {
                    Circle().stroke(markerColor, lineWidth: 2)
                }
        case .foothold:
            Diamond()
                .fill(markerColor.opacity(0.22))
                .overlay {
                    Diamond().stroke(markerColor, lineWidth: 2)
                }
        case .top:
            RoundedRectangle(cornerRadius: 2)
                .fill(markerColor.opacity(0.22))
                .overlay {
                    RoundedRectangle(cornerRadius: 2).stroke(markerColor, lineWidth: 2)
                }
        case .none:
            Circle()
                .fill(markerColor.opacity(0.22))
                .overlay {
                    Circle().stroke(markerColor, lineWidth: 2)
                }
        }
    }

    private var markerColor: Color {
        switch role {
        case .start:
            return .green
        case .hold:
            return .blue
        case .foothold:
            return .yellow
        case .top:
            return .red
        case .none:
            return .white
        }
    }
}

private struct Diamond: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        path.move(to: CGPoint(x: insetRect.midX, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.midY))
        path.addLine(to: CGPoint(x: insetRect.midX, y: insetRect.maxY))
        path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.midY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
