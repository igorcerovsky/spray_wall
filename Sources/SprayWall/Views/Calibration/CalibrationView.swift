import SwiftData
import SwiftUI

struct CalibrationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var appModel
    @Query(sort: \WallCalibration.updatedAt, order: .reverse) private var calibrations: [WallCalibration]

    @State private var photoPath = ""
    @State private var points = CalibrationPointTemplates.all

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
                    TextField("photo_original.jpg", text: $photoPath)

                    Text("Manual 8-point calibration is enabled for MVP.")
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
                    Text("main_wall_rectified.png")
                    Text("kickboard_rectified.png")
                }

                Button("Save Calibration") {
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
            .navigationTitle("Wall Calibration")
            .task {
                loadIfNeeded()
            }
        }
    }

    private func loadIfNeeded() {
        guard let calibration = calibrations.first else {
            return
        }

        photoPath = calibration.photoPath
        points = calibration.points
    }

    private func save() {
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
            appModel.globalMessage = "Calibration saved."
        } catch {
            appModel.globalMessage = "Could not save calibration: \(error.localizedDescription)"
        }
    }
}
