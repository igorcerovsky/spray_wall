import SwiftData
import SwiftUI

struct AttemptLoggerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var appModel

    @Query(sort: \Attempt.date, order: .reverse) private var attempts: [Attempt]
    @Query(sort: \Route.routeID) private var routes: [Route]
    @Query(sort: \UserAccount.createdAt) private var users: [UserAccount]

    @State private var selectedRouteID: Int?
    @State private var result: AttemptResult = .success
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Log Attempt") {
                    if routes.isEmpty {
                        Text("Create at least one route before logging attempts.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Route", selection: routeBinding) {
                            ForEach(routes) { route in
                                Text("#\(route.routeID) \(route.name)").tag(Optional(route.routeID))
                            }
                        }

                        Picker("Result", selection: $result) {
                            ForEach(AttemptResult.allCases) { value in
                                Text(value.displayName).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)

                        TextField("Notes", text: $notes, axis: .vertical)
                            .lineLimit(2...4)

                        Button("Save Attempt") {
                            saveAttempt()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Section("History") {
                    if attempts.isEmpty {
                        Text("No attempts logged yet.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(attempts) { attempt in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(routeName(for: attempt.routeID))
                                .font(.headline)
                            Text(attempt.result.displayName)
                                .font(.subheadline)
                            Text(attempt.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Climber: \(climberName(for: attempt.climberID))")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if !attempt.notes.isEmpty {
                                Text(attempt.notes)
                                    .font(.footnote)
                            }
                        }
                    }
                    .onDelete(perform: deleteAttempts)
                }
            }
            .navigationTitle("Attempt Logger")
            .onAppear {
                if selectedRouteID == nil {
                    selectedRouteID = routes.first?.routeID
                }
            }
        }
    }

    private var routeBinding: Binding<Int?> {
        Binding(
            get: {
                selectedRouteID ?? routes.first?.routeID
            },
            set: { selectedRouteID = $0 }
        )
    }

    private func saveAttempt() {
        guard let user = appModel.currentUser else {
            appModel.globalMessage = "You must be signed in to log attempts."
            return
        }

        guard let routeID = selectedRouteID ?? routes.first?.routeID else {
            appModel.globalMessage = "Select a route first."
            return
        }

        do {
            let attemptID = try IDService.nextAttemptID(in: modelContext)
            let attempt = Attempt(
                attemptID: attemptID,
                routeID: routeID,
                climberID: user.id,
                result: result,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            modelContext.insert(attempt)
            try modelContext.save()
            notes = ""
            appModel.globalMessage = "Attempt saved."
        } catch {
            appModel.globalMessage = "Could not save attempt: \(error.localizedDescription)"
        }
    }

    private func deleteAttempts(at offsets: IndexSet) {
        for index in offsets {
            guard attempts.indices.contains(index) else { continue }
            modelContext.delete(attempts[index])
        }

        do {
            try modelContext.save()
        } catch {
            appModel.globalMessage = "Could not delete attempt: \(error.localizedDescription)"
        }
    }

    private func routeName(for routeID: Int) -> String {
        if let route = routes.first(where: { $0.routeID == routeID }) {
            return "#\(route.routeID) \(route.name)"
        }
        return "#\(routeID)"
    }

    private func climberName(for climberID: UUID) -> String {
        users.first(where: { $0.id == climberID })?.displayName ?? "Unknown"
    }
}
