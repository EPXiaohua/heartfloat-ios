import SwiftUI
import UIKit

@main
struct HeartFloatApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = HeartRateViewModel()
    @StateObject private var settingsManager = SettingsManager.shared

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(viewModel)
                .environmentObject(settingsManager)
                .tint(Color(hex: "EC746F"))
                .preferredColorScheme(appearanceColorScheme)
        }
    }

    /// 外观模式：0 跟随系统 1 浅色 2 深色
    private var appearanceColorScheme: ColorScheme? {
        switch settingsManager.appearanceMode {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }
}

/// 全屏图表横屏时允许横屏方向，其余时候锁定竖屏
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationManager.shared.isLandscape ? .landscapeRight : .portrait
    }
}

/// 全屏图表的方向控制器
class OrientationManager {
    static let shared = OrientationManager()
    var isLandscape = false

    func enterLandscape() {
        isLandscape = true
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }

    func exitLandscape() {
        isLandscape = false
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }
}
