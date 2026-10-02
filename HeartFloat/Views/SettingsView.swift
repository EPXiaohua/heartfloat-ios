import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var viewModel: HeartRateViewModel

    @State private var showingColorPicker = false
    @State private var colorPickerTarget: ColorPickerTarget = .bpmNumber

    @State private var httpPort: String = "8080"
    @State private var showingHttpAlert = false
    @State private var httpAlertMessage = ""

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

                httpPushSettings

                presetSection
            }
            .padding()
        }
        .navigationTitle("设置")
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
        .alert("提示", isPresented: $showingHttpAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(httpAlertMessage)
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

    private var httpPushSettings: some View {
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
                    .foregroundColor(.blue)
                }

                if let ip = HttpServerManager.shared.localIP {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("本机地址")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("http://\(ip):\(settings.httpPushPort)")
                            .font(.system(size: 14, design: .monospaced))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("API接口说明")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("/heartbeat - 返回纯文本心率值\n/heartbeat.json - 返回JSON格式数据\n/live - 直播专用页面")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.blue)
                }
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

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SettingsView()
                .environmentObject(SettingsManager.shared)
                .environmentObject(HeartRateViewModel())
        }
    }
}
