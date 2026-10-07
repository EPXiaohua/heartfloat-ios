import SwiftUI
import Foundation
import UIKit
import UniformTypeIdentifiers

// 记录图表主题色（与主界面曲线一致）
private let recordingThemeColor = Color(red: 1.0, green: 0.42, blue: 0.42)

// MARK: - 设置主页（分组路径）

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var viewModel: HeartRateViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    NavigationLink(destination: GeneralSettingsView()) {
                        Label("通用", systemImage: "gearshape")
                    }
                    NavigationLink(destination: PipSettingsView()) {
                        Label("悬浮窗设置", systemImage: "pip.enter")
                    }
                    NavigationLink(destination: RecordingsListView()) {
                        Label("心率记录", systemImage: "waveform.path.ecg")
                    }
                    NavigationLink(destination: BleDeviceSettingsView()) {
                        Label("蓝牙设备", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    NavigationLink(destination: PushServiceSettingsView()) {
                        Label("推送服务", systemImage: "dot.radiowaves.up.forward")
                    }
                    NavigationLink(destination: StorageManageView()) {
                        Label("存储管理", systemImage: "internaldrive")
                    }
                    NavigationLink(destination: AboutView()) {
                        Label("关于", systemImage: "info.circle")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - 通用设置

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        List {
            Section(footer: Text("「跟随系统」时应用配色随 iOS 深色模式自动切换。")) {
                Picker("外观", selection: $settings.appearanceMode) {
                    Text("跟随系统").tag(0)
                    Text("浅色").tag(1)
                    Text("深色").tag(2)
                }
            }

            Section(footer: Text("关闭后，长按菜单、选择模式、复制地址等操作不再震动。")) {
                Toggle("触感反馈", isOn: $settings.hapticsEnabled)
            }

            Section(footer: Text("开启后屏幕不会自动熄灭，适合把心率挂在屏幕上查看；会更耗电。")) {
                Toggle("屏幕常亮", isOn: $settings.keepScreenOn)
                    .onChange(of: settings.keepScreenOn) { _ in
                        settings.applyKeepScreenOn()
                    }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("通用")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 悬浮窗设置

struct PipSettingsView: View {
    @EnvironmentObject var settings: SettingsManager

    @State private var showingColorPicker = false
    @State private var colorPickerTarget: ColorPickerTarget = .bpmNumber

    enum ColorPickerTarget {
        case bpmNumber
        case bpmLabel
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                previewSection

                bpmNumberSettings

                bpmLabelSettings

                positionSettings

                backgroundSettings

                presetSection
            }
            .padding()
        }
        .navigationTitle("悬浮窗设置")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingColorPicker) {
            ColorPickerSheet(
                selectedColor: colorPickerTarget == .bpmNumber ? settings.bpmNumberColor : settings.bpmLabelColor,
                onColorSelected: { color in
                    if colorPickerTarget == .bpmNumber {
                        settings.bpmNumberColor = color
                    } else {
                        settings.bpmLabelColor = color
                    }
                }
            )
        }
    }

    private var previewSection: some View {
        VStack(spacing: 8) {
            Text("预览")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(white: settings.backgroundBrightness / 100))
                    .frame(height: 80)

                if settings.bpmPosition == 0 || settings.bpmPosition == 1 {
                    // 纵向排列：BPM 在上 / 下
                    VStack(spacing: 2) {
                        if settings.bpmPosition == 0 {
                            Text("BPM")
                                .font(.system(size: settings.bpmLabelSize))
                                .foregroundColor(settings.bpmLabelColor)
                        }
                        Text("88")
                            .font(.system(size: min(settings.bpmNumberSize, 32), weight: .bold))
                            .foregroundColor(settings.bpmNumberColor)
                        if settings.bpmPosition == 1 {
                            Text("BPM")
                                .font(.system(size: settings.bpmLabelSize))
                                .foregroundColor(settings.bpmLabelColor)
                        }
                    }
                } else {
                    // 横向排列：BPM 在左 / 右
                    HStack(spacing: 4) {
                        if settings.bpmPosition == 2 {
                            Text("BPM")
                                .font(.system(size: settings.bpmLabelSize))
                                .foregroundColor(settings.bpmLabelColor)
                        }
                        Text("88")
                            .font(.system(size: settings.bpmNumberSize, weight: .bold))
                            .foregroundColor(settings.bpmNumberColor)
                        if settings.bpmPosition == 3 {
                            Text("BPM")
                                .font(.system(size: settings.bpmLabelSize))
                                .foregroundColor(settings.bpmLabelColor)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var bpmNumberSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BPM数字设置")
                .font(.system(size: 16, weight: .bold))

            HStack {
                Text("文字大小")
                    .foregroundColor(.secondary)
                Slider(value: $settings.bpmNumberSize, in: 12...48, step: 1)
                Text("\(Int(settings.bpmNumberSize))")
                    .frame(width: 40)
            }

            HStack {
                Text("文字颜色")
                    .foregroundColor(.secondary)
                Spacer()
                ColorPicker("", selection: $settings.bpmNumberColor)
                    .labelsHidden()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var bpmLabelSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BPM文字设置")
                .font(.system(size: 16, weight: .bold))

            HStack {
                Text("文字大小")
                    .foregroundColor(.secondary)
                Slider(value: $settings.bpmLabelSize, in: 8...32, step: 1)
                Text("\(Int(settings.bpmLabelSize))")
                    .frame(width: 40)
            }

            HStack {
                Text("文字颜色")
                    .foregroundColor(.secondary)
                Spacer()
                ColorPicker("", selection: $settings.bpmLabelColor)
                    .labelsHidden()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var positionSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("位置设置")
                .font(.system(size: 16, weight: .bold))

            Picker("位置", selection: $settings.bpmPosition) {
                Text("上方").tag(0)
                Text("下方").tag(1)
                Text("左侧").tag(2)
                Text("右侧").tag(3)
            }
            .pickerStyle(SegmentedPickerStyle())
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var backgroundSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("背景设置")
                .font(.system(size: 16, weight: .bold))

            HStack {
                Text("背景亮度")
                    .foregroundColor(.secondary)
                Text("黑")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Slider(value: $settings.backgroundBrightness, in: 0...100, step: 1)
                Text("白")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("\(Int(settings.backgroundBrightness))")
                    .frame(width: 40)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("预设方案")
                .font(.system(size: 16, weight: .bold))

            HStack(spacing: 12) {
                Button(action: { settings.applyPresetClassic() }) {
                    VStack {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.42, blue: 0.42))
                            .frame(width: 40, height: 40)
                        Text("经典")
                            .font(.system(size: 12))
                    }
                }
                .foregroundColor(.primary)

                Button(action: { settings.applyPresetNeon() }) {
                    VStack {
                        Circle()
                            .fill(Color(red: 0.0, green: 1.0, blue: 0.53))
                            .frame(width: 40, height: 40)
                        Text("霓虹")
                            .font(.system(size: 12))
                    }
                }
                .foregroundColor(.primary)

                Button(action: { settings.applyPresetOcean() }) {
                    VStack {
                        Circle()
                            .fill(Color(red: 0.0, green: 0.75, blue: 1.0))
                            .frame(width: 40, height: 40)
                        Text("海洋")
                            .font(.system(size: 12))
                    }
                }
                .foregroundColor(.primary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - 推送服务（HTTP + WebSocket）

struct PushServiceSettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var viewModel: HeartRateViewModel
    @ObservedObject private var httpServer = HttpServerManager.shared
    @ObservedObject private var wsServer = WsServerManager.shared
    @Environment(\.openURL) private var openURL

    @State private var httpPort: String = "8080"
    @State private var wsPort: String = "8081"
    @State private var showingPortAlert = false
    @State private var portAlertMessage = ""
    // 复制成功的顶部 Toast（设置页在 sheet 内，MainView 的 Toast 被遮挡，本页单独显示）
    @State private var toastText: String?
    @State private var toastToken = UUID()

    private let themeColor = Color(hex: "EC746F")

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                httpPushSection
                wsPushSection
                networkNote
            }
            .padding()
        }
        .navigationTitle("推送服务")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            httpPort = "\(settings.httpPushPort)"
            wsPort = "\(settings.wsPushPort)"
            httpServer.refreshIPs()
        }
        .alert("提示", isPresented: $showingPortAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(portAlertMessage)
        }
        // 底部 Toast（复制成功提示，复用全局毛玻璃样式）
        .overlay(alignment: .bottom) {
            VStack {
                Spacer()
                if let toast = toastText {
                    ToastView(text: toast)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: toastText)
            .allowsHitTesting(false)
        }
    }

    // MARK: HTTP 实时推送

    private var httpPushSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HTTP 实时推送")
                .font(.system(size: 16, weight: .bold))

            Toggle("启用 HTTP 推送", isOn: $settings.httpPushEnabled)
                .onChange(of: settings.httpPushEnabled) { enabled in
                    if enabled {
                        viewModel.startHttpServer(port: settings.httpPushPort)
                    } else {
                        viewModel.stopHttpServer()
                    }
                }

            if settings.httpPushEnabled {
                HStack {
                    Text("端口")
                        .foregroundColor(.secondary)
                    TextField("端口号", text: $httpPort)
                        .keyboardType(.numberPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 100)

                    Button("应用", action: applyHttpPort)
                        .foregroundColor(themeColor)
                }

                addressLinks(scheme: "http", port: settings.httpPushPort)

                VStack(alignment: .leading, spacing: 10) {
                    Text("API 接口（点击可直接打开）")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    apiLink("/heartbeat", "返回纯文本心率值", ip: httpServer.localIPs.first, port: settings.httpPushPort)
                    apiLink("/heartbeat.json", "返回 JSON 格式数据", ip: httpServer.localIPs.first, port: settings.httpPushPort)
                    apiLink("/live", "直播悬浮页（可作 OBS 浏览器源）", ip: httpServer.localIPs.first, port: settings.httpPushPort)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: WebSocket 实时推送

    private var wsPushSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WebSocket 实时推送")
                .font(.system(size: 16, weight: .bold))

            Toggle("启用 WebSocket 推送", isOn: $settings.wsPushEnabled)
                .onChange(of: settings.wsPushEnabled) { enabled in
                    if enabled {
                        wsServer.startServer(port: settings.wsPushPort)
                    } else {
                        wsServer.stopServer()
                    }
                }

            if settings.wsPushEnabled {
                HStack {
                    Text("端口")
                        .foregroundColor(.secondary)
                    TextField("端口号", text: $wsPort)
                        .keyboardType(.numberPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 100)

                    Button("应用", action: applyWsPort)
                        .foregroundColor(themeColor)
                }

                HStack {
                    Text("状态")
                        .foregroundColor(.secondary)
                    Spacer()
                    if wsServer.isRunning {
                        Label(wsServer.clientCount > 0 ? "\(wsServer.clientCount) 个连接" : "运行中",
                              systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.green)
                    } else {
                        Text("未运行")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }

                addressLinks(scheme: "ws", port: wsServer.currentPort)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: 网络环境说明

    private var networkNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("关于网络环境", systemImage: "info.circle")
                .font(.system(size: 13, weight: .semibold))
            Text("同一 WiFi 下设备可直接访问以上地址；蜂窝数据下手机拿到的是运营商内网地址，外部设备无法直接连入，建议使用 WiFi 或开启个人热点。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: 端口应用

    private func applyHttpPort() {
        if let port = Int(httpPort), port >= 1024 && port <= 65535 {
            settings.httpPushPort = port
            if settings.httpPushEnabled {
                viewModel.stopHttpServer()
                viewModel.startHttpServer(port: port)
            }
            portAlertMessage = "端口已应用"
        } else {
            portAlertMessage = "无效的端口号（1024-65535）"
        }
        showingPortAlert = true
    }

    private func applyWsPort() {
        if let port = Int(wsPort), port >= 1024 && port <= 65535 {
            settings.wsPushPort = port
            if settings.wsPushEnabled {
                wsServer.stopServer()
                wsServer.startServer(port: port)
            }
            portAlertMessage = "端口已应用"
        } else {
            portAlertMessage = "无效的端口号（1024-65535）"
        }
        showingPortAlert = true
    }

    // MARK: 本机地址列表（多网络接口）

    @ViewBuilder
    private func addressLinks(scheme: String, port: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("本机地址")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("单击打开 · 长按复制")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if httpServer.localIPs.isEmpty {
                Text("未获取到可用的本机地址")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            ForEach(httpServer.localIPs, id: \.self) { ip in
                if let url = URL(string: "\(scheme)://\(ip):\(port)/") {
                    HStack(spacing: 4) {
                        Text("\(scheme)://\(ip):\(port)")
                            .font(.system(size: 14, design: .monospaced))
                        if scheme == "http" {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11))
                        }
                    }
                    .foregroundColor(themeColor)
                    .contentShape(Rectangle())
                    // 手势顺序照搬主界面记录 chip 的验证组合：单击在前不吞点击，长按复制后松手也不会误触发打开
                    .onTapGesture {
                        openURL(url)
                    }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        UIPasteboard.general.string = "\(scheme)://\(ip):\(port)"
                        Haptics.light()
                        showToast("已复制")
                    }
                }
            }
        }
    }

    // MARK: 复制 / 打开手势与 Toast

    /// 顶部 Toast（短暂显示后自动消失，连续触发时替换上一条不叠加）
    private func showToast(_ text: String) {
        toastToken = UUID()
        toastText = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [token = toastToken] in
            if token == toastToken {
                toastText = nil
            }
        }
    }

    /// API 接口行：单击在浏览器打开，长按复制完整链接
    @ViewBuilder
    private func apiLink(_ path: String, _ desc: String, ip: String?, port: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let ip = ip, let url = URL(string: "http://\(ip):\(port)\(path)") {
                Text(path)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(themeColor)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openURL(url)
                    }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        UIPasteboard.general.string = url.absoluteString
                        Haptics.light()
                        showToast("已复制")
                    }
            } else {
                Text(path)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(themeColor.opacity(0.5))
            }
            Text(desc)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 全屏横屏图表（单指拖动平移 + 双指捏合缩放 + 单击查询 + 滑块辅助）

struct LandscapeChartView: View {
    let recording: HeartRateRecording

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var viewStartDate: Date?
    @State private var viewSpanSeconds: TimeInterval?
    @State private var queryIndex: Int?

    // 手势状态
    @State private var dragActive = false
    @State private var dragStartViewStart: Date?
    @State private var magnifying = false
    @State private var magnifyStartSpan: TimeInterval?
    @State private var magnifyCenter: Date?

    // 底部缩略裁剪条状态：按触摸 id 管理会话，支持双指同时拖动两个把手
    @State private var touchSessions: [Int: StripSession] = [:]

    private enum StripDragMode { case leftHandle, rightHandle, pan }

    struct StripSession {
        var mode: StripDragMode
        var startX: CGFloat
        var startViewStartDate: Date?
        var startViewEndDate: Date?
        var startPanViewStart: Date?
    }

    /// 锁定模式：视口固定，图表上滑动即可连续查询（未缩放时默认开启）
    @State private var lockMode = false

    /// 横向缩放时可见的最小时间窗口
    private let minSpan: TimeInterval = 30

    /// 浅色模式跟随应用主题（淡粉渐变），深色模式沉浸黑底
    private var backgroundColor: some View {
        Group {
            if colorScheme == .dark {
                Color.black
            } else {
                LinearGradient(
                    colors: [Color(red: 1.0, green: 0.96, blue: 0.96), Color(white: 0.98)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
    private var hintColor: Color {
        colorScheme == .dark ? .white.opacity(0.55) : Color.secondary
    }

    private var firstDate: Date {
        recording.samples.first?.t ?? Date()
    }
    private var totalSpan: TimeInterval {
        guard let last = recording.samples.last?.t else { return minSpan }
        return max(last.timeIntervalSince(firstDate), minSpan)
    }
    /// 当前视口宽度（秒）
    private var currentSpan: TimeInterval {
        min(viewSpanSeconds ?? totalSpan, totalSpan)
    }
    /// 当前视口起点（钳制在数据范围内）
    private var currentStart: Date {
        clampStart(viewStartDate ?? firstDate, span: currentSpan)
    }
    /// 视口终点
    private var viewEndDate: Date {
        currentStart.addingTimeInterval(currentSpan)
    }

    var body: some View {
        ZStack {
            backgroundColor

            VStack(spacing: 12) {
                // 顶栏：关闭 + 采样点数
                HStack(spacing: 12) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(recordingThemeColor)
                    }
                    Spacer()
                    Button {
                        Haptics.light()
                        lockMode.toggle()
                    } label: {
                        Image(systemName: lockMode ? "lock.fill" : "lock.open.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(lockMode ? .white : hintColor)
                            .padding(7)
                            .background(lockMode ? recordingThemeColor : Color(.systemGray5).opacity(0.7), in: Circle())
                    }
                    Text("共 \(recording.samples.count) 点")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(hintColor)
                }

                chartArea

                // 底栏：图表缩略图 + 双把手裁剪窗口（控制视口两端）
                thumbStrip
            }
            .padding()
        }
        .onAppear {
            OrientationManager.shared.enterLandscape()
            // 初始未缩放（视口即全范围）时平移无意义，默认开启锁定
            if currentSpan >= totalSpan - 1 {
                lockMode = true
            }
        }
        .onDisappear { OrientationManager.shared.exitLandscape() }
    }

    /// 图表区：单击查询、单指拖动平移、双指捏合缩放
    private var chartArea: some View {
        GeometryReader { geo in
            RecordingChartView(
                samples: recording.samples,
                themeColor: recordingThemeColor,
                queryIndex: $queryIndex,
                viewStart: currentStart,
                viewSpanSeconds: currentSpan,
                queryEnabled: false,
                topInset: 34
            )
            // 无查询时在图表顶部居中显示操作提示（与查询胶囊互斥）
            .overlay(alignment: .top) {
                if queryIndex == nil {
                    Text(lockMode ? "滑动查询 · 双指缩放" : "单击查询 · 双指缩放 · 拖动平移")
                        .font(.system(size: 12))
                        .foregroundColor(hintColor)
                        .padding(.top, 10)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { handleDragChanged($0, size: geo.size) }
                    .onEnded { handleDragEnded($0, size: geo.size) }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { handleMagnify($0) }
                    .onEnded { _ in
                        magnifying = false
                        magnifyStartSpan = nil
                    }
            )
        }
    }

    /// 单指拖动：锁定时滑动连续查询；未锁定时位移超过阈值进入平移模式，否则视为单击
    private func handleDragChanged(_ value: DragGesture.Value, size: CGSize) {
        if lockMode {
            // 锁定：视口固定，滑动经过的采样点实时查询
            let layout = RecordingChartLayout(
                samples: recording.samples,
                size: size,
                viewStart: currentStart,
                viewSpanSeconds: currentSpan
            )
            queryIndex = layout.nearestIndex(in: recording.samples, at: value.location)
            return
        }
        guard !magnifying else { return }
        if !dragActive {
            if abs(value.translation.width) > 10 || abs(value.translation.height) > 10 {
                dragActive = true
                dragStartViewStart = currentStart
            } else {
                return
            }
        }
        let plotWidth = max(size.width - 52, 10)
        let shift = -value.translation.width / plotWidth * currentSpan
        viewStartDate = clampStart(dragStartViewStart!.addingTimeInterval(shift), span: currentSpan)
    }

    private func handleDragEnded(_ value: DragGesture.Value, size: CGSize) {
        defer {
            dragActive = false
            dragStartViewStart = nil
        }
        guard !magnifying, !dragActive else { return }
        // 未进入平移模式 → 单击查询；点击绘图区外清除
        let plot = CGRect(x: 40, y: 34, width: max(size.width - 52, 10), height: max(size.height - 56, 10))
        guard plot.insetBy(dx: -10, dy: -10).contains(value.location) else {
            queryIndex = nil
            return
        }
        let layout = RecordingChartLayout(
            samples: recording.samples,
            size: size,
            viewStart: currentStart,
            viewSpanSeconds: currentSpan
        )
        queryIndex = layout.nearestIndex(in: recording.samples, at: value.location)
    }

    /// 双指捏合：张开放大（时间窗口变窄），保持视口中心稳定
    private func handleMagnify(_ value: MagnificationGesture.Value) {
        magnifying = true
        if magnifyStartSpan == nil {
            magnifyStartSpan = currentSpan
            magnifyCenter = currentStart.addingTimeInterval(currentSpan / 2)
        }
        let newSpan = clampSpan(magnifyStartSpan! / value)
        viewSpanSeconds = newSpan
        viewStartDate = clampStart(magnifyCenter!.addingTimeInterval(-newSpan / 2), span: newSpan)
        // 视口回到全范围则平移无意义，自动锁定；一旦缩放即解锁
        lockMode = newSpan >= totalSpan - 1
    }

    // MARK: - 底部缩略裁剪条

    private var thumbStrip: some View {
        GeometryReader { geo in
            let inset: CGFloat = 10
            let trackWidth = max(geo.size.width - inset * 2, 10)
            let startFraction = totalSpan > 0 ? currentStart.timeIntervalSince(firstDate) / totalSpan : 0
            let endFraction = totalSpan > 0 ? viewEndDate.timeIntervalSince(firstDate) / totalSpan : 1
            let leftX = inset + CGFloat(startFraction) * trackWidth
            let rightX = inset + CGFloat(endFraction) * trackWidth

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color(.systemGray5))

                ThumbCurve(
                    samples: recording.samples,
                    firstDate: firstDate,
                    totalSpan: totalSpan,
                    viewLeftX: leftX,
                    viewRightX: rightX,
                    plotInset: inset,
                    themeColor: recordingThemeColor
                )

                handle(isActive: touchSessions.values.contains { $0.mode == .leftHandle })
                    .position(x: leftX, y: geo.size.height / 2)

                handle(isActive: touchSessions.values.contains { $0.mode == .rightHandle })
                    .position(x: rightX, y: geo.size.height / 2)
            }
            .overlay(
                StripTouchView(
                    onBegan: { handleTouchesBegan($0, trackWidth: trackWidth, inset: inset) },
                    onMoved: { handleTouchesMoved($0, trackWidth: trackWidth, inset: inset) },
                    onEnded: { handleTouchesEnded($0) }
                )
            )
        }
        .frame(height: 46)
    }

    /// 裁剪条把手：拖动时曲线动效放大 + 高亮，松开弹回原样
    private func handle(isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(recordingThemeColor)
            .frame(width: 8, height: 38)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(isActive ? 0.9 : 0), lineWidth: 2)
            )
            .shadow(color: recordingThemeColor.opacity(isActive ? 0.55 : 0.18), radius: isActive ? 6 : 2, y: 1)
            .scaleEffect(isActive ? 1.35 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isActive)
    }

    private func handleTouchesBegan(_ touches: [StripTouch], trackWidth: CGFloat, inset: CGFloat) {
        for touch in touches {
            let x = touch.location.x
            let startFraction = totalSpan > 0 ? currentStart.timeIntervalSince(firstDate) / totalSpan : 0
            let endFraction = totalSpan > 0 ? viewEndDate.timeIntervalSince(firstDate) / totalSpan : 1
            let leftX = inset + CGFloat(startFraction) * trackWidth
            let rightX = inset + CGFloat(endFraction) * trackWidth

            let grab: CGFloat = 16
            let mode: StripDragMode
            if abs(x - leftX) <= grab {
                mode = .leftHandle
            } else if abs(x - rightX) <= grab {
                mode = .rightHandle
            } else if !touchSessions.values.contains(where: { $0.mode == .pan }) {
                mode = .pan
            } else {
                continue // 同时只允许一个平移触摸
            }

            touchSessions[touch.id] = StripSession(
                mode: mode,
                startX: x,
                startViewStartDate: currentStart,
                startViewEndDate: viewEndDate,
                startPanViewStart: currentStart
            )
        }
    }

    private func handleTouchesMoved(_ touches: [StripTouch], trackWidth: CGFloat, inset: CGFloat) {
        let secondsPerPoint = totalSpan / max(trackWidth, 1)
        for touch in touches {
            guard let session = touchSessions[touch.id] else { continue }
            let shiftSeconds = TimeInterval(touch.location.x - session.startX) * secondsPerPoint

            switch session.mode {
            case .leftHandle:
                // 拖左把手：右端固定，起点移动（视口不小于 minSpan）
                guard let s0 = session.startViewStartDate, let e0 = session.startViewEndDate else { continue }
                let newStart = min(max(s0.addingTimeInterval(shiftSeconds), firstDate), e0.addingTimeInterval(-minSpan))
                viewStartDate = newStart
                viewSpanSeconds = e0.timeIntervalSince(newStart)
                lockMode = (viewSpanSeconds ?? 0) >= totalSpan - 1
            case .rightHandle:
                // 拖右把手：起点固定，终点移动
                guard let s0 = session.startViewStartDate, let e0 = session.startViewEndDate else { continue }
                let newEnd = min(max(e0.addingTimeInterval(shiftSeconds), s0.addingTimeInterval(minSpan)), firstDate.addingTimeInterval(totalSpan))
                viewSpanSeconds = newEnd.timeIntervalSince(s0)
                viewStartDate = s0
                lockMode = (viewSpanSeconds ?? 0) >= totalSpan - 1
            case .pan:
                let base = session.startPanViewStart ?? currentStart
                viewStartDate = clampStart(base.addingTimeInterval(shiftSeconds), span: currentSpan)
            }
        }
    }

    private func handleTouchesEnded(_ ids: [Int]) {
        for id in ids {
            touchSessions.removeValue(forKey: id)
        }
    }

    private func clampSpan(_ span: TimeInterval) -> TimeInterval {
        min(max(span, minSpan), totalSpan)
    }

    private func clampStart(_ start: Date, span: TimeInterval) -> Date {
        let maxStart = firstDate.addingTimeInterval(max(0, totalSpan - span))
        return min(max(start, firstDate), maxStart)
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

/// 底部缩略曲线：全范围曲线，视口内正常对比度、视口外降低透明度
private struct ThumbCurve: View {
    let samples: [HeartRateRecording.Sample]
    let firstDate: Date
    let totalSpan: TimeInterval
    let viewLeftX: CGFloat
    let viewRightX: CGFloat
    let plotInset: CGFloat
    let themeColor: Color

    var body: some View {
        Canvas { context, size in
            guard samples.count >= 2, totalSpan > 0 else { return }
            let plot = CGRect(
                x: plotInset,
                y: 5,
                width: max(size.width - plotInset * 2, 10),
                height: max(size.height - 10, 10)
            )
            let values = samples.map { Double($0.bpm) }
            let lo = values.min() ?? 60
            let hi = max(values.max() ?? 100, lo + 1)

            var path = Path()
            var started = false
            for s in samples {
                let x = plot.minX + CGFloat(s.t.timeIntervalSince(firstDate) / totalSpan) * plot.width
                let ratio = (Double(s.bpm) - lo) / (hi - lo)
                let y = plot.maxY - CGFloat(ratio) * plot.height
                if started {
                    path.addLine(to: CGPoint(x: x, y: y))
                } else {
                    path.move(to: CGPoint(x: x, y: y))
                    started = true
                }
            }

            let style = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)

            // 视口外：降低对比度
            context.stroke(path, with: .color(themeColor.opacity(0.28)), style: style)

            // 视口内：正常对比度
            let viewRect = CGRect(x: viewLeftX, y: 0, width: max(viewRightX - viewLeftX, 1), height: size.height)
            context.clip(to: Path(viewRect))
            context.stroke(path, with: .color(themeColor), style: style)
        }
    }
}

/// 底部裁剪条的多点触摸桥接：SwiftUI 的 DragGesture 无法同时跟踪两个触点
private struct StripTouchView: UIViewRepresentable {
    var onBegan: ([StripTouch]) -> Void
    var onMoved: ([StripTouch]) -> Void
    var onEnded: ([Int]) -> Void

    func makeUIView(context: Context) -> StripTouchUIView {
        let view = StripTouchUIView()
        view.isMultipleTouchEnabled = true
        view.onBegan = onBegan
        view.onMoved = onMoved
        view.onEnded = onEnded
        return view
    }

    func updateUIView(_ uiView: StripTouchUIView, context: Context) {
        uiView.onBegan = onBegan
        uiView.onMoved = onMoved
        uiView.onEnded = onEnded
    }
}

final class StripTouchUIView: UIView {
    var onBegan: ([StripTouch]) -> Void = { _ in }
    var onMoved: ([StripTouch]) -> Void = { _ in }
    var onEnded: ([Int]) -> Void = { _ in }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onBegan(touches.map { StripTouch(id: $0.hash, location: $0.location(in: self)) })
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        onMoved(touches.map { StripTouch(id: $0.hash, location: $0.location(in: self)) })
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        onEnded(touches.map { $0.hash })
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        onEnded(touches.map { $0.hash })
    }
}

struct StripTouch {
    let id: Int
    let location: CGPoint
}

// MARK: - 蓝牙设备（绑定详情 + 解绑）

struct BleDeviceSettingsView: View {
    @EnvironmentObject var viewModel: HeartRateViewModel
    @ObservedObject private var ble = BleService.shared

    @State private var showUnbindConfirm = false

    private var isBound: Bool { ble.lastConnectedIdentifier != nil }

    var body: some View {
        ZStack {
            List {
                Section {
                    if isBound {
                        HStack(spacing: 14) {
                            Image(systemName: "heart.circle.fill")
                                .font(.system(size: 34))
                                .foregroundColor(Color(hex: "EC746F"))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ble.lastConnectedName.isEmpty ? "未知设备" : ble.lastConnectedName)
                                    .font(.system(size: 15, weight: .medium))
                                Text("标识 \(ble.lastConnectedIdentifier!.uuidString.prefix(8).uppercased())")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(viewModel.connectionState == .connected ? Color.green : Color(.systemGray3))
                                        .frame(width: 7, height: 7)
                                    Text(viewModel.connectionState == .connected ? "已连接" : "未连接")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                if let at = ble.lastConnectedAt {
                                    Text("最后连接 \(Self.dateText(at))")
                                        .font(.system(size: 10))
                                        .foregroundColor(Color(.tertiaryLabel))
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.system(size: 36))
                                .foregroundColor(Color(.tertiaryLabel))
                            Text("尚未绑定设备")
                                .font(.system(size: 14, weight: .medium))
                            Text("连接一次手环后，这里会显示设备信息")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                } header: {
                    Text("绑定设备")
                } footer: {
                    Text("绑定后，连接时会优先直连该设备（不依赖设备广播），速度更快；解绑后恢复为扫描搜索附近的设备。")
                }

                Section {
                    Button(action: {
                        Haptics.light()
                        showUnbindConfirm = true
                    }) {
                        HStack {
                            Spacer()
                            Image(systemName: "link.badge.plus")
                            Text("解绑设备")
                            Spacer()
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.red)
                    }
                    .disabled(!isBound)
                }
            }
            .listStyle(.insetGrouped)

            if showUnbindConfirm {
                GlassAlertOverlay(
                    iconName: "link.badge.plus",
                    iconColor: .red,
                    title: "解绑设备？",
                    message: "解绑「\(ble.lastConnectedName.isEmpty ? "未知设备" : ble.lastConnectedName)」后，下次连接将重新搜索附近的心率设备",
                    confirmTitle: "解绑",
                    confirmDestructive: true,
                    onConfirm: {
                        ble.unbindLastDevice()
                        showUnbindConfirm = false
                    },
                    onCancel: { showUnbindConfirm = false }
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showUnbindConfirm)
        .navigationTitle("蓝牙设备")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 心率记录列表

struct RecordingsListView: View {
    @EnvironmentObject var viewModel: HeartRateViewModel

    @State private var showImporter = false
    @State private var pendingDelete: HeartRateRecording?
    @State private var importResult: ImportResult?
    // 批量删除（自绘多选：不用系统编辑模式，从根上避开减号删除控件）
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showBatchDeleteConfirm = false

    struct ImportResult: Identifiable {
        let id = UUID()
        let success: Bool
        let message: String
    }

    /// 导入的记录单独分组展示，与自测记录区分
    private var importedRecordings: [HeartRateRecording] {
        viewModel.recordings.filter { $0.imported }
    }
    private var myRecordings: [HeartRateRecording] {
        viewModel.recordings.filter { !$0.imported }
    }

    var body: some View {
        ZStack {
            List {
                if !importedRecordings.isEmpty {
                    Section("导入的记录") {
                        ForEach(importedRecordings) { recording in
                            row(recording)
                        }
                        .onDelete(perform: isSelecting ? nil : { requestDelete(offsets: $0, in: importedRecordings) })
                    }
                }

                Section("我的记录") {
                    if myRecordings.isEmpty {
                        Text(myRecordingsPlaceholder)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    ForEach(myRecordings) { recording in
                        row(recording)
                    }
                    .onDelete(perform: isSelecting ? nil : { requestDelete(offsets: $0, in: myRecordings) })
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .bottom) {
                if isSelecting {
                    batchBar
                }
            }

            // 删除确认（防误删）
            if let pending = pendingDelete {
                GlassAlertOverlay(
                    iconName: "trash",
                    iconColor: .red,
                    title: "删除记录？",
                    message: "删除「\(Self.shortDateText(pending.startedAt))」的记录后无法恢复",
                    confirmTitle: "删除",
                    confirmDestructive: true,
                    onConfirm: {
                        viewModel.deleteRecording(pending)
                        pendingDelete = nil
                    },
                    onCancel: { pendingDelete = nil }
                )
                .transition(.opacity)
                .zIndex(10)
            }

            // 批量删除确认（防误删）
            if showBatchDeleteConfirm {
                GlassAlertOverlay(
                    iconName: "trash",
                    iconColor: .red,
                    title: "删除 \(selectedIDs.count) 条记录？",
                    message: "删除后无法恢复",
                    confirmTitle: "删除",
                    confirmDestructive: true,
                    onConfirm: {
                        viewModel.deleteRecordings(withIDs: selectedIDs)
                        selectedIDs = []
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isSelecting = false
                        }
                        showBatchDeleteConfirm = false
                    },
                    onCancel: { showBatchDeleteConfirm = false }
                )
                .transition(.opacity)
                .zIndex(10)
            }

            // 导入结果
            if let result = importResult {
                GlassAlertOverlay(
                    iconName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill",
                    iconColor: result.success ? .green : .red,
                    title: result.success ? "导入成功" : "导入失败",
                    message: result.message,
                    confirmTitle: "知道",
                    cancelTitle: nil,
                    onConfirm: { importResult = nil }
                )
                .transition(.opacity)
                .zIndex(11)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: pendingDelete?.id)
        .animation(.easeInOut(duration: 0.2), value: importResult?.id)
        .animation(.easeInOut(duration: 0.25), value: isSelecting)
        .animation(.easeInOut(duration: 0.2), value: showBatchDeleteConfirm)
        .animation(.easeInOut(duration: 0.15), value: selectedIDs)
        .navigationTitle("心率记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !isSelecting {
                    Button(action: {
                        Haptics.light()
                        showImporter = true
                    }) {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                Button(action: toggleSelection) {
                    Text(isSelecting ? "完成" : "选择")
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    try viewModel.importRecording(from: url)
                    importResult = ImportResult(success: true, message: "已导入到「导入的记录」分组，可点击查看详情")
                } catch {
                    importResult = ImportResult(success: false, message: error.localizedDescription)
                }
            case .failure(let error):
                importResult = ImportResult(success: false, message: error.localizedDescription)
            }
        }
    }

    private var myRecordingsPlaceholder: String {
        importedRecordings.isEmpty
            ? "还没有记录。点击右上角导入心率文件，或连接手环后在主界面开始记录"
            : "暂无自测记录。点击右上角导入心率文件，或连接手环后在主界面开始记录"
    }

    private func requestDelete(offsets: IndexSet, in list: [HeartRateRecording]) {
        guard let index = offsets.first, list.indices.contains(index) else { return }
        pendingDelete = list[index]
    }

    // MARK: 批量删除

    private var allSelected: Bool {
        !viewModel.recordings.isEmpty && selectedIDs.count == viewModel.recordings.count
    }

    private func toggleSelection() {
        Haptics.light()
        withAnimation(.easeInOut(duration: 0.25)) {
            isSelecting.toggle()
        }
        if !isSelecting {
            selectedIDs = []
        }
    }

    private func toggleSelectAll() {
        Haptics.light()
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedIDs = allSelected ? [] : Set(viewModel.recordings.map(\.id))
        }
    }

    private var batchBar: some View {
        HStack(spacing: 12) {
            Button(action: toggleSelectAll) {
                Text(allSelected ? "取消全选" : "全选")
                    .font(.system(size: 14))
            }
            .disabled(viewModel.recordings.isEmpty)

            Spacer()

            Text("已选 \(selectedIDs.count) 条")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            Button(action: { showBatchDeleteConfirm = true }) {
                Label("删除", systemImage: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(selectedIDs.isEmpty ? Color(.systemGray4) : Color.red, in: Capsule())
            }
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// 选择模式：整行变多选按钮（自绘勾选圈）；普通模式：进详情
    private func row(_ recording: HeartRateRecording) -> some View {
        Group {
            if isSelecting {
                Button {
                    toggleSelect(recording)
                } label: {
                    rowContent(recording, selected: selectedIDs.contains(recording.id))
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(destination: RecordingDetailView(recording: recording)) {
                    rowContent(recording, selected: false)
                }
            }
        }
    }

    private func rowContent(_ recording: HeartRateRecording, selected: Bool) -> some View {
        HStack(spacing: 10) {
            if isSelecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(selected ? recordingThemeColor : Color(.systemGray3))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.dateText(recording.startedAt))
                    .font(.system(size: 15, weight: .medium))
                HStack(spacing: 14) {
                    Text("时长 \(recording.durationText)")
                    Text("平均 \(recording.averageBpm.map { String(format: "%.0f", $0) } ?? "--") BPM")
                    Text("\(recording.samples.count) 点")
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func toggleSelect(_ recording: HeartRateRecording) {
        Haptics.light()
        if selectedIDs.contains(recording.id) {
            selectedIDs.remove(recording.id)
        } else {
            selectedIDs.insert(recording.id)
        }
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func shortDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 记录详情（大图 + 点击查询 + 导出）

struct RecordingDetailView: View {
    let recording: HeartRateRecording

    @State private var shareItem: ShareItem?
    @State private var showExportMenu = false
    @State private var showLandscape = false
    /// 图表点击查询的采样点下标（点击绘图区外或统计卡时清除）
    @State private var queryIndex: Int?

    struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 16) {
                    statsSection
                        .contentShape(Rectangle())
                        .onTapGesture { queryIndex = nil }

                    RecordingChartView(samples: recording.samples, themeColor: recordingThemeColor, queryIndex: $queryIndex, topInset: 28)
                        .frame(height: 300)
                        .background(Color(.systemGray6))
                        .cornerRadius(14)
                        .overlay(alignment: .topTrailing) {
                            Button(action: {
                                Haptics.light()
                                showLandscape = true
                            }) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.primary.opacity(0.55))
                                    .frame(width: 28, height: 28)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .padding(8)
                        }
                        .fullScreenCover(isPresented: $showLandscape) {
                            LandscapeChartView(recording: recording)
                        }

                    exportMenu
                }
                .padding()
            }
        }
        // 菜单打开时点击页面任意处关闭（simultaneous 不影响子按钮正常点击）
        .simultaneousGesture(
            TapGesture().onEnded {
                if showExportMenu { showExportMenu = false }
            }
        )
        .animation(.easeInOut(duration: 0.2), value: showExportMenu)
        .navigationTitle("记录详情")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(items: [item.url])
        }
    }

    private var statsSection: some View {
        HStack(spacing: 0) {
            statItem("平均", recording.averageBpm.map { String(format: "%.0f", $0) } ?? "--")
            statItem("最低", recording.minBpm.map(String.init) ?? "--")
            statItem("最高", recording.maxBpm.map(String.init) ?? "--")
            statItem("时长", recording.durationText)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(14)
    }

    private func statItem(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(recordingThemeColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var exportMenu: some View {
        Button(action: {
            Haptics.medium()
            showExportMenu = true
        }) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text("导出记录")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(recordingThemeColor)
            .foregroundColor(.white)
            .cornerRadius(14)
        }
        // 菜单卡片从按钮上方向上弹出；按钮位于页面底部，向上弹不会被滚动区域裁剪
        .overlay(alignment: .top) {
            if showExportMenu {
                AnchoredMenuCard(items: [
                    AnchoredMenuItem(
                        title: "导出 CSV",
                        subtitle: "表格软件可直接打开",
                        icon: "tablecells"
                    ) {
                        exportFile(ext: "csv", text: csvText)
                    },
                    AnchoredMenuItem(
                        title: "导出 JSON",
                        subtitle: "完整原始数据，便于程序处理",
                        icon: "curlybraces.square"
                    ) {
                        exportFile(ext: "json", text: jsonText)
                    }
                ]) {
                    showExportMenu = false
                }
                .offset(y: -136)
                .transition(.opacity)
            }
        }
    }

    private var csvText: String {
        var lines = ["timestamp,bpm"]
        for sample in recording.samples {
            lines.append("\(HeartRateRecordingStore.iso8601.string(from: sample.t)),\(sample.bpm)")
        }
        return lines.joined(separator: "\n")
    }

    private var jsonText: String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(recording),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private func exportFile(ext: String, text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let name = "心率记录_\(formatter.string(from: recording.startedAt)).\(ext)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        shareItem = ShareItem(url: url)
    }
}

// MARK: - 记录图表（Canvas 绘制：整数 BPM 刻度 + 时间刻度 + 点击查询）

struct RecordingChartView: View {
    let samples: [HeartRateRecording.Sample]
    let themeColor: Color
    @Binding var queryIndex: Int?
    /// 视口起点与宽度（秒）；nil 时覆盖全部数据
    var viewStart: Date? = nil
    var viewSpanSeconds: TimeInterval? = nil
    /// 内置点击查询手势开关（全屏模式下由外部手势接管）
    var queryEnabled: Bool = true
    /// 绘图区顶部留白（给查询胶囊/提示文字让位）
    var topInset: CGFloat = 8

    /// 点击绘图区内查询最近采样点；点击绘图区外的留白区域则清除查询
    private func handleTouch(at point: CGPoint, layout: RecordingChartLayout) {
        guard layout.plot.insetBy(dx: -10, dy: -10).contains(point) else {
            queryIndex = nil
            return
        }
        queryIndex = layout.nearestIndex(in: samples, at: point)
    }

    var body: some View {
        GeometryReader { geo in
            let layout = RecordingChartLayout(samples: samples, size: geo.size, viewStart: viewStart, viewSpanSeconds: viewSpanSeconds, topInset: topInset)
            let chart = Canvas { context, size in
                draw(in: &context, size: size, layout: layout)
            }
            .overlay(alignment: .top) {
                if let index = queryIndex, samples.indices.contains(index) {
                    Text("\(Self.timeText(samples[index].t)) · \(samples[index].bpm) BPM")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 6)
                }
            }
            .contentShape(Rectangle())

            if queryEnabled {
                chart.gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { handleTouch(at: $0.location, layout: layout) }
                        .onEnded { handleTouch(at: $0.location, layout: layout) }
                )
            } else {
                chart
            }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, layout: RecordingChartLayout) {
        let plot = layout.plot

        guard !samples.isEmpty else {
            context.draw(
                Text("没有采样数据").font(.system(size: 13)).foregroundColor(Color(.tertiaryLabel)),
                at: CGPoint(x: size.width / 2, y: size.height / 2)
            )
            return
        }

        // 水平 BPM 网格：刻度对齐整数（步长取 1/2/5×10ⁿ）
        let span = layout.ymax - layout.ymin
        let rawStep = span / 5
        let magnitude = pow(10.0, floor(log10(rawStep)))
        let normalized = rawStep / magnitude
        let step = (normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 7 ? 5 : 10) * magnitude
        var value = (layout.ymin / step).rounded(.up) * step
        while value <= layout.ymax + 0.001 {
            let y = layout.y(value)
            var grid = Path()
            grid.move(to: CGPoint(x: plot.minX, y: y))
            grid.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(grid, with: .color(Color(.systemGray5)), lineWidth: 0.8)
            context.draw(
                Text("\(Int(value.rounded()))").font(.system(size: 9, design: .monospaced)).foregroundColor(Color(.tertiaryLabel)),
                at: CGPoint(x: plot.minX - 18, y: y)
            )
            value += step
        }

        // 垂直时间刻度：5 等分，短记录显示 分:秒，长记录显示 时:分
        let total = layout.xmax.timeIntervalSince(layout.xmin)
        let formatter = DateFormatter()
        formatter.dateFormat = total < 90 ? "mm:ss" : "HH:mm"
        for i in 0...4 {
            let fraction = Double(i) / 4.0
            let date = layout.xmin.addingTimeInterval(fraction * total)
            let x = plot.minX + CGFloat(fraction) * plot.width
            var grid = Path()
            grid.move(to: CGPoint(x: x, y: plot.minY))
            grid.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.stroke(grid, with: .color(Color(.systemGray5)), lineWidth: 0.8)
            context.draw(
                Text(formatter.string(from: date)).font(.system(size: 9)).foregroundColor(Color(.tertiaryLabel)),
                at: CGPoint(x: x, y: plot.maxY + 12)
            )
        }

        // 剪裁绘图区
        context.clip(to: Path(plot))

        // 折线：直线段连接全部采样点
        var line = Path()
        for (index, sample) in samples.enumerated() {
            let point = CGPoint(x: layout.x(sample.t), y: layout.y(Double(sample.bpm)))
            if index == 0 {
                line.move(to: point)
            } else {
                line.addLine(to: point)
            }
        }

        // 渐变填充
        var fill = line
        fill.addLine(to: CGPoint(x: layout.x(samples[samples.count - 1].t), y: plot.maxY))
        fill.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
        fill.closeSubpath()
        context.fill(fill, with: .linearGradient(
            Gradient(colors: [themeColor.opacity(0.28), themeColor.opacity(0.02)]),
            startPoint: CGPoint(x: 0, y: plot.minY),
            endPoint: CGPoint(x: 0, y: plot.maxY)
        ))

        // 折线描边
        context.stroke(line, with: .color(themeColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        // 点击查询指示：竖直虚线 + 高亮圆点
        if let index = queryIndex, samples.indices.contains(index) {
            let sample = samples[index]
            let x = layout.x(sample.t)
            let y = layout.y(Double(sample.bpm))
            var guide = Path()
            guide.move(to: CGPoint(x: x, y: plot.minY))
            guide.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.stroke(guide, with: .color(Color.secondary.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            context.fill(
                Path(ellipseIn: CGRect(x: x - 4.5, y: y - 4.5, width: 9, height: 9)),
                with: .color(themeColor)
            )
            context.stroke(
                Path(ellipseIn: CGRect(x: x - 6.5, y: y - 6.5, width: 13, height: 13)),
                with: .color(.white),
                lineWidth: 1.5
            )
        }
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

/// 图表布局：数据范围 → 坐标映射（绘制与手势反查共用）
private struct RecordingChartLayout {
    let plot: CGRect
    let xmin: Date
    let xmax: Date
    let ymin: Double
    let ymax: Double

    init(samples: [HeartRateRecording.Sample], size: CGSize, viewStart: Date? = nil, viewSpanSeconds: TimeInterval? = nil, topInset: CGFloat = 8) {
        plot = CGRect(x: 40, y: topInset, width: max(size.width - 52, 10), height: max(size.height - topInset - 22, 10))
        let first = samples.first?.t ?? Date()
        let last = samples.last?.t ?? first
        // 视口：未指定时覆盖全部数据；指定时显示 [start, end] 区间
        let start = viewStart ?? first
        let span = viewSpanSeconds ?? max(last.timeIntervalSince(first), 10)
        let end = start.addingTimeInterval(span)
        // 用局部变量过滤：init 完成前闭包不能捕获 self 的属性
        let inView = samples.filter { $0.t >= start && $0.t <= end }
        xmin = start
        xmax = end
        let values = (inView.isEmpty ? samples : inView).map { Double($0.bpm) }
        let vmin = values.min() ?? 60
        let vmax = values.max() ?? 100
        let spanY = max(vmax - vmin, 8) * 1.15
        let mid = (vmin + vmax) / 2
        ymin = mid - spanY / 2
        ymax = mid + spanY / 2
    }

    func x(_ t: Date) -> CGFloat {
        let total = xmax.timeIntervalSince(xmin)
        guard total > 0 else { return plot.midX }
        return plot.minX + CGFloat(t.timeIntervalSince(xmin) / total) * plot.width
    }

    func y(_ v: Double) -> CGFloat {
        plot.maxY - CGFloat((v - ymin) / max(ymax - ymin, 0.001)) * plot.height
    }

    /// 点击位置 → 最近的采样点下标（二分）
    func nearestIndex(in samples: [HeartRateRecording.Sample], at point: CGPoint) -> Int? {
        guard !samples.isEmpty, plot.width > 0 else { return nil }
        let fraction = min(max((point.x - plot.minX) / plot.width, 0), 1)
        let total = xmax.timeIntervalSince(xmin)
        let target = xmin.addingTimeInterval(Double(fraction) * total)
        var lo = 0
        var hi = samples.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if samples[mid].t < target {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        if lo == 0 { return 0 }
        if lo == samples.count { return samples.count - 1 }
        let before = abs(samples[lo - 1].t.timeIntervalSince(target))
        let after = abs(samples[lo].t.timeIntervalSince(target))
        return before < after ? lo - 1 : lo
    }
}

// MARK: - 系统分享面板

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 关于

struct AboutView: View {
    @EnvironmentObject var settings: SettingsManager
    @ObservedObject private var updateChecker = UpdateChecker.shared

    private let repoURL = URL(string: "https://github.com/EPXiaohua/heartfloat-ios")!
    private let issuesURL = URL(string: "https://github.com/EPXiaohua/heartfloat-ios/issues")!
    private let androidURL = URL(string: "https://github.com/EPXiaohua/heartfloat-android")!

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 52))
                            .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.42))
                            .padding(.bottom, 2)
                        Text("心率悬浮窗")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("版本 \(Self.appVersion)")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)

                    infoCard(title: "应用简介") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("通过蓝牙连接小米手环等标准心率设备，实时查看心率数值与曲线，支持画中画悬浮窗常亮展示、长时间心率记录与多格式数据导出。")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("本应用主要在小米手环 9 Pro 上测试。其他设备如遇到连接或数据问题，欢迎在 GitHub Issues 中反馈。")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    infoCard(title: "为什么做心率悬浮窗") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("2023 年，张雪峰老师在直播里被网友提醒嘴唇发紫、建议查查心脏，他回了一句：“你跑不过我你信吗？我跑半马的人，你说我心脏不好？”")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("2026 年 3 月，他因心源性猝死离世，年仅 41 岁。身体的信号，往往来得比想象中早。")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("HeartFloat 没什么大本事，只是想让你的心率一直悬在屏幕上——看得见，别不当回事（）")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    infoCard(title: "关于安卓版") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("之前还做过一个安卓版的 HeartFloat，不过已经弃坑了——UI 难看、BUG 也多，唯一的亮点是 HTTP 直播页有多个预设（但也就那样吧）。所以别指望我更新它，精力都在 iOS 版上。")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack {
                                Text("仓库地址")
                                Spacer()
                                Link("heartfloat-android", destination: androidURL)
                            }
                            .font(.system(size: 14))
                        }
                    }

                    infoCard(title: "最新版本") {
                        VStack(alignment: .leading, spacing: 10) {
                            if let release = updateChecker.latestRelease {
                                let hasNew = UpdateChecker.isNewer(release.version, than: Self.appVersion)
                                HStack(alignment: .firstTextBaseline) {
                                    Text(release.version)
                                        .font(.system(size: 30, weight: .bold, design: .rounded))
                                        .foregroundColor(recordingThemeColor)
                                    Spacer()
                                    Text(hasNew ? "发现新版本" : "已是最新")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(hasNew ? recordingThemeColor : .secondary)
                                }
                                if !release.notes.isEmpty {
                                    // 发布说明（预览前几行，完整内容见 Releases 页）
                                    Text(release.notes)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .lineSpacing(3)
                                        .lineLimit(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Link(destination: release.htmlURL ?? UpdateChecker.releasesURL) {
                                    Label("前往 Releases 页面下载", systemImage: "arrow.down.circle")
                                        .font(.system(size: 13, weight: .medium))
                                }
                            } else {
                                Text("暂时无法获取最新版本信息")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Divider()

                            Toggle("自动检查更新", isOn: $settings.checkUpdatesEnabled)
                                .font(.system(size: 14))
                        }
                    }

                    infoCard(title: "项目信息") {
                        VStack(spacing: 10) {
                            HStack {
                                Text("当前版本")
                                Spacer()
                                Text(Self.appVersion)
                                    .foregroundColor(.secondary)
                            }
                            Divider()
                            HStack {
                                Text("仓库地址")
                                Spacer()
                                Link("EPXiaohua/heartfloat-ios", destination: repoURL)
                            }
                            Divider()
                            HStack {
                                Text("问题反馈")
                                Spacer()
                                Link("GitHub Issues", destination: issuesURL)
                            }
                        }
                        .font(.system(size: 14))
                    }
                }
                .padding()
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 进入关于页时刷新一次最新版本信息（启动时已静默检查过）
            updateChecker.fetch()
        }
    }

    /// 版本号从打包配置读取（Info.plist 的 CFBundleShortVersionString），不写死
    static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "未知"
    }

    private func infoCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(14)
    }
}

struct ColorPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    @State var selectedColor: Color
    var onColorSelected: (Color) -> Void

    var body: some View {
        NavigationView {
            VStack {
                ColorPicker("选择颜色", selection: $selectedColor, supportsOpacity: true)
                    .padding()

                Spacer()
            }
            .navigationTitle("选择颜色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        onColorSelected(selectedColor)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 清理缓存弹窗（自定义毛玻璃：计算 → 确认 → 清理中 → 完成）

struct CacheCleanupOverlayView: View {
    var onClose: () -> Void

    private enum Phase { case calculating, ready, cleaning, done }

    @State private var phase: Phase = .calculating
    @State private var cacheBytes: Int64 = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { } // 阻断点击穿透

            VStack(spacing: 14) {
                statusIcon

                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                if phase == .ready {
                    Text("画中画载体视频缓存、导出临时文件等可再生数据")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                if phase == .ready {
                    HStack(spacing: 10) {
                        Button(action: clean) {
                            Text("清理")
                                .font(.system(size: 15, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(red: 1.0, green: 0.42, blue: 0.42))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        Button(action: onClose) {
                            Text("取消")
                                .font(.system(size: 15, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.systemGray5))
                                .foregroundColor(.primary)
                                .cornerRadius(12)
                        }
                    }
                }
            }
            .padding(22)
            .frame(width: 310)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        }
        .onAppear(perform: calculate)
    }

    private var title: String {
        switch phase {
        case .calculating: return "正在计算缓存..."
        case .ready: return "可清理缓存 \(CacheCleaner.sizeText(cacheBytes))"
        case .cleaning: return "正在清理..."
        case .done: return "已清理"
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch phase {
        case .calculating, .cleaning:
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 4)
                    .frame(width: 54, height: 54)
                ProgressView()
                    .scaleEffect(1.3)
            }
        case .ready:
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 54))
                .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.42))
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundColor(.green)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private func calculate() {
        DispatchQueue.global(qos: .userInitiated).async {
            let bytes = CacheCleaner.calculateCacheSize()
            DispatchQueue.main.async {
                cacheBytes = bytes
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    phase = .ready
                }
            }
        }
    }

    private func clean() {
        withAnimation(.easeInOut(duration: 0.2)) { phase = .cleaning }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) {
            CacheCleaner.clearCache()
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    phase = .done
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: onClose)
            }
        }
    }
}

// MARK: - 存储管理（空间概览 + 占用明细 + 清理临时缓存）

struct StorageManageView: View {
    @State private var recordingsSize: Int64 = 0
    @State private var cacheSize: Int64 = 0
    @State private var appSize: Int64 = 0
    @State private var availableCapacity: Int64 = 0
    @State private var totalCapacity: Int64 = 0
    @State private var showCleanConfirm = false
    @State private var showNoCacheTip = false
    @State private var isCleaning = false

    /// 三段比例：App 占用 / 其他已用 / 剩余可用（相对手机总容量）
    private var appRatio: Double {
        totalCapacity > 0 ? min(1, Double(appSize) / Double(totalCapacity)) : 0
    }
    private var freeRatio: Double {
        totalCapacity > 0 ? min(1, Double(availableCapacity) / Double(totalCapacity)) : 0
    }
    private var otherRatio: Double {
        max(0, 1 - appRatio - freeRatio)
    }

    var body: some View {
        ZStack {
            List {
                Section("手机空间") {
                    storageRow(icon: "iphone", label: "可用空间", value: CacheCleaner.sizeText(availableCapacity))
                    storageRow(icon: "app", label: "应用占用", value: CacheCleaner.sizeText(appSize))
                    storageRow(icon: "internaldrive", label: "总容量", value: CacheCleaner.sizeText(totalCapacity))
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            legendDot(color: Color(red: 1.0, green: 0.42, blue: 0.42), text: "应用占用")
                            legendDot(color: Color(.systemGray3), text: "其他已用")
                            legendDot(color: Color(.systemGray5), text: "剩余可用")
                        }
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                Capsule()
                                    .fill(Color(red: 1.0, green: 0.42, blue: 0.42))
                                    .frame(width: max(6, geo.size.width * appRatio))
                                Capsule()
                                    .fill(Color(.systemGray3))
                                    .frame(width: max(6, geo.size.width * otherRatio))
                                Capsule()
                                    .fill(Color(.systemGray5))
                                    .frame(width: max(6, geo.size.width * freeRatio))
                            }
                        }
                        .frame(height: 10)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    storageRow(icon: "waveform.path.ecg", label: "心率记录", value: CacheCleaner.sizeText(recordingsSize))
                    storageRow(icon: "doc.on.doc", label: "临时缓存", value: CacheCleaner.sizeText(cacheSize))
                } header: {
                    Text("数据占用")
                } footer: {
                    Text("应用占用包含 App 本体与全部数据；其中临时缓存包含画中画载体视频、导出临时文件及系统缓存目录等可再生数据，清理后不影响心率记录。心率记录可在设置一级页面查看与管理。")
                }

                Section {
                    Button(action: {
                        Haptics.light()
                        if cacheSize > 0 {
                            showCleanConfirm = true
                        } else {
                            showNoCacheTip = true
                        }
                    }) {
                        HStack {
                            Spacer()
                            if isCleaning {
                                ProgressView()
                                    .padding(.horizontal, 6)
                                Text("正在清理...")
                            } else {
                                Image(systemName: "trash")
                                Text("清理临时缓存")
                            }
                            Spacer()
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.red)
                    }
                    .disabled(isCleaning)
                }
            }
            .listStyle(.insetGrouped)

            if showCleanConfirm {
                CacheCleanupOverlayView(onClose: {
                    showCleanConfirm = false
                    refresh()
                })
                .transition(.opacity)
                .zIndex(10)
            }

            if showNoCacheTip {
                GlassAlertOverlay(
                    iconName: "sparkles",
                    iconColor: .green,
                    title: "很干净",
                    message: "当前没有可清理的临时缓存",
                    confirmTitle: "知道",
                    cancelTitle: nil,
                    onConfirm: { showNoCacheTip = false }
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCleanConfirm)
        .animation(.easeInOut(duration: 0.2), value: showNoCacheTip)
        .navigationTitle("存储管理")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private func storageRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "EC746F"))
                .frame(width: 24)
            Text(label)
                .font(.system(size: 15))
            Spacer()
            Text(value)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func refresh() {
        recordingsSize = CacheCleaner.directorySize(HeartRateRecordingStore.directory)
        cacheSize = CacheCleaner.calculateCacheSize()
        appSize = CacheCleaner.appTotalSize()
        if let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        ) {
            availableCapacity = values.volumeAvailableCapacityForImportantUsage ?? 0
            totalCapacity = Int64(values.volumeTotalCapacity ?? 0)
        }
    }

    private func cleanCache() {
        isCleaning = true
        DispatchQueue.global(qos: .userInitiated).async {
            CacheCleaner.clearCache()
            DispatchQueue.main.async {
                isCleaning = false
                refresh()
            }
        }
    }
}

// MARK: - 缓存计算与清理（临时目录均为可再生数据：载体视频、导出的临时文件等）

private enum CacheCleaner {
    /// 可清理的缓存目录：临时目录 + Library/Caches（标准缓存目录）
    /// 注意不能清整个 Library——Preferences 里是 UserDefaults 设置数据
    static var cacheDirectories: [URL] {
        let fm = FileManager.default
        var dirs = [fm.temporaryDirectory]
        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            dirs.append(caches)
        }
        return dirs
    }

    static func calculateCacheSize() -> Int64 {
        cacheDirectories.reduce(0) { $0 + directorySize($1) }
    }

    static func clearCache() {
        for dir in cacheDirectories {
            let contents = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in contents {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// 整个 App 的磁盘占用：App 本体（bundle）+ 沙盒数据（Documents/Library/tmp）
    static func appTotalSize() -> Int64 {
        var total: Int64 = 0
        var directories: [URL] = []
        if let bundle = Bundle.main.resourceURL {
            directories.append(bundle)
        }
        let fm = FileManager.default
        directories.append(fm.urls(for: .documentDirectory, in: .userDomainMask)[0])
        directories.append(fm.urls(for: .libraryDirectory, in: .userDomainMask)[0])
        directories.append(fm.temporaryDirectory)
        for dir in directories {
            total += directorySize(dir)
        }
        return total
    }

    static func directorySize(_ url: URL) -> Int64 {
        let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])) ?? []
        var total: Int64 = 0
        for item in contents {
            guard let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) else { continue }
            if values.isDirectory == true {
                total += directorySize(item)
            } else {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(SettingsManager.shared)
            .environmentObject(HeartRateViewModel())
    }
}
