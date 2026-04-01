import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if appModel.isAuthenticated {
                AppTabView()
            } else {
                AuthView()
            }
        }
        .task {
            appModel.bootstrap(context: modelContext)
            appModel.ensureCalibrationExists(context: modelContext)
        }
        .alert(
            "Message",
            isPresented: Binding(
                get: { appModel.globalMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        appModel.globalMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                appModel.globalMessage = nil
            }
        } message: {
            Text(appModel.globalMessage ?? "")
        }
    }
}
