import SwiftData
import SwiftUI

struct HoldEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var appModel

    @Query(sort: \Hold.holdID) private var holds: [Hold]

    @State private var selectedRole: HoldRole = .hand
    @State private var newHoldIsStart = false
    @State private var newHoldIsTop = false
    @State private var newHoldIsStartFoot = false
    @State private var colorBlindMode = false

    @State private var editingHold: Hold?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                controls

                GeometryReader { geometry in
                    ZStack {
                        wallBackground(size: geometry.size)

                        ForEach(holds) { hold in
                            HoldMarkerView(hold: hold, colorBlindMode: colorBlindMode)
                                .position(position(for: hold, size: geometry.size))
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            move(hold: hold, to: value.location, size: geometry.size)
                                        }
                                        .onEnded { _ in
                                            persist()
                                        }
                                )
                                .onTapGesture {
                                    editingHold = hold
                                }
                                .contextMenu {
                                    Button("Edit Grips") {
                                        editingHold = hold
                                    }
                                    Button("Delete Hold", role: .destructive) {
                                        delete(hold: hold)
                                    }
                                }
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                addHold(at: value.location, size: geometry.size)
                            }
                    )
                }
                .frame(minHeight: 320)

                List(holds.prefix(8)) { hold in
                    HStack {
                        Text("#\(hold.holdID)")
                            .font(.headline.monospacedDigit())
                        Text("\(Int(hold.xCm)), \(Int(hold.yCm)) cm")
                            .font(.subheadline)
                        Spacer()
                        Text(hold.role.displayName)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingHold = hold
                    }
                }
                .listStyle(.plain)
                .frame(maxHeight: 220)
            }
            .padding()
            .navigationTitle("Hold Editor")
            .sheet(item: $editingHold) { hold in
                HoldDetailView(hold: hold)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Picker("Role", selection: $selectedRole) {
                ForEach(HoldRole.allCases) { role in
                    Text(role.displayName).tag(role)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Toggle("Start", isOn: $newHoldIsStart)
                Toggle("Top", isOn: $newHoldIsTop)
                Toggle("Start Foot", isOn: $newHoldIsStartFoot)
            }

            Toggle("Color-blind mode", isOn: $colorBlindMode)
                .toggleStyle(.switch)

            Text("Tap wall to add, drag marker to move, long press for delete.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func wallBackground(size: CGSize) -> some View {
        let kickboardHeight = size.height * (WallSpec.kickboardHeightCm / WallSpec.totalHeightCm)

        return ZStack(alignment: .bottom) {
            Rectangle()
                .fill(Color.gray.opacity(0.2))

            Rectangle()
                .fill(Color.brown.opacity(0.22))
                .frame(height: kickboardHeight)

            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(height: 1)
                .offset(y: -(kickboardHeight))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func addHold(at location: CGPoint, size: CGSize) {
        do {
            let holdID = try IDService.nextHoldID(in: modelContext)
            let xCm = max(0, min(WallSpec.widthCm, (location.x / size.width) * WallSpec.widthCm))
            let yCm = max(0, min(WallSpec.totalHeightCm, (1 - (location.y / size.height)) * WallSpec.totalHeightCm))
            let plane: HoldPlane = yCm <= WallSpec.kickboardHeightCm ? .kickboard : .main

            let hold = Hold(
                holdID: holdID,
                xCm: xCm,
                yCm: yCm,
                plane: plane,
                role: selectedRole,
                isStart: newHoldIsStart,
                isTop: newHoldIsTop,
                isStartFoot: newHoldIsStartFoot
            )
            modelContext.insert(hold)
            persist()
        } catch {
            appModel.globalMessage = "Could not create hold: \(error.localizedDescription)"
        }
    }

    private func move(hold: Hold, to location: CGPoint, size: CGSize) {
        hold.xCm = max(0, min(WallSpec.widthCm, (location.x / size.width) * WallSpec.widthCm))
        hold.yCm = max(0, min(WallSpec.totalHeightCm, (1 - (location.y / size.height)) * WallSpec.totalHeightCm))
        hold.plane = hold.yCm <= WallSpec.kickboardHeightCm ? .kickboard : .main
    }

    private func delete(hold: Hold) {
        modelContext.delete(hold)
        persist()
    }

    private func persist() {
        do {
            try modelContext.save()
        } catch {
            appModel.globalMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func position(for hold: Hold, size: CGSize) -> CGPoint {
        let x = (hold.xCm / WallSpec.widthCm) * size.width
        let y = (1 - (hold.yCm / WallSpec.totalHeightCm)) * size.height
        return CGPoint(x: x, y: y)
    }
}
