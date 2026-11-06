import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct CalibrationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var appModel
    @Query(sort: \WallCalibration.updatedAt, order: .reverse) private var calibrations: [WallCalibration]

    @State private var photoPath = ""
    @State private var points = CalibrationPointTemplates.all
    @State private var mainWallOutputPath = ""
    @State private var kickboardOutputPath = ""
    @State private var isRectifying = false
    @State private var isImportingPhoto = false
    @State private var isFileImporterPresented = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isShowingInteractiveEditor = false
    @State private var previewId = UUID()

    var body: some View {
        NavigationStack {
            List {
                Section("Wall") {
                    LabeledContent("Width", value: "\(Int(WallSpec.widthCm)) cm")
                    LabeledContent("Main Wall", value: "\(Int(WallSpec.mainWallHeightCm)) cm @ \(Int(WallSpec.mainWallAngleDegFromFloor)) deg")
                    LabeledContent("Kickboard", value: "\(Int(WallSpec.kickboardHeightCm)) cm @ \(Int(WallSpec.kickboardAngleDegFromFloor)) deg")
                    LabeledContent("Rectification", value: "1 px = 0.5 cm")
                }

                Section("Photo") {
                    let pickerTitle = isImportingPhoto ? "Importing..." : "Pick Photo from Library"
                    let fileTitle = isImportingPhoto ? "Importing..." : "Import Image from Computer"

                    TextField("resources/281026_dd.jpeg", text: $photoPath)
                        .disabled(isImportingPhoto || isRectifying)

                    HStack(spacing: 12) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label(pickerTitle, systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isImportingPhoto || isRectifying)

                        Button {
                            isFileImporterPresented = true
                        } label: {
                            Label(fileTitle, systemImage: "folder")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isImportingPhoto || isRectifying)
                    }

                    Text("Manual 8-point calibration is enabled for MVP.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Each reference point maps image x/y (px) to world x/y (cm).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Origin is bottom-left (0,0) for both image and world coordinates.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Use absolute path or a file inside wall_project folder.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Coordinate Pairs (Image px -> World cm)") {
                    Button {
                        isShowingInteractiveEditor = true
                    } label: {
                        Label("Edit Interactively", systemImage: "hand.draw")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.bordered)
                    .padding(.vertical, 4)

                    ForEach($points) { $point in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(point.label)
                                .font(.subheadline.weight(.medium))

                            HStack(spacing: 8) {
                                Text("Image")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 48, alignment: .leading)

                                TextField("X px", value: $point.xPx, format: .number.precision(.fractionLength(0)))
                                    .textFieldStyle(.roundedBorder)
                                TextField("Y px", value: $point.yPx, format: .number.precision(.fractionLength(0)))
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack(spacing: 8) {
                                Text("World")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 48, alignment: .leading)

                                TextField("X cm", value: $point.xCm, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Y cm", value: $point.yCm, format: .number)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button("Reset World Coordinates to Wall Defaults") {
                        resetWorldCoordinates()
                    }
                    .disabled(isRectifying || isImportingPhoto)
                }

                Section("Output") {
                    FileImagePreview(
                        title: "Original Photo",
                        fileURL: previewURL(for: photoPath),
                        placeholderText: "No photo available."
                    )

                    LabeledContent("Main Wall") {
                        Text(mainWallOutputPath.isEmpty ? "main_wall_rectified.png" : mainWallOutputPath)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    FileImagePreview(
                        title: "Main Wall Preview",
                        fileURL: previewURL(for: mainWallOutputPath),
                        placeholderText: "Generate rectified main wall image."
                    )

                    LabeledContent("Kickboard") {
                        Text(kickboardOutputPath.isEmpty ? "kickboard_rectified.png" : kickboardOutputPath)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    FileImagePreview(
                        title: "Kickboard Preview",
                        fileURL: previewURL(for: kickboardOutputPath),
                        placeholderText: "Generate rectified kickboard image."
                    )

                    Button(isRectifying ? "Applying Calibration..." : "Apply Calibration") {
                        generateRectifiedImages()
                    }
                    .disabled(isRectifying || isImportingPhoto)

                    Text("Applies coordinate mapping and regenerates rectified wall images.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .id(previewId)

                Button("Save Calibration") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRectifying || isImportingPhoto)
            }
            .listStyle(.automatic)
            .navigationTitle("Wall Calibration")
            .task {
                loadIfNeeded()
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    await importPhoto(from: newItem)
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.image]
            ) { result in
                switch result {
                case .success(let url):
                    Task {
                        await importPhoto(fromFile: url)
                    }
                case .failure(let error):
                    appModel.globalMessage = "File selection failed: \(error.localizedDescription)"
                }
            }
        }
        .sheet(isPresented: $isShowingInteractiveEditor) {
            InteractiveCalibrationEditor(
                points: $points,
                photoURL: previewURL(for: photoPath),
                onSave: {
                    // Slight delay to allow the sheet to start dismissing
                    Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        generateRectifiedImages()
                    }
                }
            )
        }
    }

    private func loadIfNeeded() {
        var needsMigrationSave = false

        if let calibration = calibrations.first {
            let normalizedPoints = CalibrationPointTemplates.normalized(calibration.points)
            let hasLegacyZeroPixels = normalizedPoints.allSatisfy { $0.xPx == 0 && $0.yPx == 0 }

            if hasLegacyZeroPixels {
                points = CalibrationPointTemplates.all
                calibration.points = points
                needsMigrationSave = true
            } else {
                points = normalizedPoints
            }

            let trimmedPhotoPath = calibration.photoPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedPhotoPath.isEmpty
                || trimmedPhotoPath.contains("photo_original.jpg")
                || trimmedPhotoPath.contains("photo original.jpg")
                || trimmedPhotoPath.hasSuffix("wall.jpg") {
                photoPath = WallCalibration.defaultPhotoPath
                calibration.photoPath = photoPath
                needsMigrationSave = true
            } else {
                photoPath = calibration.photoPath
            }
        } else {
            points = CalibrationPointTemplates.all
            photoPath = WallCalibration.defaultPhotoPath
        }

        if needsMigrationSave {
            do {
                try modelContext.save()
            } catch {
                appModel.globalMessage = "Could not migrate calibration defaults: \(error.localizedDescription)"
            }
        }

        refreshOutputPaths()
    }

    private func save(showMessage: Bool = true) {
        let calibration: WallCalibration
        if let existing = calibrations.first {
            calibration = existing
        } else {
            let created = WallCalibration()
            modelContext.insert(created)
            calibration = created
        }

        points = CalibrationPointTemplates.normalized(points)
        calibration.photoPath = photoPath
        calibration.points = points

        do {
            try modelContext.save()
            if showMessage {
                appModel.globalMessage = "Calibration saved."
            }
        } catch {
            appModel.globalMessage = "Could not save calibration: \(error.localizedDescription)"
        }
    }

    private func generateRectifiedImages() {
        isRectifying = true
        defer { isRectifying = false }

        do {
            save(showMessage: false)

            let photoURL = try WallProjectPaths.resolvePhotoURL(from: photoPath)
            let outputDirectory = try WallProjectPaths.ensureProjectDirectory()
            let output = try ImageRectificationService.rectify(
                photoURL: photoURL,
                points: points,
                outputDirectory: outputDirectory
            )

            if photoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                photoPath = WallCalibration.defaultPhotoPath
            }
            mainWallOutputPath = output.mainWallURL.path
            kickboardOutputPath = output.kickboardURL.path

            save(showMessage: false)
            previewId = UUID()
            appModel.globalMessage = "Rectified images generated."
        } catch {
            appModel.globalMessage = "Rectification failed: \(error.localizedDescription)"
        }
    }

    private func refreshOutputPaths() {
        let manager = FileManager.default

        if let mainURL = try? WallProjectPaths.defaultMainWallRectifiedURL(),
           manager.fileExists(atPath: mainURL.path) {
            mainWallOutputPath = mainURL.path
        }

        if let kickboardURL = try? WallProjectPaths.defaultKickboardRectifiedURL(),
           manager.fileExists(atPath: kickboardURL.path) {
            kickboardOutputPath = kickboardURL.path
        }
    }

    private func previewURL(for path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let resolved = try? WallProjectPaths.resolvePhotoURL(from: trimmed) {
            return resolved
        }

        let fileManager = FileManager.default
        let absolute = URL(fileURLWithPath: trimmed)
        if fileManager.fileExists(atPath: absolute.path) {
            return absolute
        }

        if let projectDirectory = try? WallProjectPaths.projectDirectory() {
            let relative = projectDirectory.appendingPathComponent(trimmed)
            if fileManager.fileExists(atPath: relative.path) {
                return relative
            }
        }

        return nil
    }

    private func resetWorldCoordinates() {
        points = points.map { point in
            guard let coordinate = CalibrationPointTemplates.defaultWorldCoordinate(for: point.id) else {
                return point
            }

            return CalibrationPoint(
                id: point.id,
                label: point.label,
                xPx: point.xPx,
                yPx: point.yPx,
                xCm: coordinate.x,
                yCm: coordinate.y
            )
        }
    }

    @MainActor
    private func importPhoto(from item: PhotosPickerItem) async {
        isImportingPhoto = true
        defer {
            isImportingPhoto = false
            selectedPhotoItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                appModel.globalMessage = "Selected photo could not be loaded."
                return
            }

            _ = try WallProjectPaths.ensureProjectDirectory()
            let projectDir = try WallProjectPaths.projectDirectory()
            let destinationURL = projectDir.appendingPathComponent("photo_original.jpg")

            for ext in ["jpg", "jpeg", "png", "heic"] {
                let candidate = projectDir.appendingPathComponent("photo_original.\(ext)")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    try? FileManager.default.removeItem(at: candidate)
                }
            }

            try data.write(to: destinationURL, options: .atomic)

            await OriginalPhotoLoader.shared.clearCache()
            photoPath = destinationURL.path
            previewId = UUID()
            save(showMessage: false)
            appModel.globalMessage = "Photo imported to wall_project/photo_original.jpg."
        } catch {
            appModel.globalMessage = "Photo import failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func importPhoto(fromFile url: URL) async {
        isImportingPhoto = true
        defer {
            isImportingPhoto = false
        }

        let gotAccess = url.startAccessingSecurityScopedResource()
        defer {
            if gotAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)

            _ = try WallProjectPaths.ensureProjectDirectory()
            let projectDir = try WallProjectPaths.projectDirectory()
            let fileExtension = url.pathExtension.isEmpty ? "jpg" : url.pathExtension.lowercased()
            let destinationURL = projectDir.appendingPathComponent("photo_original.\(fileExtension)")

            for ext in ["jpg", "jpeg", "png", "heic"] {
                let candidate = projectDir.appendingPathComponent("photo_original.\(ext)")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    try? FileManager.default.removeItem(at: candidate)
                }
            }

            try data.write(to: destinationURL, options: .atomic)

            await OriginalPhotoLoader.shared.clearCache()
            photoPath = destinationURL.path
            previewId = UUID()
            save(showMessage: false)
            appModel.globalMessage = "Photo imported to wall_project/photo_original.\(fileExtension)."
        } catch {
            appModel.globalMessage = "Photo import failed: \(error.localizedDescription)"
        }
    }
}

private struct FileImagePreview: View {
    let title: String
    let fileURL: URL?
    let placeholderText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))

            if let fileURL {
                AsyncImage(url: fileURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .failure:
                        Text("Could not load image at \(fileURL.path)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Text(placeholderText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
