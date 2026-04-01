import PhotosUI
import SwiftData
import SwiftUI

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
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section("Wall") {
                    LabeledContent("Width", value: "\(Int(WallSpec.widthCm)) cm")
                    LabeledContent("Main Wall", value: "\(Int(WallSpec.mainWallHeightCm)) cm @ \(Int(WallSpec.mainWallAngleDegFromFloor)) deg")
                    LabeledContent("Kickboard", value: "\(Int(WallSpec.kickboardHeightCm)) cm @ \(Int(WallSpec.kickboardAngleDegFromFloor)) deg")
                    LabeledContent("Rectification", value: "1 px = 0.5 cm")
                }

                Section("Photo") {
                    let pickerTitle = isImportingPhoto ? "Importing Photo..." : "Pick Photo from Library"

                    TextField("photo_original.jpg", text: $photoPath)
                        .disabled(isImportingPhoto || isRectifying)

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(pickerTitle, systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(isImportingPhoto || isRectifying)

                    Text("Manual 8-point calibration is enabled for MVP.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Use absolute path or a file inside wall_project folder.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Reference Points") {
                    ForEach($points) { $point in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(point.label)
                                .font(.subheadline.weight(.medium))

                            HStack {
                                TextField("X px", value: $point.xPx, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Y px", value: $point.yPx, format: .number)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Output") {
                    LabeledContent("Main Wall") {
                        Text(mainWallOutputPath.isEmpty ? "main_wall_rectified.png" : mainWallOutputPath)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    LabeledContent("Kickboard") {
                        Text(kickboardOutputPath.isEmpty ? "kickboard_rectified.png" : kickboardOutputPath)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Button(isRectifying ? "Rectifying..." : "Generate Rectified Images") {
                        generateRectifiedImages()
                    }
                    .disabled(isRectifying || isImportingPhoto)
                }

                Button("Save Calibration") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRectifying || isImportingPhoto)
            }
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
        }
    }

    private func loadIfNeeded() {
        if let calibration = calibrations.first {
            photoPath = calibration.photoPath
            points = calibration.points
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

            photoPath = output.photoOriginalURL.path
            mainWallOutputPath = output.mainWallURL.path
            kickboardOutputPath = output.kickboardURL.path

            save(showMessage: false)
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
            let destinationURL = try WallProjectPaths.defaultPhotoOriginalURL()

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try data.write(to: destinationURL, options: .atomic)

            photoPath = destinationURL.path
            save(showMessage: false)
            appModel.globalMessage = "Photo imported to wall_project/photo_original.jpg."
        } catch {
            appModel.globalMessage = "Photo import failed: \(error.localizedDescription)"
        }
    }
}
