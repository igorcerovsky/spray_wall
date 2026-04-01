import SwiftData
import SwiftUI

struct HoldDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var appModel

    let hold: Hold

    var body: some View {
        NavigationStack {
            Form {
                Section("Hold") {
                    LabeledContent("ID", value: "#\(hold.holdID)")

                    TextField("X (cm)", value: xBinding, format: .number)
                    TextField("Y (cm)", value: yBinding, format: .number)

                    Picker("Plane", selection: planeBinding) {
                        ForEach(HoldPlane.allCases) { plane in
                            Text(plane.rawValue.capitalized).tag(plane)
                        }
                    }

                    Picker("Role", selection: roleBinding) {
                        ForEach(HoldRole.allCases) { role in
                            Text(role.displayName).tag(role)
                        }
                    }

                    Toggle("Start", isOn: startBinding)
                    Toggle("Top", isOn: topBinding)
                    Toggle("Start Foot", isOn: startFootBinding)
                }

                Section("Grips") {
                    if hold.grips.isEmpty {
                        Text("No grips yet.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(hold.grips.sorted { $0.createdAt < $1.createdAt }) { grip in
                        GripRow(grip: grip)
                    }
                    .onDelete(perform: deleteGrip)

                    Button("Add Grip") {
                        addGrip()
                    }
                    .disabled(!hold.canAddGrip)
                }
            }
            .navigationTitle("Hold #\(hold.holdID)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        saveAndClose()
                    }
                }
            }
        }
    }

    private var xBinding: Binding<Double> {
        Binding(
            get: { hold.xCm },
            set: { hold.xCm = clamp($0, range: 0...WallSpec.widthCm) }
        )
    }

    private var yBinding: Binding<Double> {
        Binding(
            get: { hold.yCm },
            set: { hold.yCm = clamp($0, range: 0...WallSpec.totalHeightCm) }
        )
    }

    private var planeBinding: Binding<HoldPlane> {
        Binding(
            get: { hold.plane },
            set: { hold.plane = $0 }
        )
    }

    private var roleBinding: Binding<HoldRole> {
        Binding(
            get: { hold.role },
            set: { hold.role = $0 }
        )
    }

    private var startBinding: Binding<Bool> {
        Binding(
            get: { hold.isStart },
            set: { hold.isStart = $0 }
        )
    }

    private var topBinding: Binding<Bool> {
        Binding(
            get: { hold.isTop },
            set: { hold.isTop = $0 }
        )
    }

    private var startFootBinding: Binding<Bool> {
        Binding(
            get: { hold.isStartFoot },
            set: { hold.isStartFoot = $0 }
        )
    }

    private func addGrip() {
        let defaults = GripDefaults.forRole(hold.role)
        let grip = Grip(
            angleDeg: defaults.angle,
            strength: defaults.strength,
            precision: defaults.precision,
            hold: hold
        )
        modelContext.insert(grip)
        hold.grips.append(grip)
        persist()
    }

    private func deleteGrip(at offsets: IndexSet) {
        let ordered = hold.grips.sorted { $0.createdAt < $1.createdAt }
        for index in offsets {
            guard ordered.indices.contains(index) else { continue }
            let grip = ordered[index]
            modelContext.delete(grip)
        }
        persist()
    }

    private func saveAndClose() {
        persist()
        dismiss()
    }

    private func persist() {
        do {
            try modelContext.save()
        } catch {
            appModel.globalMessage = "Could not save hold changes: \(error.localizedDescription)"
        }
    }

    private func clamp(_ value: Double, range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

private struct GripRow: View {
    let grip: Grip

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(grip.id.uuidString.prefix(8))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            LabeledContent("Angle", value: "\(Int(grip.angleDeg)) deg")
            Slider(value: angleBinding, in: 0...360, step: 1)

            LabeledContent("Strength", value: String(format: "%.2f", grip.strength))
            Slider(value: strengthBinding, in: 0...1, step: 0.01)

            LabeledContent("Precision", value: String(format: "%.2f", grip.precision))
            Slider(value: precisionBinding, in: 0...1, step: 0.01)
        }
        .padding(.vertical, 4)
    }

    private var angleBinding: Binding<Double> {
        Binding(
            get: { grip.angleDeg },
            set: { grip.angleDeg = $0 }
        )
    }

    private var strengthBinding: Binding<Double> {
        Binding(
            get: { grip.strength },
            set: { grip.strength = $0 }
        )
    }

    private var precisionBinding: Binding<Double> {
        Binding(
            get: { grip.precision },
            set: { grip.precision = $0 }
        )
    }
}

private enum GripDefaults {
    static func forRole(_ role: HoldRole) -> (angle: Double, strength: Double, precision: Double) {
        switch role {
        case .hand:
            return (210, 0.5, 0.2)
        case .foot:
            return (180, 0.4, 0.45)
        case .microFoot:
            return (180, 0.3, 0.8)
        }
    }
}
