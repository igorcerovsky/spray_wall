import SwiftData
import SwiftUI

@main
struct SprayWallApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
        }
        .modelContainer(for: [
            UserAccount.self,
            Hold.self,
            Grip.self,
            Route.self,
            Attempt.self,
            WallCalibration.self
        ])
    }
}
