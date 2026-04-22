import SwiftData
import SwiftUI

struct BoulderListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var appModel

    @Query(sort: \Boulder.updatedAt, order: .reverse) private var boulders: [Boulder]

    @State private var filterEstablishedOnly = false
    @AppStorage("spraywall.boulder_filter_min_difficulty_index") private var minDifficultyIndex = 0
    @AppStorage("spraywall.boulder_filter_max_difficulty_index") private var maxDifficultyIndex = 25
    @State private var boulderToOpen: Boulder?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Established only", isOn: $filterEstablishedOnly)
                }

                Section("Difficulty Filter") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("From: \(Boulder.availableGrades[minDifficultyIndex])")
                            Spacer()
                            Text("To: \(Boulder.availableGrades[maxDifficultyIndex])")
                                .font(.subheadline.weight(.semibold))
                        }

                        DifficultyRangeSlider(
                            minIndex: $minDifficultyIndex,
                            maxIndex: $maxDifficultyIndex,
                            maxValue: Boulder.availableGrades.count - 1
                        )
                        .frame(height: 36)
                    }
                }

                Section("Boulders") {
                    if filteredBoulders.isEmpty {
                        Text("No boulders in selected difficulty range")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(filteredBoulders) { boulder in
                        NavigationLink {
                            BoulderEditorView(boulder: boulder)
                        } label: {
                            HStack(spacing: 8) {
                                Text(displayName(for: boulder))
                                    .font(.headline)
                                Text(displayDifficulty(for: boulder))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(displaySetter(for: boulder))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                if boulder.status == .draft {
                                    Text("Draft")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                Spacer()
                                if boulder.hasAscent(by: appModel.currentUser?.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Boulders")
            .navigationDestination(item: $boulderToOpen) { boulder in
                BoulderEditorView(boulder: boulder)
            }
            .onAppear {
                normalizeDifficultyFilterBounds()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addBoulder()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
        }
    }

    private var filteredBoulders: [Boulder] {
        boulders.filter { boulder in
            if filterEstablishedOnly, boulder.status != .established {
                return false
            }

            guard let difficultyIndex = difficultyIndex(for: boulder) else {
                return false
            }

            return difficultyIndex >= minDifficultyIndex && difficultyIndex <= maxDifficultyIndex
        }
    }

    private func displayName(for boulder: Boulder) -> String {
        let trimmed = boulder.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    private func displayDifficulty(for boulder: Boulder) -> String {
        Boulder.normalizedGrade(boulder.grade)
    }

    private func displaySetter(for boulder: Boulder) -> String {
        let trimmed = boulder.setter.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : trimmed
    }

    private func difficultyIndex(for boulder: Boulder) -> Int? {
        let normalized = boulder.grade
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return Boulder.availableGrades.firstIndex(of: normalized)
    }

    private func addBoulder() {
        do {
            let nextID = try nextBoulderID()
            let setter = appModel.currentUser?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let boulder = Boulder(
                boulderID: nextID,
                name: "Boulder \(nextID)",
                grade: Boulder.availableGrades.first ?? "1",
                setter: setter
            )
            modelContext.insert(boulder)
            try modelContext.save()
            boulderToOpen = boulder
        } catch {
            appModel.globalMessage = "Could not create boulder: \(error.localizedDescription)"
        }
    }

    private func nextBoulderID() throws -> Int {
        let descriptor = FetchDescriptor<Boulder>(sortBy: [SortDescriptor(\.boulderID, order: .reverse)])
        let latest = try modelContext.fetch(descriptor).first
        return (latest?.boulderID ?? 0) + 1
    }

    private func delete(at offsets: IndexSet) {
        let current = filteredBoulders

        for index in offsets {
            guard current.indices.contains(index) else { continue }
            modelContext.delete(current[index])
        }

        do {
            try modelContext.save()
        } catch {
            appModel.globalMessage = "Could not delete boulder: \(error.localizedDescription)"
        }
    }

    private func normalizeDifficultyFilterBounds() {
        let maxAllowed = Boulder.availableGrades.count - 1
        minDifficultyIndex = max(0, min(minDifficultyIndex, maxAllowed))
        maxDifficultyIndex = max(0, min(maxDifficultyIndex, maxAllowed))
        if minDifficultyIndex > maxDifficultyIndex {
            maxDifficultyIndex = minDifficultyIndex
        }
    }
}

private struct DifficultyRangeSlider: View {
    @Binding var minIndex: Int
    @Binding var maxIndex: Int
    let maxValue: Int

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let stepWidth = width / CGFloat(max(1, maxValue))
            let minX = CGFloat(minIndex) * stepWidth
            let maxX = CGFloat(maxIndex) * stepWidth

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: 6)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(6, maxX - minX), height: 6)
                    .offset(x: minX)

                thumb
                    .position(x: minX, y: geometry.size.height / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let clampedX = clamp(value.location.x, min: 0, max: width)
                                let newMin = index(for: clampedX, width: width)
                                minIndex = min(newMin, maxIndex)
                            }
                    )

                thumb
                    .position(x: maxX, y: geometry.size.height / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let clampedX = clamp(value.location.x, min: 0, max: width)
                                let newMax = index(for: clampedX, width: width)
                                maxIndex = max(newMax, minIndex)
                            }
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var thumb: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 18, height: 18)
            .overlay {
                Circle().stroke(Color.accentColor, lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
    }

    private func index(for x: CGFloat, width: CGFloat) -> Int {
        let ratio = clamp(x / max(width, 1), min: 0, max: 1)
        let raw = Int((ratio * CGFloat(maxValue)).rounded())
        return max(0, min(maxValue, raw))
    }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minValue), maxValue)
    }
}
