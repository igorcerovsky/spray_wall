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

            BoulderListView()
                .tabItem {
                    Label(AppModel.AppTab.boulder.title, systemImage: AppModel.AppTab.boulder.systemImage)
                }
                .tag(AppModel.AppTab.boulder)

            SettingsView()
                .tabItem {
                    Label(AppModel.AppTab.settings.title, systemImage: AppModel.AppTab.settings.systemImage)
                }
                .tag(AppModel.AppTab.settings)
        }
    }
}
