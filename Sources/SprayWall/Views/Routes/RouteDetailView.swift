import SwiftData
import SwiftUI

struct RouteDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var appModel

    @Query(sort: \Hold.holdID) private var holds: [Hold]

    let route: Route

    @State private var name = ""
    @State private var startHoldsText = ""
    @State private var startFeetText = ""
    @State private var sequenceText = ""
    @State private var topHoldsText = ""
    @State private var topMode: TopMode = .match

    var body: some View {
        Form {
            Section("Route") {
                LabeledContent("ID", value: "#\(route.routeID)")
                TextField("Name", text: $name)
            }

            Section("Holds") {
                TextField("Start holds (ids)", text: $startHoldsText)
                TextField("Start feet (ids)", text: $startFeetText)
                TextField("Sequence (ids)", text: $sequenceText)
                TextField("Top holds (ids)", text: $topHoldsText)

                Picker("Top mode", selection: $topMode) {
                    ForEach(TopMode.allCases) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }

                Text("Use comma-separated hold IDs, e.g. 12,44,78,91")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Available Hold IDs") {
                Text(holds.map(\.holdID).map(String.init).joined(separator: ", "))
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button("Save Route") {
                save()
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle(route.name)
        .task {
            loadFromRoute()
        }
    }

    private func loadFromRoute() {
        name = route.name
        startHoldsText = route.startHoldIDsCSV
        startFeetText = route.startFootIDsCSV
        sequenceText = route.sequenceIDsCSV
        topHoldsText = route.topHoldIDsCSV
        topMode = route.topMode
    }

    private func save() {
        route.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        route.startHoldIDs = CSVIntCodec.decode(startHoldsText)
        route.startFootIDs = CSVIntCodec.decode(startFeetText)
        route.sequenceIDs = CSVIntCodec.decode(sequenceText)
        route.topHoldIDs = CSVIntCodec.decode(topHoldsText)
        route.topMode = topMode

        do {
            try modelContext.save()
            appModel.globalMessage = "Route saved."
        } catch {
            appModel.globalMessage = "Could not save route: \(error.localizedDescription)"
        }
    }
}
