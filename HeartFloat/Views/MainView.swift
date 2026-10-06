import SwiftUI

struct MainView: View {
    @EnvironmentObject var viewModel: HeartRateViewModel
    @EnvironmentObject var settings: SettingsManager

    @State private var showSettings = false
    @State private var blink = false
    @State private var showStopConfirm = false
    @State private var showDisconnectConfirm = false
    @State private var showModeMenu = false
    @State private var chipFrame: CGRect = .zero

    private let themeColor = Color(red: 1.0, green: 0.42, blue: 0.42)

    var body: some View {
        ZStack {
            // 渐变背景
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.96, blue: 0.96), Color(white: 0.98)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                titleSection
                heartRateDisplay
                statusSection
                chartCard
                buttonSection
                Spacer()
                hintSection
            }
            .padding()

            if viewModel.showConnectionOverlay {
                ConnectionOverlayView(viewModel: viewModel)
                    .transition(.opacity)
                    .zIndex(10)
            }

            // 停止记录确认（防止误触）
            if showStopConfirm {
                GlassAlertOverlay(
                    iconName: "stop.circle.fill",
                    iconColor: .red,
                    title: "停止记录？",
                    message: "本次已记录 \(HeartRateRecording.format(duration: Date().timeIntervalSince(viewModel.recordingStartedAt ?? Date())))，停止后自动保存",
                    confirmTitle: "停止并保存",
                    confirmDestructive: true,
                    onConfirm: {
                        viewModel.stopRecording()
                        showStopConfirm = false
                    },
                    onCancel: { showStopConfirm = false }
                )
                .transition(.opacity)
                .zIndex(11)
            }

            // 记录中点断开连接：先停止并保存再断开
            if showDisconnectConfirm {
                GlassAlertOverlay(
                    iconName: "antenna.radiowaves.left.and.right.slash",
                    iconColor: .orange,
                    title: "心率记录进行中",
                    message: "断开连接将停止记录并自动保存本次数据",
                    confirmTitle: "停止记录并断开",
                    confirmDestructive: true,
                    onConfirm: {
                        viewModel.stopRecording()
                        viewModel.disconnect()
                        showDisconnectConfirm = false
                    },
                    onCancel: { showDisconnectConfirm = false }
                )
                .transition(.opacity)
                .zIndex(11)
            }

            // 上次异常退出遗留的未保存记录（最高优先级，必须二选一）
            if let pending = viewModel.pendingUnsavedRecording {
                let duration = pending.samples.last?.t.timeIntervalSince(pending.startedAt) ?? 0
                GlassAlertOverlay(
                    iconName: "waveform.path.ecg.circle",
                    iconColor: themeColor,
                    title: "发现未保存的记录",
                    message: "上次退出时有 \(pending.samples.count) 个采样点（\(HeartRateRecording.format(duration: duration))）尚未保存",
                    confirmTitle: "保存",
                    cancelTitle: "丢弃",
                    onConfirm: { viewModel.keepPendingUnsaved() },
                    onCancel: { viewModel.discardPendingUnsaved() }
                )
                .transition(.opacity)
                .zIndex(20)
            }
            // 长按记录按钮：自定义锚定模式菜单（contextMenu 形态，支持副标题）
            if showModeMenu {
                AnchoredMenuOverlay(anchor: chipFrame, items: [
                    AnchoredMenuItem(
                        title: "手动模式",
                        subtitle: "手动开始，停止时确认后保存",
                        isSelected: !viewModel.autoRecording
                    ) {
                        viewModel.autoRecording = false
                    },
                    AnchoredMenuItem(
                        title: "Auto 模式",
                        subtitle: "连接自动记录，断开自动保存",
                        isSelected: viewModel.autoRecording
                    ) {
                        viewModel.autoRecording = true
                    }
                ]) {
                    showModeMenu = false
                }
                .zIndex(12)
            }
            // 顶部 Toast（自动保存等提示）
            VStack {
                if let toastText = viewModel.toastText {
                    ToastView(text: toastText, iconName: viewModel.toastIcon, iconColor: viewModel.toastIconColor)
                }
                Spacer()
            }
            .zIndex(30)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.toastText)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showConnectionOverlay)
        .animation(.easeInOut(duration: 0.2), value: showStopConfirm)
        .animation(.easeInOut(duration: 0.2), value: showDisconnectConfirm)
        .animation(.easeInOut(duration: 0.2), value: showModeMenu)
        .animation(.easeInOut(duration: 0.2), value: viewModel.pendingUnsavedRecording != nil)
        .onPreferenceChange(GlobalFrameKey.self) { chipFrame = $0 }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private var titleSection: some View {
        HStack {
            Text("心率悬浮窗")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(themeColor)

            Spacer()

            // 设置入口：右上角齿轮，点按底部弹出设置面板
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(themeColor)
                    .frame(width: 38, height: 38)
                    .background(themeColor.opacity(0.12))
                    .clipShape(Circle())
            }
        }
    }

    private var heartRateDisplay: some View {
        HStack(alignment: .center, spacing: 10) {
            // 爱心按当前心率节拍跳动
            PulsingHeartIcon(bpm: viewModel.heartRate, active: viewModel.connectionState == .connected, color: themeColor)

            Text(viewModel.heartRate > 0 ? "\(viewModel.heartRate)" : "--")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundColor(themeColor)
                .animation(.easeOut(duration: 0.3), value: viewModel.heartRate)

            Text("BPM")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(themeColor.opacity(0.7))
                .padding(.top, 26)
        }
        .padding(.top, 4)
    }

    private var statusSection: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 心率曲线卡片

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("实时心率")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                recordingChip
                Text("最近 60 秒")
                    .font(.system(size: 11))
                    .foregroundColor(Color(.tertiaryLabel))
            }

            HeartRateChartView(themeColor: themeColor)
                .frame(height: 150)
        }
        .padding(14)
        .background(Color.white.opacity(0.9))
        .cornerRadius(18)
        .shadow(color: themeColor.opacity(0.10), radius: 10, y: 4)
    }

    // MARK: - 按钮

    private var buttonSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: {
                    if viewModel.connectionState == .connected {
                        // 手动模式记录中弹确认防误触；Auto 模式直接断开，由断连流程自动保存
                        if viewModel.isRecording && !viewModel.autoRecording {
                            showDisconnectConfirm = true
                        } else {
                            viewModel.disconnect()
                        }
                    } else if viewModel.connectionState != .connecting {
                        viewModel.connect()
                    }
                }) {
                    HStack {
                        Image(systemName: viewModel.connectionState == .connected ? "link.badge.plus" : "antenna.radiowaves.left.and.right")
                        Text(viewModel.connectionState == .connected ? "断开连接" : "连接手环")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(viewModel.connectionState == .connected ? Color(.systemGray4) : themeColor)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .shadow(color: viewModel.connectionState == .connected ? .clear : themeColor.opacity(0.35), radius: 8, y: 3)
                }
                .disabled(viewModel.connectionState == .connecting)
                .opacity(viewModel.connectionState == .connecting ? 0.5 : 1)

                Button(action: {
                    viewModel.togglePip()
                }) {
                    HStack {
                        Image(systemName: viewModel.isPipActive ? "pip.exit" : "pip.enter")
                        Text(viewModel.isPipActive ? "隐藏悬浮窗" : "显示悬浮窗")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(viewModel.isPipActive ? Color(red: 0.95, green: 0.55, blue: 0.55) : Color(red: 0.31, green: 0.80, blue: 0.77))
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .shadow(color: Color(red: 0.31, green: 0.80, blue: 0.77).opacity(viewModel.connectionState == .connected ? 0.35 : 0), radius: 8, y: 3)
                }
                .disabled(viewModel.connectionState != .connected)
                .opacity(viewModel.connectionState == .connected ? 1 : 0.55)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - 记录入口（曲线卡右上角紧凑胶囊，防误触；点按开始/停止，长按选模式）

    private var recordingChip: some View {
        Group {
            if viewModel.isRecording {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                        .opacity(blink ? 0.3 : 1)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: blink)
                        .onAppear { blink = true }
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(HeartRateRecording.format(duration: Date().timeIntervalSince(viewModel.recordingStartedAt ?? Date())))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    if viewModel.autoRecording {
                        Text("A")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 14, height: 14)
                            .background(Color.white.opacity(0.28), in: Circle())
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.red, in: Capsule())
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 12))
                    Text("记录")
                        .font(.system(size: 12, weight: .medium))
                    if viewModel.autoRecording {
                        Text("A")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 13, height: 13)
                            .background(themeColor.opacity(0.15), in: Circle())
                    }
                }
                .foregroundColor(themeColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(themeColor.opacity(0.12), in: Capsule())
            }
        }
        .opacity(viewModel.connectionState == .connected || viewModel.isRecording ? 1 : 0.45)
        .onTapGesture {
            if viewModel.isRecording {
                showStopConfirm = true
            } else if viewModel.connectionState == .connected {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.startRecording()
            }
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showModeMenu = true
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: GlobalFrameKey.self, value: geo.frame(in: .global))
            }
        )
    }

    private var statusText: String {
        switch viewModel.connectionState {
        case .disconnected:
            return "未连接"
        case .connecting:
            return "正在连接..."
        case .connected:
            return viewModel.connectedDeviceName.isEmpty ? "已连接" : "已连接 · \(viewModel.connectedDeviceName)"
        case .failed:
            return "连接失败"
        }
    }

    private var statusColor: Color {
        switch viewModel.connectionState {
        case .disconnected:
            return .gray
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .failed:
            return .red
        }
    }

    // MARK: - 底部提示（括号内容独立一行）

    private var hintSection: some View {
        VStack(spacing: 3) {
            Text("提示：请先在手环的设置中开启心率广播")
            Text("（不同机型开启路径略有差异）")
                .font(.system(size: 10))
                .opacity(0.75)
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
    }
}

// MARK: - 爱心图标（按当前心率节拍真实跳动）

struct PulsingHeartIcon: View {
    let bpm: Int
    let active: Bool
    let color: Color

    @State private var beating = false
    @State private var beatToken = UUID()

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 40))
            .foregroundColor(color)
            .scaleEffect(beating ? 1.22 : 1.0)
            .opacity(active ? 1 : 0.35)
            .onAppear(perform: restart)
            .onChange(of: bpm) { _ in restart() }
            .onChange(of: active) { _ in restart() }
    }

    private func restart() {
        beatToken = UUID()
        beating = false
        if active {
            startLoop(token: beatToken)
        }
    }

    /// 以 60/bpm 秒为周期循环：收缩 0.1s → 舒张 0.3s → 等待
    private func startLoop(token myToken: UUID) {
        guard active, bpm >= 30 else { return }
        let interval = 60.0 / Double(max(bpm, 30))
        let capturedToken = beatToken
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            guard capturedToken == myToken else { return }
            beat(token: myToken)
        }
    }

    private func beat(token myToken: UUID) {
        guard myToken == beatToken else { return }
        withAnimation(.easeOut(duration: 0.1)) { beating = true }
        let capturedToken = beatToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard capturedToken == myToken else { return }
            withAnimation(.easeInOut(duration: 0.3)) { beating = false }
            startLoop(token: myToken)
        }
    }
}

// MARK: - 实时心率图表（Canvas 逐帧绘制：网格 + 数值/时间刻度 + 直线折线 + 心电图式滚动）

struct HeartRateChartView: View {
    @EnvironmentObject var viewModel: HeartRateViewModel
    let themeColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, now: timeline.date)
            }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, now: Date) {
        let samples = viewModel.heartRateSamples.filter { now.timeIntervalSince($0.0) <= 61 }
        let validValues = samples.map { $0.1 }.filter { $0 > 0.05 }

        // 绘图区（左侧留 BPM 标签、底部留时间标签）
        let plot = CGRect(x: 34, y: 6, width: size.width - 40, height: size.height - 24)

        // 无数据：占位提示
        if validValues.isEmpty {
            let hint = viewModel.connectionState == .connected ? "正在采集心率数据..." : "连接手环后显示心率曲线"
            context.draw(
                Text(hint).font(.system(size: 13)).foregroundColor(Color(.tertiaryLabel)),
                at: CGPoint(x: size.width / 2, y: size.height / 2)
            )
            drawGrid(plot: plot, in: &context, lo: 50, hi: 90, viewport: 60)
            return
        }

        // 值域目标：紧贴 60 秒内数据的实际范围（含少量边距），小波动也能放大看出细节
        let vmin = validValues.min() ?? 60
        let vmax = validValues.max() ?? 100
        let mid = (vmin + vmax) / 2
        let span = max(vmax - vmin, 6) * 1.15
        let targetLo = mid - span / 2
        let targetHi = mid + span / 2

        // 值域指数趋近：范围变化时整条曲线平滑伸缩（先快后慢）
        let dt = min(max(now.timeIntervalSince(viewModel.lastFrameAt), 0), 0.1)
        viewModel.lastFrameAt = now
        let k = 1 - exp(-dt / 0.35)
        let lo: Double
        let hi: Double
        if let plo = viewModel.displayLo, let phi = viewModel.displayHi {
            lo = plo + (targetLo - plo) * k
            hi = phi + (targetHi - phi) * k
        } else {
            lo = targetLo
            hi = targetHi
        }
        viewModel.displayLo = lo
        viewModel.displayHi = hi

        // 时间 → x 坐标：视口右缘跟随最新采样点，两次采样之间画面完全静止。
        // 视口宽度自适应：统计不足 60 秒时全部数据拉伸铺满，
        // 超过 60 秒后固定 60 秒窗口跟随最新点滚动
        let base = viewModel.lastSampleAt
        let oldest = samples.first?.0 ?? base
        let viewport = min(60.0, max(base.timeIntervalSince(oldest), 5.0))

        drawGrid(plot: plot, in: &context, lo: lo, hi: hi, viewport: viewport)

        // 值 → y 坐标。超界点不压平，由绘图区剪裁自然裁掉，保持连续
        func yFor(_ v: Double) -> CGFloat {
            let ratio = min(max((v - lo) / max(hi - lo, 1), -0.2), 1.2)
            return plot.maxY - CGFloat(ratio) * plot.height
        }

        func xFor(_ t: Date) -> CGFloat {
            let age = base.timeIntervalSince(t) // 距最新采样的秒数
            return plot.maxX - CGFloat(age / viewport) * plot.width
        }

        // 剪裁绘图区
        context.clip(to: Path(plot))

        // 折线：直线段连接，按每个采样点的时间戳放置
        var line = Path()
        var started = false
        for (t, v) in samples where v > 0.05 {
            let p = CGPoint(x: xFor(t), y: yFor(v))
            if started {
                line.addLine(to: p)
            } else {
                line.move(to: p)
                started = true
            }
        }

        // 渐变填充
        var fill = line
        fill.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        fill.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
        fill.closeSubpath()
        context.fill(fill, with: .linearGradient(
            Gradient(colors: [themeColor.opacity(0.30), themeColor.opacity(0.02)]),
            startPoint: CGPoint(x: 0, y: plot.minY),
            endPoint: CGPoint(x: 0, y: plot.maxY)
        ))

        // 折线描边
        context.stroke(line, with: .color(themeColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        // 当前心率圆点：贴右缘（视口跟随最新点），按心率节拍向外扩散
        if let last = samples.last, last.1 > 0.05 {
            let head = CGPoint(x: plot.maxX, y: yFor(last.1))

            let bpm = max(viewModel.heartRate, 40)
            let beatInterval = 60.0 / Double(bpm)
            let phase = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: beatInterval) / beatInterval
            let expand = 1 - phase // 1 → 0 向外扩散衰减

            context.fill(Path(ellipseIn: CGRect(x: head.x - 4, y: head.y - 4, width: 8, height: 8)), with: .color(themeColor))
            context.stroke(
                Path(ellipseIn: CGRect(x: head.x - 5 - 7 * expand, y: head.y - 5 - 7 * expand, width: 10 + 14 * expand, height: 10 + 14 * expand)),
                with: .color(themeColor.opacity(0.5 * expand)),
                lineWidth: 1.5
            )
        }
    }

    /// 网格线 + 横向 BPM 数值 + 纵向时间刻度
    private func drawGrid(plot: CGRect, in context: inout GraphicsContext, lo: Double, hi: Double, viewport: Double) {
        let labelColor = Color(.tertiaryLabel)
        let gridColor = Color(.systemGray5)

        // 水平网格：刻度对齐整数 BPM（步长取 1/2/5×10ⁿ），标签数值与线的位置精确一致
        let span = hi - lo
        let rawStep = span / 5.5
        let magnitude = pow(10.0, floor(log10(rawStep)))
        let normalized = rawStep / magnitude
        let step = (normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 7 ? 5 : 10) * magnitude
        var v = (lo / step).rounded(.up) * step
        while v <= hi + 0.001 {
            let y = plot.maxY - CGFloat((v - lo) / max(span, 0.001)) * plot.height
            var grid = Path()
            grid.move(to: CGPoint(x: plot.minX, y: y))
            grid.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(grid, with: .color(gridColor), lineWidth: 0.8)
            context.draw(
                Text("\(Int(v.rounded()))").font(.system(size: 9, design: .monospaced)).foregroundColor(labelColor),
                at: CGPoint(x: plot.minX - 14, y: y)
            )
            v += step
        }

        // 垂直网格：时间刻度跟随实际视口宽度（拉伸期显示真实统计秒数，满窗口后 -60s → 现在）
        let timeMarks: [(String, CGFloat)] = [
            ("-\(Int(viewport.rounded()))s", 0),
            ("-\(Int((viewport * 2.0 / 3.0).rounded()))s", 1.0 / 3.0),
            ("-\(Int((viewport / 3.0).rounded()))s", 2.0 / 3.0),
            ("现在", 1)
        ]
        for (label, frac) in timeMarks {
            let x = plot.minX + frac * plot.width
            var grid = Path()
            grid.move(to: CGPoint(x: x, y: plot.minY))
            grid.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.stroke(grid, with: .color(gridColor), lineWidth: 0.8)
            context.draw(
                Text(label).font(.system(size: 9)).foregroundColor(labelColor),
                at: CGPoint(x: x, y: plot.maxY + 10)
            )
        }
    }
}

// MARK: - 连接弹窗（毛玻璃 + 日志 + 结果动画 + 取消）

struct ConnectionOverlayView: View {
    @ObservedObject var viewModel: HeartRateViewModel
    @State private var resultIconShown = false
    @State private var appeared = false

    private var isFailed: Bool { viewModel.connectionState == .failed }
    private var isConnected: Bool { viewModel.connectionState == .connected }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { } // 阻断点击穿透

            VStack(spacing: 14) {
                statusIcon

                Text(statusTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)

                logList

                // 连接成功后按钮没有意义（弹窗随即自动关闭），直接隐藏
                if !isConnected {
                    cancelButton
                }
            }
            .padding(22)
            .frame(width: 310)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
            // 开场：淡入 + spring 展开（与其他弹窗一致）
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: isConnected)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                appeared = true
            }
        }
        .onChange(of: viewModel.connectionState) { state in
            if state == .connected || state == .failed {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    resultIconShown = true
                }
            } else {
                resultIconShown = false
            }
        }
    }

    private var statusTitle: String {
        if isConnected { return "连接成功" }
        if isFailed { return "连接失败" }
        return "正在搜索手环..."
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isConnected {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundColor(.green)
                .scaleEffect(resultIconShown ? 1.0 : 0.2)
                .opacity(resultIconShown ? 1.0 : 0.0)
        } else if isFailed {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 54))
                .foregroundColor(.red)
                .scaleEffect(resultIconShown ? 1.0 : 0.2)
                .opacity(resultIconShown ? 1.0 : 0.0)
        } else {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 4)
                    .frame(width: 54, height: 54)
                ProgressView()
                    .scaleEffect(1.3)
            }
        }
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(viewModel.logMessages.suffix(30).enumerated()), id: \.offset) { _, message in
                        Text(message)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id("overlayLogBottom")
                }
                .padding(10)
            }
            .frame(height: 130)
            .background(Color(.systemGray6).opacity(0.75))
            .cornerRadius(12)
            .onChange(of: viewModel.logMessages.count) { _ in
                withAnimation(.linear(duration: 0.12)) {
                    proxy.scrollTo("overlayLogBottom", anchor: .bottom)
                }
            }
        }
    }

    private var cancelButton: some View {
        Button(action: {
            if isFailed {
                viewModel.showConnectionOverlay = false
            } else {
                viewModel.cancelConnect()
            }
        }) {
            Text(isFailed ? "关闭" : "取消连接")
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemGray5))
                .foregroundColor(.primary)
                .cornerRadius(12)
        }
    }
}

// MARK: - 通用毛玻璃确认弹窗

struct GlassAlertOverlay: View {
    var iconName: String
    var iconColor: Color
    var title: String
    var message: String
    var confirmTitle: String
    var confirmDestructive = false
    var cancelTitle: String? = "取消"
    var onConfirm: () -> Void
    var onCancel: (() -> Void)? = nil

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { } // 阻断点击穿透

            VStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 50))
                    .foregroundColor(iconColor)

                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)

                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onConfirm()
                    }) {
                        Text(confirmTitle)
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(confirmDestructive ? Color.red : Color(red: 1.0, green: 0.42, blue: 0.42))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    if let cancelTitle = cancelTitle {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onCancel?()
                        }) {
                            Text(cancelTitle)
                                .font(.system(size: 15, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.systemGray5))
                                .foregroundColor(.primary)
                                .cornerRadius(12)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(22)
            .frame(width: 310)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
            // 开场：淡入 + spring 展开（与清理缓存弹窗一致）
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                appeared = true
            }
        }
    }
}

// MARK: - 锚定弹出菜单（contextMenu 形态的自定义实现，支持副标题说明）

/// 锚点 frame 通过 preference 传递（主界面无 ScrollView，传播可靠）
struct GlobalFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct AnchoredMenuItem: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var isSelected = false
    var isDestructive = false
    var action: () -> Void
}

/// 菜单卡片本体（毛玻璃 + 副标题行），被锚定容器的不同定位方式共用
struct AnchoredMenuCard: View {
    let items: [AnchoredMenuItem]
    var onClose: () -> Void
    /// 展开动画的锚点（向上弹出的菜单从底部展开）
    var popAnchor: UnitPoint = .bottom

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 2) {
            ForEach(items) { item in
                row(item)
                if item.id != items.last?.id {
                    Divider()
                        .padding(.horizontal, 14)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(width: 250)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.16), radius: 20, y: 6)
        // 开场：淡入 + spring 展开
        .scaleEffect(appeared ? 1 : 0.8, anchor: popAnchor)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                appeared = true
            }
        }
    }

    private func row(_ item: AnchoredMenuItem) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            item.action()
            onClose()
        }) {
            HStack(spacing: 10) {
                if let icon = item.icon {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundColor(item.isDestructive ? .red : Color(red: 1.0, green: 0.42, blue: 0.42))
                        .frame(width: 20)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(item.isDestructive ? .red : .primary)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if item.isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.42))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AnchoredMenuOverlay: View {
    let anchor: CGRect
    let items: [AnchoredMenuItem]
    var onClose: () -> Void

    private let menuWidth: CGFloat = 250

    var body: some View {
        GeometryReader { geo in
            let screen = geo.frame(in: .global)
            // 锚点未获取到时（preference 未传播）回退到曲线卡头部附近的估算位置，避免出现在角落
            let effectiveAnchor = anchor.width > 1
                ? anchor
                : CGRect(x: screen.maxX - 90, y: screen.minY + 230, width: 80, height: 30)
            let menuHeight = Self.estimatedHeight(for: items)
            // 优先在锚点上方弹出，空间不足时移到下方；水平方向右对齐锚点并夹在屏幕内
            let popsUp = effectiveAnchor.minY - menuHeight - 12 > screen.minY + 50
            let menuY = popsUp ? effectiveAnchor.minY - menuHeight - 8 : effectiveAnchor.maxY + 8
            let menuX = min(max(effectiveAnchor.maxX - menuWidth, screen.minX + 12), screen.maxX - menuWidth - 12)

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12).onEnded { _ in onClose() }
                )
                .overlay(
                    AnchoredMenuCard(items: items, onClose: onClose)
                        .position(x: menuX + menuWidth / 2, y: menuY + menuHeight / 2)
                        .transition(.opacity)
                )
        }
        // 让 GeometryReader 的坐标系与全局坐标一致，锚点定位才准确
        .ignoresSafeArea()
    }

    /// 估算菜单高度用于锚定定位（卡片实际高度由内容自然撑开）
    private static func estimatedHeight(for items: [AnchoredMenuItem]) -> CGFloat {
        let rowHeight: CGFloat = items.contains { $0.subtitle != nil } ? 52 : 38
        return CGFloat(items.count) * rowHeight + 12
    }
}

// MARK: - Toast 提示（毛玻璃胶囊，自动消失）

struct ToastView: View {
    let text: String
    var iconName: String = "checkmark.circle.fill"
    var iconColor: Color = .green

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 16, y: 5)
        // 开场：淡入 + spring 展开
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                appeared = true
            }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
            .environmentObject(HeartRateViewModel())
            .environmentObject(SettingsManager.shared)
    }
}
