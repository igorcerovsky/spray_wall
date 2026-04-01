import SwiftUI

struct AppTabView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        TabView(selection: Bindable(appModel).selectedTab) {
            CalibrationView()
                .tabItem {
                    Label(AppModel.AppTab.calibration.title, systemImage: AppModel.AppTab.calibration.systemImage)
                }
                .tag(AppModel.AppTab.calibration)

            HoldEditorView()
                .tabItem {
                    Label(AppModel.AppTab.holds.title, systemImage: AppModel.AppTab.holds.systemImage)
                }
                .tag(AppModel.AppTab.holds)

            RouteEditorView()
                .tabItem {
                    Label(AppModel.AppTab.routes.title, systemImage: AppModel.AppTab.routes.systemImage)
                }
                .tag(AppModel.AppTab.routes)

            AttemptLoggerView()
                .tabItem {
                    Label(AppModel.AppTab.attempts.title, systemImage: AppModel.AppTab.attempts.systemImage)
                }
                .tag(AppModel.AppTab.attempts)

            SettingsView()
                .tabItem {
                    Label(AppModel.AppTab.settings.title, systemImage: AppModel.AppTab.settings.systemImage)
                }
                .tag(AppModel.AppTab.settings)
        }
    }
}
