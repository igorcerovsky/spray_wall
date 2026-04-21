import SwiftData
import SwiftUI

struct BoulderListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var appModel

    @Query(sort: \Boulder.updatedAt, order: .reverse) private var boulders: [Boulder]

    @State private var filterEstablishedOnly = false
    @State private var boulderToOpen: Boulder?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Established only", isOn: $filterEstablishedOnly)
                }

                Section("Boulders") {
                    if filteredBoulders.isEmpty {
                        Text("No boulders yet")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(filteredBoulders) { boulder in
                        NavigationLink {
                            BoulderEditorView(boulder: boulder)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(displayName(for: boulder))
                                        .font(.headline)
                                    Spacer()
                                    Text(boulder.status.displayName)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(boulder.status == .established ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }

                                HStack {
                                    Text("Difficulty: \(displayDifficulty(for: boulder))")
                                        .font(.footnote.weight(.bold))
                                    Spacer()
                                    Text("Ascents: \(totalAscents(for: boulder))")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                Text("#\(boulder.boulderID)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
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
        if filterEstablishedOnly {
            return boulders.filter { $0.status == .established }
        }
        return boulders
    }

    private func displayName(for boulder: Boulder) -> String {
        let trimmed = boulder.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    private func displayDifficulty(for boulder: Boulder) -> String {
        let trimmed = boulder.grade.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : trimmed
    }

    private func totalAscents(for boulder: Boulder) -> Int {
        boulder.ascentLogged ? 1 : 0
    }

    private func addBoulder() {
        do {
            let nextID = try nextBoulderID()
            let setter = appModel.currentUser?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let boulder = Boulder(
                boulderID: nextID,
                name: "Boulder \(nextID)",
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
}
