import SwiftUI

struct MainView: View {
    @EnvironmentObject var viewModel: HeartRateViewModel
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        ZStack {
            NavigationView {
                VStack(spacing: 16) {
                    titleSection

                    heartRateDisplay

                    statusSection

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
            .font(.system(size: 28, weight: .bold))
            .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.42))
    }

    private var heartRateDisplay: some View {
        Text(viewModel.heartRate > 0 ? "\(viewModel.heartRate) BPM" : "-- BPM")
            .font(.system(size: 56, weight: .bold))
            .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.42))
            .padding(.top, 24)
    }

    private var statusSection: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
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

    private var buttonSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
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
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.connectionState == .connected ? Color.gray : Color(red: 1.0, green: 0.42, blue: 0.42))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(viewModel.connectionState == .connecting)
                .opacity(viewModel.connectionState == .connecting ? 0.5 : 1)

                Button(action: {
                    viewModel.togglePip()
                }) {
                    HStack {
                        Image(systemName: viewModel.isPipActive ? "pip.exit" : "pip.enter")
                        Text(viewModel.isPipActive ? "隐藏悬浮窗" : "显示悬浮窗")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.isPipActive ? Color(red: 1.0, green: 0.42, blue: 0.42) : Color(red: 0.31, green: 0.80, blue: 0.77))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(viewModel.connectionState != .connected)
                .opacity(viewModel.connectionState == .connected ? 1 : 0.5)
            }

            NavigationLink(destination: SettingsView()) {
                HStack {
                    Image(systemName: "gear")
                    Text("设置")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(red: 0.61, green: 0.35, blue: 0.71))
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding(.top, 8)
    }

    private var hintSection: some View {
        Text("提示：请先在手环的设置中开启心率广播（不同机型开启路径略有差异）")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
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
                    // 最早的在上、最新的在下
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
