import Foundation
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
        let primaryStoreURL = (try? WallProjectPaths.primaryModelStoreURL()) ?? fallbackDirectory.appendingPathComponent("spraywall.sqlite")

        if let primary = createContainer(schema: schema, storeURL: primaryStoreURL) {
            return primary
        }

        // Legacy fallback: open the default SwiftData store path so old data remains available.
        if let legacy = try? ModelContainer(for: schema) {
            return legacy
        }

        let fallbackStoreURL = fallbackDirectory.appendingPathComponent("spraywall-fallback.sqlite")
        if let fallback = createContainer(schema: schema, storeURL: fallbackStoreURL) {
            return fallback
        }

        fatalError("Failed to create model container at primary, legacy, and fallback locations.")
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
        }
        .modelContainer(sharedModelContainer)
    }

    private static func createContainer(schema: Schema, storeURL: URL) -> ModelContainer? {
        let configuration = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
        return try? ModelContainer(for: schema, configurations: [configuration])
    }
}
