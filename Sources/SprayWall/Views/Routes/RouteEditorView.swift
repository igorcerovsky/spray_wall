import SwiftData
import SwiftUI

struct RouteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var appModel

    @Query(sort: \Route.routeID) private var routes: [Route]

    @State private var selectedRouteID: Int?

    var body: some View {
        NavigationStack {
            List {
                Section("Active Route") {
                    if routes.isEmpty {
                        Text("No routes yet")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Route", selection: selectedRouteBinding) {
                            ForEach(routes) { route in
                                Text("#\(route.routeID) \(route.name)").tag(Optional(route.routeID))
                            }
                        }

                        if let route = activeRoute {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(route.name)
                                    .font(.headline)
                                Text("Start holds: \(route.startHoldIDs.map(String.init).joined(separator: ", "))")
                                Text("Start feet: \(route.startFootIDs.map(String.init).joined(separator: ", "))")
                                Text("Sequence: \(route.sequenceIDs.map(String.init).joined(separator: " -> "))")
                                Text("Top: \(route.topHoldIDs.map(String.init).joined(separator: ", "))")
                                Text("Top mode: \(route.topMode.rawValue)")
                            }
                            .font(.footnote)
                        }
                    }
                }

                Section("All Routes") {
                    ForEach(routes) { route in
                        NavigationLink {
                            RouteDetailView(route: route)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("#\(route.routeID) \(route.name)")
                                    .font(.headline)
                                Text(route.sequenceIDs.map(String.init).joined(separator: " -> "))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteRoutes)
                }
            }
            .navigationTitle("Route Editor")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addRoute()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .onAppear {
                if selectedRouteID == nil {
                    selectedRouteID = routes.first?.routeID
                }
            }
        }
    }

    private var selectedRouteBinding: Binding<Int?> {
        Binding(
            get: {
                if let selectedRouteID {
                    return selectedRouteID
                }
                return routes.first?.routeID
            },
            set: { selectedRouteID = $0 }
        )
    }

    private var activeRoute: Route? {
        if let selectedRouteID,
           let route = routes.first(where: { $0.routeID == selectedRouteID }) {
            return route
        }
        return routes.first
    }

    private func addRoute() {
        do {
            let routeID = try IDService.nextRouteID(in: modelContext)
            let route = Route(routeID: routeID, name: "Route \(routeID)")
            modelContext.insert(route)
            try modelContext.save()
            selectedRouteID = routeID
        } catch {
            appModel.globalMessage = "Could not create route: \(error.localizedDescription)"
        }
    }

    private func deleteRoutes(at offsets: IndexSet) {
        for index in offsets {
            guard routes.indices.contains(index) else { continue }
            modelContext.delete(routes[index])
        }

        do {
            try modelContext.save()
            if let selectedRouteID,
               routes.first(where: { $0.routeID == selectedRouteID }) == nil {
                self.selectedRouteID = routes.first?.routeID
            }
        } catch {
            appModel.globalMessage = "Could not delete route: \(error.localizedDescription)"
        }
    }
}
