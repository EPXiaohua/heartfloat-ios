import Foundation
import SwiftUI
import UIKit
import Combine

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @AppStorage("bpmNumberSize") var bpmNumberSize: Double = 36
    @AppStorage("bpmNumberColorHex") var bpmNumberColorHex: String = "FF6B6B"
    @AppStorage("bpmLabelSize") var bpmLabelSize: Double = 14
    @AppStorage("bpmLabelColorHex") var bpmLabelColorHex: String = "FFFFFF"
    @AppStorage("bpmPosition") var bpmPosition: Int = 3
    @AppStorage("backgroundBrightness") var backgroundBrightness: Double = 0
    @AppStorage("httpPushEnabled") var httpPushEnabled: Bool = false
    @AppStorage("httpPushPort") var httpPushPort: Int = 8080
    @AppStorage("wsPushEnabled") var wsPushEnabled: Bool = false
    @AppStorage("wsPushPort") var wsPushPort: Int = 8081
    @AppStorage("checkUpdatesEnabled") var checkUpdatesEnabled: Bool = true
    /// 外观模式：0 跟随系统 1 浅色 2 深色
    @AppStorage("appearanceMode") var appearanceMode: Int = 0

    var bpmNumberColor: Color {
        get { Color(hex: bpmNumberColorHex) }
        set { bpmNumberColorHex = newValue.toHex() }
    }

    var bpmLabelColor: Color {
        get { Color(hex: bpmLabelColorHex) }
        set { bpmLabelColorHex = newValue.toHex() }
    }

    let positionOptions = ["上方", "下方", "左侧", "右侧"]
    let presetColors: [Color] = [
        Color(red: 1.0, green: 0.42, blue: 0.42),
        Color(red: 0.31, green: 0.80, blue: 0.77),
        Color(red: 0.27, green: 0.72, blue: 0.82),
        Color(red: 0.59, green: 0.81, blue: 0.71),
        Color(red: 1.0, green: 0.92, blue: 0.65),
        Color(red: 0.87, green: 0.90, blue: 0.91),
        Color(red: 1.0, green: 0.46, blue: 0.46),
        Color(red: 0.46, green: 0.73, blue: 1.0),
        Color(red: 0.64, green: 0.61, blue: 1.0),
        Color(red: 0.99, green: 0.47, blue: 0.66),
        Color(red: 0.0, green: 0.72, blue: 0.58),
        Color(red: 0.88, green: 0.44, blue: 0.33)
    ]

    func applyPresetClassic() {
        bpmNumberColor = Color(red: 1.0, green: 0.42, blue: 0.42)
        bpmLabelColor = .white
        bpmNumberSize = 36
        bpmLabelSize = 14
    }

    func applyPresetNeon() {
        bpmNumberColor = Color(red: 0.0, green: 1.0, blue: 0.53)
        bpmLabelColor = Color(red: 0.0, green: 1.0, blue: 1.0)
        bpmNumberSize = 40
        bpmLabelSize = 16
    }

    func applyPresetOcean() {
        bpmNumberColor = Color(red: 0.0, green: 0.75, blue: 1.0)
        bpmLabelColor = Color(red: 0.53, green: 0.81, blue: 0.92)
        bpmNumberSize = 38
        bpmLabelSize = 15
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 107, 107)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func toHex() -> String {
        guard let components = UIColor(self).cgColor.components else { return "FF6B6B" }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

// MARK: - 自动检查更新（GitHub Releases）

class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    static let releasesURL = URL(string: "https://github.com/EPXiaohua/heartfloat-ios/releases")!

    private static let apiURL = URL(string: "https://api.github.com/repos/EPXiaohua/heartfloat-ios/releases/latest")!

    struct ReleaseInfo {
        let version: String   // 标签去掉 v 前缀后的版本号
        let notes: String     // 发布说明
        let htmlURL: URL?
    }

    @Published var latestRelease: ReleaseInfo?

    /// 当前版本号（Info.plist 的 CFBundleShortVersionString）
    static var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "未知"
    }

    /// 启动时静默检查：只有发现新版本才回调；网络失败、已是最新都不打扰
    func checkOnLaunch(newVersionFound: @escaping (ReleaseInfo) -> Void) {
        fetch { release in
            guard let release = release,
                  Self.isNewer(release.version, than: Self.currentVersion) else { return }
            newVersionFound(release)
        }
    }

    /// 拉取最新 Release（失败回调 nil，不抛错）
    func fetch(completion: ((ReleaseInfo?) -> Void)? = nil) {
        var request = URLRequest(url: Self.apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self = self,
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    completion?(nil)
                    return
                }
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let release = ReleaseInfo(
                    version: version,
                    notes: Self.cleanNotes(json["body"] as? String ?? ""),
                    htmlURL: (json["html_url"] as? String).flatMap(URL.init(string:))
                )
                self.latestRelease = release
                completion?(release)
            }
        }.resume()
    }

    /// 版本号比较（按 '.' 分段数值比较）：lhs 比 rhs 新返回 true
    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let l = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let r = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(l.count, r.count) {
            let lv = i < l.count ? l[i] : 0
            let rv = i < r.count ? r[i] : 0
            if lv != rv { return lv > rv }
        }
        return false
    }

    /// 轻量清理发布说明的 Markdown 标记，适合纯文本展示
    static func cleanNotes(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "## ", with: "")
    }
}
