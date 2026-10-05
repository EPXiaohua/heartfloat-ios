import SwiftUI

@main
struct HeartFloatApp: App {
    @StateObject private var viewModel = HeartRateViewModel()
    @StateObject private var settingsManager = SettingsManager.shared

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(viewModel)
                .environmentObject(settingsManager)
                .tint(Color(hex: "EC746F"))
        }
    }
}
