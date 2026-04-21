import SwiftData
import SwiftUI

@main
struct SprayWallApp: App {
    @State private var appModel = AppModel()
    private let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserAccount.self,
            Hold.self,
            Grip.self,
            Boulder.self,
            Route.self,
            Attempt.self,
            WallCalibration.self
        ])

        let fallbackDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let projectDirectory = (try? WallProjectPaths.ensureProjectDirectory()) ?? fallbackDirectory
        let storeURL = projectDirectory.appendingPathComponent("spraywall.sqlite")
        let configuration = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create model container at \(storeURL.path): \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
        }
        .modelContainer(sharedModelContainer)
    }
}
