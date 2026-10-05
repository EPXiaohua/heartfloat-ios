import SwiftUI
import Foundation

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
                    NavigationLink(destination: PipSettingsView()) {
                        Label("悬浮窗设置", systemImage: "pip.enter")
                    }
                    NavigationLink(destination: RecordingsListView()) {
                        Label("心率记录", systemImage: "waveform.path.ecg")
                    }
                    NavigationLink(destination: HttpPushSettingsView()) {
                        Label("联网推送", systemImage: "dot.radiowaves.up.forward")
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

// MARK: - 联网推送

struct HttpPushSettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var viewModel: HeartRateViewModel

    @State private var httpPort: String = "8080"
    @State private var showingHttpAlert = false
    @State private var httpAlertMessage = ""

    private let themeColor = Color(hex: "EC746F")

    var body: some View {
        ScrollView {
            httpPushSection
                .padding()
        }
        .navigationTitle("联网推送")
        .navigationBarTitleDisplayMode(.inline)
        .alert("提示", isPresented: $showingHttpAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(httpAlertMessage)
        }
    }

    private var httpPushSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("联网推送")
                .font(.system(size: 16, weight: .bold))

            Toggle("启用HTTP推送", isOn: $settings.httpPushEnabled)
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

                    Button("应用") {
                        if let port = Int(httpPort), port >= 1024 && port <= 65535 {
                            settings.httpPushPort = port
                            if settings.httpPushEnabled {
                                viewModel.stopHttpServer()
                                viewModel.startHttpServer(port: port)
                            }
                            httpAlertMessage = "端口已应用"
                            showingHttpAlert = true
                        } else {
                            httpAlertMessage = "无效的端口号（1024-65535）"
                            showingHttpAlert = true
                        }
                    }
                    .foregroundColor(themeColor)
                }

                if let ip = HttpServerManager.shared.localIP {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("本机地址")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Link(destination: URL(string: "http://\(ip):\(settings.httpPushPort)/")!) {
                            HStack(spacing: 4) {
                                Text("http://\(ip):\(settings.httpPushPort)")
                                    .font(.system(size: 14, design: .monospaced))
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(themeColor)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("API 接口（点击可直接打开）")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    apiLink("/heartbeat", "返回纯文本心率值", ip: HttpServerManager.shared.localIP, port: settings.httpPushPort)
                    apiLink("/heartbeat.json", "返回 JSON 格式数据", ip: HttpServerManager.shared.localIP, port: settings.httpPushPort)
                    apiLink("/live", "直播悬浮页（可作 OBS 浏览器源）", ip: HttpServerManager.shared.localIP, port: settings.httpPushPort)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    /// API 接口行：设备已获取到本机 IP 时渲染为可点击链接，直接在浏览器打开
    @ViewBuilder
    private func apiLink(_ path: String, _ desc: String, ip: String?, port: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let ip = ip, let url = URL(string: "http://\(ip):\(port)\(path)") {
                Link(destination: url) {
                    Text(path)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(themeColor)
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

    @State private var viewStartDate: Date?
    @State private var viewSpanSeconds: TimeInterval?
    @State private var queryIndex: Int?

    // 手势状态
    @State private var dragActive = false
    @State private var dragStartViewStart: Date?
    @State private var magnifying = false
    @State private var magnifyStartSpan: TimeInterval?
    @State private var magnifyCenter: Date?

    /// 横向缩放时可见的最小时间窗口
    private let minSpan: TimeInterval = 30

    private var firstDate: Date {
        recording.samples.first?.t ?? Date()
    }
    private var totalSpan: TimeInterval {
        guard let last = recording.samples.last?.t else { return minSpan }
        return max(last.timeIntervalSince(firstDate), minSpan)
    }
    private var maxZoom: Double {
        max(1, totalSpan / minSpan)
    }
    /// 当前视口宽度（秒）
    private var currentSpan: TimeInterval {
        min(viewSpanSeconds ?? totalSpan, totalSpan)
    }
    /// 当前视口起点（钳制在数据范围内）
    private var currentStart: Date {
        clampStart(viewStartDate ?? firstDate, span: currentSpan)
    }
    /// 当前缩放倍率（滑块显示用）
    private var zoomValue: Double {
        currentSpan > 0 ? totalSpan / currentSpan : 1
    }
    /// 当前视口偏移比例（滑块显示用）
    private var offsetValue: Double {
        let draggable = max(0, totalSpan - currentSpan)
        guard draggable > 0 else { return 0 }
        return currentStart.timeIntervalSince(firstDate) / draggable
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    if let index = queryIndex, recording.samples.indices.contains(index) {
                        let sample = recording.samples[index]
                        Text("\(Self.timeText(sample.t)) · \(sample.bpm) BPM")
                            .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.42))
                    } else {
                        Text("单击图表查看对应时间的心率")
                            .foregroundColor(.white.opacity(0.55))
                    }
                    Spacer()
                    Text("共 \(recording.samples.count) 点")
                        .foregroundColor(.white.opacity(0.55))
                }
                .font(.system(size: 12, design: .monospaced))

                chartArea

                // 底部：视口位置滑块（拖动图表同样可以平移）
                HStack(spacing: 10) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                    Slider(
                        value: Binding(get: { offsetValue }, set: { setOffset($0) }),
                        in: 0...1
                    )
                    .disabled(totalSpan - currentSpan < 1)
                    Text("\(Int(offsetValue * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 34)
                }
            }
            .padding()

            // 右上角：横向缩放滑块
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                        Slider(
                            value: Binding(get: { zoomValue }, set: { setZoom($0) }),
                            in: 1...maxZoom
                        )
                        .frame(width: 180)
                        Text(String(format: "%.1fx", zoomValue))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 40)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                Spacer()
            }
            .padding()

            // 左上角：关闭
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding()
        }
        .onAppear { OrientationManager.shared.enterLandscape() }
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
                queryEnabled: false
            )
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

    /// 单指拖动：位移超过阈值进入平移模式，否则视为单击
    private func handleDragChanged(_ value: DragGesture.Value, size: CGSize) {
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
        let plot = CGRect(x: 40, y: 8, width: max(size.width - 52, 10), height: max(size.height - 30, 10))
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
    }

    /// 右上角滑块设定缩放倍率（保持视口中心稳定）
    private func setZoom(_ newZoom: Double) {
        let newSpan = clampSpan(totalSpan / max(newZoom, 0.0001))
        let center = currentStart.addingTimeInterval(currentSpan / 2)
        viewSpanSeconds = newSpan
        viewStartDate = clampStart(center.addingTimeInterval(-newSpan / 2), span: newSpan)
    }

    /// 底部滑块设定视口位置
    private func setOffset(_ fraction: Double) {
        let draggable = max(0, totalSpan - currentSpan)
        viewStartDate = clampStart(firstDate.addingTimeInterval(fraction * draggable), span: currentSpan)
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

// MARK: - 心率记录列表

struct RecordingsListView: View {
    @EnvironmentObject var viewModel: HeartRateViewModel

    var body: some View {
        Group {
            if viewModel.recordings.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 40))
                        .foregroundColor(Color(.tertiaryLabel))
                    Text("还没有心率记录")
                        .font(.system(size: 15, weight: .medium))
                    Text("连接手环后，在主界面点「开始记录」")
                        .font(.system(size: 12))
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.recordings) { recording in
                        NavigationLink(destination: RecordingDetailView(recording: recording)) {
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
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete { viewModel.deleteRecordings(at: $0) }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("心率记录")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
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

                    RecordingChartView(samples: recording.samples, themeColor: recordingThemeColor, queryIndex: $queryIndex)
                        .frame(height: 300)
                        .background(Color(.systemGray6))
                        .cornerRadius(14)
                        .overlay(alignment: .topTrailing) {
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
            let layout = RecordingChartLayout(samples: samples, size: geo.size, viewStart: viewStart, viewSpanSeconds: viewSpanSeconds)
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

    init(samples: [HeartRateRecording.Sample], size: CGSize, viewStart: Date? = nil, viewSpanSeconds: TimeInterval? = nil) {
        plot = CGRect(x: 40, y: 8, width: max(size.width - 52, 10), height: max(size.height - 30, 10))
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
    private let repoURL = URL(string: "https://github.com/EPXiaohua/heartfloat-ios")!

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
                        Text("通过蓝牙连接小米手环等标准心率设备，实时查看心率数值与曲线，支持画中画悬浮窗常亮展示、长时间心率记录与多格式数据导出。")
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                        }
                        .font(.system(size: 14))
                    }
                }
                .padding()
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
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
                    Text("应用占用包含 App 本体与全部数据；其中临时缓存包含画中画载体视频、导出临时文件等可再生数据，清理后不影响心率记录。心率记录可在设置一级页面查看与管理。")
                }

                Section {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
        cacheSize = CacheCleaner.directorySize(FileManager.default.temporaryDirectory)
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
    static func calculateCacheSize() -> Int64 {
        directorySize(FileManager.default.temporaryDirectory)
    }

    static func clearCache() {
        let tmp = FileManager.default.temporaryDirectory
        let contents = (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
        for url in contents {
            try? FileManager.default.removeItem(at: url)
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
