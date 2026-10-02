import SwiftUI

struct MainView: View {
    @EnvironmentObject var viewModel: HeartRateViewModel
    @EnvironmentObject var settings: SettingsManager

    @State private var heartPulse = false

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
            Image(systemName: "heart.fill")
                .font(.system(size: 40))
                .foregroundColor(themeColor)
                .scaleEffect(heartPulse ? 1.18 : 1.0)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: heartPulse)
                .opacity(viewModel.connectionState == .connected ? 1 : 0.35)

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
        .onAppear { heartPulse = true }
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

            GeometryReader { geo in
                let data = ChartData(values: viewModel.heartRateHistory)
                let endPoint = chartEndPoint(data: data, in: geo.size)

                ZStack(alignment: .topLeading) {
                    // 曲线下方渐变填充
                    HeartRateCurveShape(data: data, filled: true)
                        .fill(
                            LinearGradient(
                                colors: [themeColor.opacity(0.35), themeColor.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )

                    // 平滑贝塞尔曲线（ease-out：先快后慢的过渡动画）
                    HeartRateCurveShape(data: data, filled: false)
                        .stroke(
                            LinearGradient(
                                colors: [themeColor.opacity(0.75), themeColor],
                                startPoint: .leading, endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )

                    // 曲线末端脉冲圆点
                    if hasValidData {
                        Circle()
                            .fill(themeColor)
                            .frame(width: 8, height: 8)
                            .position(endPoint)
                            .overlay(
                                Circle()
                                    .stroke(themeColor.opacity(0.4))
                                    .frame(width: 8, height: 8)
                                    .scaleEffect(heartPulse ? 2.4 : 1.0)
                                    .opacity(heartPulse ? 0 : 1)
                                    .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: heartPulse)
                            )
                    }
                }
            }
            .frame(height: 150)
            .animation(.easeOut(duration: 0.7), value: viewModel.heartRateHistory)
        }
        .padding(14)
        .background(Color.white.opacity(0.9))
        .cornerRadius(18)
        .shadow(color: themeColor.opacity(0.10), radius: 10, y: 4)
        .overlay(
            // 无数据占位
            Group {
                if !hasValidData {
                    Text(viewModel.connectionState == .connected ? "正在采集心率数据..." : "连接手环后显示心率曲线")
                        .font(.system(size: 13))
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }
        )
    }

    private var hasValidData: Bool {
        viewModel.heartRateHistory.contains { $0 > 0 }
    }

    /// 曲线末端坐标（与 HeartRateCurveShape 内部映射公式完全一致）
    private func chartEndPoint(data: ChartData, in size: CGSize) -> CGPoint {
        let values = data.values
        let validValues = values.filter { $0 > 0 }
        guard let last = values.last, last > 0, !validValues.isEmpty else {
            return CGPoint(x: size.width - 4, y: size.height)
        }

        var maxValue = validValues.max() ?? 100
        var minValue = validValues.min() ?? 60
        if maxValue - minValue < 8 {
            let mid = (maxValue + minValue) / 2
            minValue = mid - 4
            maxValue = mid + 4
        }

        let ratio = min(max((last - minValue) / (maxValue - minValue), 0.02), 1.0)
        let h = size.height
        let y = h * 0.08 + h * 0.92 * (1 - ratio * 0.92)
        return CGPoint(x: size.width - 4, y: min(max(y, 4), h - 4))
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

// MARK: - 心率平滑曲线（Catmull-Rom → 三次贝塞尔）

struct HeartRateCurveShape: Shape {
    var data: ChartData
    var filled: Bool

    func path(in rect: CGRect) -> Path {
        let values = data.values
        guard values.count > 1, rect.width > 0, rect.height > 0 else { return Path() }

        let validValues = values.filter { $0 > 0 }
        guard !validValues.isEmpty else { return Path() }

        var maxValue = validValues.max() ?? 100
        var minValue = validValues.min() ?? 60
        // 幅度过小时扩一点，避免曲线退化成贴边直线
        if maxValue - minValue < 8 {
            let mid = (maxValue + minValue) / 2
            minValue = mid - 4
            maxValue = mid + 4
        }

        let topInset = rect.height * 0.08
        let usableHeight = rect.height - topInset

        func mappedPoint(index: Int) -> CGPoint {
            let x = rect.width * CGFloat(index) / CGFloat(values.count - 1)
            let v = values[index]
            let ratio: CGFloat
            if v <= 0 {
                // 无数据点画在最底
                ratio = 0
            } else {
                let r = CGFloat((Double(v) - minValue) / Double(maxValue - minValue))
                ratio = min(max(r, 0.02), 1.0)
            }
            let y = topInset + usableHeight * (1 - CGFloat(ratio) * 0.92)
            return CGPoint(x: x, y: y)
        }

        let points = (0..<values.count).map(mappedPoint)

        var path = Path()
        path.move(to: points[0])
        if points.count == 2 {
            path.addLine(to: points[1])
        } else {
            // Catmull-Rom 样条转换成三次贝塞尔，过渡平滑
            for i in 0..<points.count - 1 {
                let p0 = points[max(i - 1, 0)]
                let p1 = points[i]
                let p2 = points[i + 1]
                let p3 = points[min(i + 2, points.count - 1)]

                let cp1 = CGPoint(
                    x: p1.x + (p2.x - p0.x) / 6,
                    y: p1.y + (p2.y - p0.y) / 6
                )
                let cp2 = CGPoint(
                    x: p2.x - (p3.x - p1.x) / 6,
                    y: p2.y - (p3.y - p1.y) / 6
                )
                path.addCurve(to: p2, control1: cp1, control2: cp2)
            }
        }

        if filled {
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: rect.height))
            path.closeSubpath()
        }
        return path
    }
}

/// 固定长度 Double 数组，实现 VectorArithmetic 以支持 SwiftUI Path 插值动画
struct ChartData: VectorArithmetic {
    var values: [Double]

    static var zero: ChartData { ChartData(values: []) }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }

    static func + (lhs: ChartData, rhs: ChartData) -> ChartData {
        var result = lhs
        result += rhs
        return result
    }

    static func - (lhs: ChartData, rhs: ChartData) -> ChartData {
        var result = lhs
        result -= rhs
        return result
    }

    static func += (lhs: inout ChartData, rhs: ChartData) {
        guard lhs.values.count == rhs.values.count else { return }
        for i in 0..<lhs.values.count {
            lhs.values[i] += rhs.values[i]
        }
    }

    static func -= (lhs: inout ChartData, rhs: ChartData) {
        guard lhs.values.count == rhs.values.count else { return }
        for i in 0..<lhs.values.count {
            lhs.values[i] -= rhs.values[i]
        }
    }

    mutating func scale(by rhs: Double) {
        for i in 0..<values.count {
            values[i] *= rhs
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
