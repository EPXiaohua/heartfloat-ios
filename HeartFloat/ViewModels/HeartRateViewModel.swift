import Foundation
import Combine
import SwiftUI
import UIKit
import AVKit
import AVFoundation

class HeartRateViewModel: NSObject, ObservableObject {
    @Published var heartRate: Int = 0
    @Published var connectionState: BleService.ConnectionState = .disconnected
    @Published var isContact: Bool = false
    @Published var logMessages: [String] = []
    @Published var isPipActive: Bool = false
    @Published var showConnectionOverlay: Bool = false
    /// 心率记录状态（记录模式下采样点无限追加，不受 60 秒窗口限制）
    @Published var isRecording = false
    @Published var recordingStartedAt: Date?
    @Published var recordings: [HeartRateRecording] = []
    /// 记录模式：Auto = 心率通知就绪后自动开始记录，断开时自动保存
    @Published var autoRecording: Bool = UserDefaults.standard.bool(forKey: "recordingAutoMode") {
        didSet {
            guard oldValue != autoRecording else { return }
            UserDefaults.standard.set(autoRecording, forKey: "recordingAutoMode")
            // 已连接状态下切到 Auto：立即开始记录，到断开时自动保存
            if autoRecording, connectionState == .connected, !isRecording {
                startRecording()
            }
        }
    }
    /// 上次异常退出遗留的未保存记录（启动时检测，弹窗询问保存或丢弃）
    @Published var pendingUnsavedRecording: HeartRateRecording?
    /// 顶部 Toast 提示文本（自动保存等），短暂显示后自动消失
    @Published var toastText: String?
    /// Toast 图标与颜色（默认绿色对勾，更新提示等场景可换）
    @Published var toastIcon: String = "checkmark.circle.fill"
    @Published var toastIconColor: Color = .green
    /// 用户主动断开标记（用于区分断连 Toast 文案）
    private var userInitiatedDisconnect = false
    private var toastToken: UUID?
    /// 当前连接的设备名
    @Published var connectedDeviceName: String = ""
    /// 心率采样点（时间戳 + 值）：每次采样无条件追加，曲线按绝对时间轴绘制，
    /// 视口跟随最新点，同值采样表现为水平线平移（形态不变），值变化才出现形态变化
    var heartRateSamples: [(Date, Double)] = []
    /// 最近一次采样时间（视口基准）
    var lastSampleAt: Date = .distantPast
    /// 值域显示范围（指数趋近缓存）：当前心率 vs 整体范围做平滑对比缩放
    var displayLo: Double?
    var displayHi: Double?
    /// 上一帧时间（计算趋近步长）
    var lastFrameAt: Date = .distantPast

    private let bleService = BleService.shared
    private let httpServer = HttpServerManager.shared
    private let wsServer = WsServerManager.shared
    private let updateChecker = UpdateChecker.shared
    private let settings = SettingsManager.shared
    private let renderer = HeartRateVideoRenderer.shared
    private var cancellables = Set<AnyCancellable>()
    private var pipController: AVPictureInPictureController?
    private var pipPlayer: AVQueuePlayer?
    private var pipPlayerLayer: AVPlayerLayer?
    private var pipLooper: AVPlayerLooper?
    private var pipCarrierView: UIView?
    private var pipOverlay: HeartRatePipView?
    private var userRequestedStop = false
    private var activeRecording: HeartRateRecording?

    override init() {
        super.init()
        recordings = HeartRateRecordingStore.loadAll()
        pendingUnsavedRecording = HeartRateRecordingStore.loadUnsaved()
        setupBindings()
        startConfiguredServers()
        startUpdateCheck()
    }

    deinit {
        userRequestedStop = true
        teardownPip(log: false)
    }

    private func setupBindings() {
        bleService.$currentHeartRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rate in
                guard let self = self else { return }
                self.httpServer.updateHeartRate(rate, contact: self.isContact)
                self.wsServer.updateHeartRate(rate, contact: self.isContact)

                // 无读数（断连归零）不记录采样点
                if rate > 0 {
                    // 每次采样无条件记录（含相同值），并裁掉窗口外的旧点
                    let now = Date()
                    self.heartRateSamples.append((now, Double(rate)))
                    while let first = self.heartRateSamples.first, now.timeIntervalSince(first.0) > 65 {
                        self.heartRateSamples.removeFirst()
                    }
                    self.lastSampleAt = now

                    // 记录模式下无限追加，不受 60 秒窗口限制
                    if self.isRecording, var session = self.activeRecording {
                        session.samples.append(.init(t: now, bpm: rate))
                        self.activeRecording = session
                        // 每 5 个采样点快照一次，应用异常退出后可恢复保存
                        if session.samples.count % 5 == 0 {
                            HeartRateRecordingStore.saveUnsaved(session)
                        }
                    }
                }

                // 数字大字 / 画中画仅在值变化时刷新
                guard rate != self.heartRate else { return }
                self.heartRate = rate
                self.pipOverlay?.update(heartRate: rate)
            }
            .store(in: &cancellables)

        bleService.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                self.connectionState = state

                // 断开后读数归零、曲线清空，重新连接后从头统计
                if state == .disconnected || state == .failed {
                    // 记录进行中随断连结束：数据源已消失，自动保存本次会话
                    if self.isRecording {
                        if self.userInitiatedDisconnect {
                            self.stopRecording(showToast: "记录已自动保存")
                        } else {
                            self.stopRecording(showToast: "连接已断开，记录已自动保存")
                        }
                    }
                    self.userInitiatedDisconnect = false
                    self.heartRate = 0
                    self.pipOverlay?.update(heartRate: 0)
                    self.isContact = false
                    self.httpServer.updateHeartRate(0, contact: false)
                    self.heartRateSamples.removeAll()
                    self.lastSampleAt = .distantPast
                    self.displayLo = nil
                    self.displayHi = nil
                    self.lastFrameAt = .distantPast
                }

                // 连接成功后展示勾动画片刻再自动关闭弹窗
                if state == .connected {
                    // Auto 模式：心率通知就绪即自动开始记录
                    if self.autoRecording && !self.isRecording {
                        self.startRecording()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                        self?.showConnectionOverlay = false
                    }
                }
            }
            .store(in: &cancellables)

        bleService.$isContact
            .receive(on: DispatchQueue.main)
            .assign(to: &$isContact)

        bleService.$connectedDeviceName
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectedDeviceName)

        bleService.$logMessages
            .receive(on: DispatchQueue.main)
            .assign(to: &$logMessages)

        // 设置变化实时应用到悬浮窗
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.pipOverlay?.apply(settings: self.settings)
            }
            .store(in: &cancellables)
    }

    func connect() {
        showConnectionOverlay = true
        bleService.startScan()
    }

    func cancelConnect() {
        bleService.cancelScan()
        showConnectionOverlay = false
    }

    func disconnect() {
        userInitiatedDisconnect = true
        bleService.disconnect()
    }

    // MARK: - 心率记录

    func startRecording() {
        guard !isRecording else { return }
        let session = HeartRateRecording(startedAt: Date(), endedAt: Date())
        activeRecording = session
        recordingStartedAt = session.startedAt
        isRecording = true
    }

    func stopRecording(showToast text: String? = "记录已保存") {
        guard isRecording, var session = activeRecording else { return }
        session.endedAt = Date()
        isRecording = false
        activeRecording = nil
        recordingStartedAt = nil
        HeartRateRecordingStore.removeUnsaved()
        // 少于两个采样点的会话没有查看价值，不保存并提示
        guard session.samples.count >= 2 else {
            showToast("采样点不足，记录未保存", icon: "exclamationmark.triangle.fill", iconColor: .orange)
            return
        }
        HeartRateRecordingStore.save(session)
        recordings = HeartRateRecordingStore.loadAll()
        if let text = text {
            showToast(text)
        }
    }

    /// 顶部 Toast 提示，短暂显示后自动消失
    func showToast(_ text: String, icon: String = "checkmark.circle.fill", iconColor: Color = .green) {
        let token = UUID()
        toastToken = token
        toastIcon = icon
        toastIconColor = iconColor
        withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
            toastText = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self = self, self.toastToken == token else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                self.toastText = nil
            }
        }
    }

    /// 保存上次异常退出遗留的记录（时长以最后一个采样点为准）
    func keepPendingUnsaved() {
        guard var session = pendingUnsavedRecording else { return }
        session.endedAt = session.samples.last?.t ?? session.startedAt
        HeartRateRecordingStore.save(session)
        HeartRateRecordingStore.removeUnsaved()
        recordings = HeartRateRecordingStore.loadAll()
        pendingUnsavedRecording = nil
    }

    /// 丢弃上次异常退出遗留的记录；若新会话已在写快照则保留快照文件
    func discardPendingUnsaved() {
        if activeRecording == nil {
            HeartRateRecordingStore.removeUnsaved()
        }
        pendingUnsavedRecording = nil
    }

    /// 批量删除记录
    func deleteRecordings(withIDs ids: Set<UUID>) {
        HeartRateRecordingStore.delete(ids)
        recordings = HeartRateRecordingStore.loadAll()
    }

    func deleteRecording(_ recording: HeartRateRecording) {
        HeartRateRecordingStore.delete(recording)
        recordings = HeartRateRecordingStore.loadAll()
    }

    enum ImportError: LocalizedError {
        case unrecognizedFormat

        var errorDescription: String? {
            switch self {
            case .unrecognizedFormat:
                return "无法识别的文件格式，请导入本应用导出的 JSON 或 CSV 文件"
            }
        }
    }

    /// 从文件导入心率记录（支持本应用导出的 JSON 与 CSV 格式），导入的记录单独分组展示
    func importRecording(from url: URL) throws {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)

        // 优先按 JSON（本应用导出格式）解析，失败再按 CSV 解析
        var session = HeartRateRecordingStore.decode(data)
        if session == nil, let text = String(data: data, encoding: .utf8) {
            session = Self.parseCSV(text)
        }
        guard var record = session, record.samples.count >= 2 else {
            throw ImportError.unrecognizedFormat
        }
        record.imported = true
        record.startedAt = record.samples.first?.t ?? record.startedAt
        record.endedAt = record.samples.last?.t ?? record.endedAt
        HeartRateRecordingStore.save(record)
        recordings = HeartRateRecordingStore.loadAll()
    }

    /// 解析本应用导出的 CSV（timestamp,bpm，ISO8601 时间）
    private static func parseCSV(_ text: String) -> HeartRateRecording? {
        var samples: [HeartRateRecording.Sample] = []
        let lines = text.components(separatedBy: .newlines)
        for line in lines.dropFirst() {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: ",")
            guard parts.count >= 2,
                  let t = HeartRateRecordingStore.iso8601.date(from: String(parts[0])),
                  let bpm = Int(parts[1]) else { continue }
            samples.append(.init(t: t, bpm: bpm))
        }
        guard samples.count >= 2 else { return nil }
        return HeartRateRecording(startedAt: samples[0].t, endedAt: samples[samples.count - 1].t, samples: samples)
    }

    func togglePip() {
        if isPipActive {
            stopPip()
        } else {
            startPip()
        }
    }

    func startPip() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            addLog("设备不支持画中画")
            return
        }
        guard connectionState == .connected else {
            addLog("请先连接手环")
            return
        }

        userRequestedStop = false
        addLog("正在准备画中画载体视频...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let url = self.renderer.generateBlackVideo() else {
                DispatchQueue.main.async {
                    self.addLog("载体视频生成失败")
                }
                return
            }
            DispatchQueue.main.async {
                self.setupPipPlayer(videoURL: url)
            }
        }
    }

    func stopPip() {
        userRequestedStop = true
        teardownPip(log: true)
    }

    private func teardownPip(log: Bool) {
        isPipActive = false
        pipController?.delegate = nil
        pipController?.stopPictureInPicture()
        pipController = nil
        pipLooper = nil
        pipPlayer?.pause()
        pipPlayer = nil
        pipPlayerLayer?.removeFromSuperlayer()
        pipPlayerLayer = nil
        pipCarrierView?.removeFromSuperview()
        pipCarrierView = nil
        removeOverlay()
        if log {
            restoreAudioSession()
            addLog("画中画已关闭")
        }
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            addLog("Audio Session 已配置为 Playback 模式")
        } catch {
            addLog("Audio Session 配置失败: \(error.localizedDescription)")
        }
    }

    private func restoreAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // ignore
        }
    }

    private func setupPipPlayer(videoURL: URL) {
        guard let keyWindow = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? UIApplication.shared.windows.first else {
            addLog("无法获取窗口")
            return
        }

        configureAudioSession()
        addLog("PiP 载体就绪，启动播放器...")

        let item = AVPlayerItem(url: videoURL)
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false

        let looper = AVPlayerLooper(player: player, templateItem: item)

        let layer = AVPlayerLayer(player: player)
        layer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        layer.videoGravity = .resizeAspect

        let carrier = UIView(frame: CGRect(x: -10, y: -10, width: 1, height: 1))
        carrier.alpha = 0.01
        carrier.layer.addSublayer(layer)
        keyWindow.addSubview(carrier)

        let controller = AVPictureInPictureController(playerLayer: layer)
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        controller?.delegate = self
        // 隐藏画中画系统控制按钮（播放/快进/进度条），参考 CaiWanFeng/PiP
        controller?.setValue(1, forKey: "controlsStyle")

        pipPlayer = player
        pipPlayerLayer = layer
        pipLooper = looper
        pipController = controller

        player.play()

        var checks = 0
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self, let ctrl = self.pipController else {
                timer.invalidate()
                return
            }
            checks += 1
            if ctrl.isPictureInPicturePossible && !self.isPipActive && !self.userRequestedStop {
                timer.invalidate()
                self.addLog("PiP 就绪，启动中...")
                ctrl.startPictureInPicture()
            } else if checks >= 20 {
                timer.invalidate()
                self.addLog("PiP 启动超时 (possible=\(ctrl.isPictureInPicturePossible))")
                self.teardownPip(log: false)
            }
        }
    }

    // MARK: - 画中画窗口叠加 UI（核心：任意自定义视图渲染到画中画窗口上）

    private func attachOverlayToPipWindow(mainWindow: UIWindow?) {
        removeOverlay()

        // 画中画启动后系统会创建一个新 window，选它而不是主 window
        let windows = UIApplication.shared.windows
        let pipWindow = windows.first { $0 !== mainWindow && !$0.isKeyWindow }
            ?? windows.first { $0 !== mainWindow }
            ?? windows.first

        guard let target = pipWindow else {
            addLog("未找到画中画窗口")
            return
        }

        let overlay = HeartRatePipView()
        overlay.apply(settings: settings)
        overlay.update(heartRate: heartRate)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        target.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: target.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: target.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: target.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: target.trailingAnchor)
        ])
        pipOverlay = overlay
        addLog("悬浮窗 UI 已叠加到画中画窗口 ✓")
    }

    private func removeOverlay() {
        pipOverlay?.removeFromSuperview()
        pipOverlay = nil
    }

    // MARK: - 日志

    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logMessages.append("[\(timestamp)] \(message)")
        if logMessages.count > 200 {
            logMessages.removeFirst()
        }
    }

    // MARK: - 推送服务（HTTP / WebSocket）

    func startHttpServer(port: Int) {
        if httpServer.startServer(port: port) {
            addLog("HTTP服务已启动，端口: \(port)")
        } else {
            addLog("HTTP服务启动失败")
        }
    }

    func stopHttpServer() {
        httpServer.stopServer()
        addLog("HTTP服务已停止")
    }

    /// 按设置自启推送服务：上次开启过则随应用启动自动运行
    private func startConfiguredServers() {
        if settings.httpPushEnabled {
            startHttpServer(port: settings.httpPushPort)
        }
        if settings.wsPushEnabled {
            wsServer.startServer(port: settings.wsPushPort)
        }
    }

    /// 启动静默检查更新：发现新版本才 Toast 提示，其余情况（已是最新/网络失败）不打扰
    private func startUpdateCheck() {
        guard settings.checkUpdatesEnabled else { return }
        updateChecker.checkOnLaunch { [weak self] release in
            self?.showToast(
                "发现新版本 \(release.version)，详情见关于页",
                icon: "arrow.down.circle.fill",
                iconColor: Color(red: 0.46, green: 0.73, blue: 1.0)
            )
        }
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension HeartRateViewModel: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // 记录主 window（启动 PiP 前的 keyWindow），用于区分新的 PiP window
        let mainWindow = pipCarrierView?.window
        isPipActive = true
        addLog("画中画已启动 ✓")
        attachOverlayToPipWindow(mainWindow: mainWindow)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPipActive = false
        removeOverlay()
        addLog("画中画已停止")
        teardownPip(log: false)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        addLog("画中画启动失败: \(error.localizedDescription)")
        teardownPip(log: false)
    }
}

// MARK: - 心率悬浮窗视图（渲染到画中画窗口上的自定义 UI）

final class HeartRatePipView: UIView {

    private let cardView = UIView()
    private let numberLabel = UILabel()
    private let bpmLabel = UILabel()
    private var currentSettings: SettingsManager?
    private var currentHeartRate: Int = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        cardView.backgroundColor = .black
        cardView.clipsToBounds = true
        addSubview(cardView)

        numberLabel.textAlignment = .center
        numberLabel.lineBreakMode = .byClipping
        numberLabel.adjustsFontSizeToFitWidth = true
        numberLabel.minimumScaleFactor = 0.5
        numberLabel.text = "--"
        cardView.addSubview(numberLabel)

        bpmLabel.textAlignment = .center
        bpmLabel.lineBreakMode = .byClipping
        bpmLabel.adjustsFontSizeToFitWidth = true
        bpmLabel.minimumScaleFactor = 0.5
        bpmLabel.text = "BPM"
        cardView.addSubview(bpmLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(settings: SettingsManager) {
        currentSettings = settings
        let numberColor = UIColor(Color(hex: settings.bpmNumberColorHex))
        let labelColor = UIColor(Color(hex: settings.bpmLabelColorHex))
        numberLabel.textColor = numberColor
        bpmLabel.textColor = labelColor
        // 背景亮度：0 = 纯黑，100 = 纯白
        let brightness = max(0, min(100, settings.backgroundBrightness)) / 100.0
        cardView.backgroundColor = UIColor(white: CGFloat(brightness), alpha: 1)
        setNeedsLayout()
        layoutIfNeeded()
    }

    func update(heartRate: Int) {
        currentHeartRate = heartRate
        let newText = heartRate > 0 ? "\(heartRate)" : "--"
        guard newText != numberLabel.text else { return }
        // 与主页一致：BPM 变化时淡入淡出过渡
        UIView.transition(with: numberLabel, duration: 0.3, options: [.transitionCrossDissolve]) {
            self.numberLabel.text = newText
        }
        // 文本宽度变化后重新布局，避免被截断成省略号
        setNeedsLayout()
        UIView.animate(withDuration: 0.3) {
            self.layoutIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let s = currentSettings else { return }

        let boundsW = bounds.width
        let boundsH = bounds.height
        guard boundsW > 10, boundsH > 10 else { return }

        // 卡片铺满整个悬浮窗（PiP 窗口自带圆角裁剪，无需自己留边距）
        cardView.frame = bounds
        cardView.layer.cornerRadius = 0

        // 字体随窗口尺寸缩放（基准 240x160 下的 size*2.5 / size*2）；数字用主页同款圆体
        let scale = min(boundsW / 240.0, boundsH / 160.0)
        let numberBase = UIFont.systemFont(ofSize: CGFloat(s.bpmNumberSize) * 2.5 * scale, weight: .bold)
        numberLabel.font = numberBase.fontDescriptor.withDesign(.rounded).map {
            UIFont(descriptor: $0, size: numberBase.pointSize)
        } ?? numberBase
        bpmLabel.font = .systemFont(ofSize: CGFloat(s.bpmLabelSize) * 2.0 * scale, weight: .medium)

        let numberFont = numberLabel.font ?? .systemFont(ofSize: 14)
        let labelFont = bpmLabel.font ?? .systemFont(ofSize: 12)
        let numberSize = numberLabel.text?.size(withAttributes: [.font: numberFont]) ?? .zero
        let labelSize = bpmLabel.text?.size(withAttributes: [.font: labelFont]) ?? .zero
        let spacing: CGFloat = 8 * scale
        // 钳制在窗口宽度内，超出时 adjustsFontSizeToFitWidth 会自动缩小字号
        let maxTextWidth = boundsW - 16
        let numberW = min(numberSize.width + 4, maxTextWidth)
        let labelW = min(labelSize.width + 4, maxTextWidth)

        let cx = boundsW / 2
        let cy = boundsH / 2

        switch s.bpmPosition {
        case 0: // BPM 在数字上方
            numberLabel.frame = CGRect(x: cx - numberW / 2, y: cy - numberSize.height / 2, width: numberW, height: numberSize.height)
            bpmLabel.frame = CGRect(x: cx - labelW / 2, y: numberLabel.frame.minY - labelSize.height - spacing, width: labelW, height: labelSize.height)
        case 1: // BPM 在数字下方
            numberLabel.frame = CGRect(x: cx - numberW / 2, y: cy - numberSize.height / 2, width: numberW, height: numberSize.height)
            bpmLabel.frame = CGRect(x: cx - labelW / 2, y: numberLabel.frame.maxY + spacing, width: labelW, height: labelSize.height)
        case 2: // BPM 在数字左侧
            let totalW = numberW + spacing + labelW
            bpmLabel.frame = CGRect(x: cx - totalW / 2, y: cy - labelSize.height / 2, width: labelW, height: labelSize.height)
            numberLabel.frame = CGRect(x: bpmLabel.frame.maxX + spacing, y: cy - numberSize.height / 2, width: numberW, height: numberSize.height)
        case 3: // BPM 在数字右侧
            let totalW = numberW + spacing + labelW
            numberLabel.frame = CGRect(x: cx - totalW / 2, y: cy - numberSize.height / 2, width: numberW, height: numberSize.height)
            bpmLabel.frame = CGRect(x: numberLabel.frame.maxX + spacing, y: cy - labelSize.height / 2, width: labelW, height: labelSize.height)
        default:
            numberLabel.frame = CGRect(x: cx - numberW / 2, y: cy - numberSize.height / 2, width: numberW, height: numberSize.height)
            bpmLabel.frame = CGRect(x: cx - labelW / 2, y: numberLabel.frame.maxY + spacing, width: labelW, height: labelSize.height)
        }
    }
}

// MARK: - 心率记录会话（文件持久化）

struct HeartRateRecording: Identifiable, Codable {
    struct Sample: Codable {
        /// 采样时间
        let t: Date
        /// 心率值（BPM）
        let bpm: Int
    }

    var id = UUID()
    var startedAt: Date
    var endedAt: Date
    var samples: [Sample] = []
    /// 是否为外部导入的记录（列表中与自测记录分组展示）
    var imported: Bool = false

    init(startedAt: Date, endedAt: Date, samples: [Sample] = [], imported: Bool = false) {
        self.id = UUID()
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.samples = samples
        self.imported = imported
    }

    /// 兼容旧格式文件：imported 字段缺失时按自测记录处理
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        samples = try container.decodeIfPresent([Sample].self, forKey: .samples) ?? []
        imported = try container.decodeIfPresent(Bool.self, forKey: .imported) ?? false
    }

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    var durationText: String { Self.format(duration: duration) }
    var averageBpm: Double? {
        guard !samples.isEmpty else { return nil }
        return Double(samples.reduce(0) { $0 + $1.bpm }) / Double(samples.count)
    }
    var minBpm: Int? { samples.map(\.bpm).min() }
    var maxBpm: Int? { samples.map(\.bpm).max() }

    /// 时长格式化：不足 1 小时显示 分:秒，超过显示 时:分:秒
    static func format(duration: TimeInterval) -> String {
        let s = max(0, Int(duration))
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
        }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

enum HeartRateRecordingStore {
    static let iso8601 = ISO8601DateFormatter()

    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func loadAll() -> [HeartRateRecording] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // 排除未保存快照 unsaved.json：它是崩溃恢复依据，不是正式记录（丢弃后不应残留在列表里）
        let unsavedName = unsavedURL.lastPathComponent
        return files
            .filter { $0.pathExtension.lowercased() == "json" && $0.lastPathComponent != unsavedName }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(HeartRateRecording.self, from: data)
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    static func save(_ recording: HeartRateRecording) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(recording) else { return }
        let url = directory.appendingPathComponent("\(recording.id.uuidString).json")
        try? data.write(to: url, options: .atomic)
    }

    static func delete(_ recording: HeartRateRecording) {
        let url = directory.appendingPathComponent("\(recording.id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    /// 批量删除（按 id 删除对应文件）
    static func delete(_ ids: Set<UUID>) {
        for id in ids {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id.uuidString).json"))
        }
    }

    /// 未保存会话快照（应用异常退出后的恢复依据），与正式记录同目录，不会被清理缓存误删
    static var unsavedURL: URL {
        directory.appendingPathComponent("unsaved.json")
    }

    static func saveUnsaved(_ recording: HeartRateRecording) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(recording) else { return }
        try? data.write(to: unsavedURL, options: .atomic)
    }

    static func loadUnsaved() -> HeartRateRecording? {
        guard let data = try? Data(contentsOf: unsavedURL) else { return nil }
        return decode(data)
    }

    /// 按本应用 JSON 格式解码（ISO8601 日期，兼容缺少字段的旧文件）
    static func decode(_ data: Data) -> HeartRateRecording? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HeartRateRecording.self, from: data)
    }

    static func removeUnsaved() {
        try? FileManager.default.removeItem(at: unsavedURL)
    }
}
