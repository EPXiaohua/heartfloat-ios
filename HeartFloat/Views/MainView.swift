import SwiftUI

struct MainView: View {
    @EnvironmentObject var viewModel: HeartRateViewModel
    @EnvironmentObject var settings: SettingsManager

    private let themeColor = Color(red: 1.0, green: 0.42, blue: 0.42)

    var body: some View {
        ZStack {
            // 渐变背景
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.96, blue: 0.96), Color(white: 0.98)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            NavigationView {
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
                .navigationBarHidden(true)
            }

            if viewModel.showConnectionOverlay {
                ConnectionOverlayView(viewModel: viewModel)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.showConnectionOverlay)
    }

    private var titleSection: some View {
        Text("心率悬浮窗")
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundColor(themeColor)
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
            HStack {
                Text("实时心率")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
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
                        viewModel.disconnect()
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

            NavigationLink(destination: SettingsView()) {
                HStack {
                    Image(systemName: "gearshape.fill")
                    Text("设置")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.64, green: 0.38, blue: 0.75), Color(red: 0.55, green: 0.32, blue: 0.68)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(14)
                .shadow(color: Color(red: 0.61, green: 0.35, blue: 0.71).opacity(0.3), radius: 8, y: 3)
            }
        }
        .padding(.top, 2)
    }

    private var statusText: String {
        switch viewModel.connectionState {
        case .disconnected:
            return "未连接"
        case .connecting:
            return "正在连接..."
        case .connected:
            return "已连接"
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
        let values = viewModel.heartRateHistory
        let validValues = values.filter { $0 > 0 }

        // 绘图区（左侧留 BPM 标签、底部留时间标签）
        let plot = CGRect(x: 34, y: 6, width: size.width - 40, height: size.height - 24)

        // 无数据：占位提示
        if validValues.isEmpty {
            let hint = viewModel.connectionState == .connected ? "正在采集心率数据..." : "连接手环后显示心率曲线"
            context.draw(
                Text(hint).font(.system(size: 13)).foregroundColor(Color(.tertiaryLabel)),
                at: CGPoint(x: size.width / 2, y: size.height / 2)
            )
            drawGrid(plot: plot, in: &context, lo: 60, hi: 100)
            return
        }

        // 值范围（取整到 10，幅度小时扩到 20）
        var hi = ceil((validValues.max() ?? 100) / 10) * 10
        var lo = floor((validValues.min() ?? 60) / 10) * 10
        if hi - lo < 20 {
            let mid = (hi + lo) / 2
            lo = mid - 10
            hi = mid + 10
        }

        drawGrid(plot: plot, in: &context, lo: lo, hi: hi)

        // 滚动动画进度：新样本到来后 0.6 秒内，曲线从右移一格的位置平滑滑回（ease-out：先快后慢）
        let elapsed = now.timeIntervalSince(viewModel.lastSampleAt)
        let t = min(max(elapsed / 0.6, 0), 1)
        let progress = 1 - pow(1 - t, 3) // cubic ease-out

        // 值 → y 坐标
        func yFor(_ v: Double) -> CGFloat {
            let ratio = min(max((v - lo) / (hi - lo), 0), 1)
            return plot.maxY - CGFloat(ratio) * plot.height
        }

        // 剪裁绘图区，滚动时旧点滑出边界
        context.clip(to: Path(plot))

        // 折线：直线段连接（心电图风格），x 随滚动进度整体平移一格
        var line = Path()
        let n = values.count
        for i in 0..<n where values[i] > 0 {
            let x = plot.minX + CGFloat((Double(i) + (1 - progress)) / Double(n - 1)) * plot.width
            let p = CGPoint(x: x, y: yFor(values[i]))
            if i == 0 || values[i - 1] <= 0 {
                line.move(to: p)
            } else {
                line.addLine(to: p)
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

        // 末端圆点：跟随滚动位置，并按心率节拍向外扩散
        if let lastValue = values.last, lastValue > 0 {
            let headX = plot.minX + CGFloat((Double(n - 1) + (1 - progress)) / Double(n - 1)) * plot.width
            let head = CGPoint(x: headX, y: yFor(lastValue))

            let bpm = max(viewModel.heartRate, 40)
            let beatInterval = 60.0 / Double(bpm)
            let phase = now.timeIntervalSince(viewModel.lastSampleAt).truncatingRemainder(dividingBy: beatInterval) / beatInterval
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
    private func drawGrid(plot: CGRect, in context: inout GraphicsContext, lo: Double, hi: Double) {
        let labelColor = Color(.tertiaryLabel)
        let gridColor = Color(.systemGray5)

        // 水平网格：上 / 中 / 下 三条，标注 BPM 值
        let gridValues: [Double] = [hi, (hi + lo) / 2, lo]
        for v in gridValues {
            let y = plot.maxY - CGFloat((v - lo) / (hi - lo)) * plot.height
            var grid = Path()
            grid.move(to: CGPoint(x: plot.minX, y: y))
            grid.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(grid, with: .color(gridColor), lineWidth: 0.8)
            context.draw(
                Text("\(Int(v))").font(.system(size: 9, design: .monospaced)).foregroundColor(labelColor),
                at: CGPoint(x: plot.minX - 14, y: y)
            )
        }

        // 垂直网格：-60s / -40s / -20s / 现在
        let timeMarks: [(String, CGFloat)] = [("-60s", 0), ("-40s", 1.0 / 3.0), ("-20s", 2.0 / 3.0), ("现在", 1)]
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

                cancelButton
            }
            .padding(22)
            .frame(width: 310)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
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

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
            .environmentObject(HeartRateViewModel())
            .environmentObject(SettingsManager.shared)
    }
}
