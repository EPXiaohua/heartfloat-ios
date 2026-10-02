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
    /// 最近 60 秒心率曲线（固定长度，供 Canvas 逐帧绘制）
    @Published var heartRateHistory: [Double] = Array(repeating: 0, count: 60)
    /// 上一次采样前的历史快照（供形变动画插值：旧形态 → 新形态）
    var previousHistory: [Double] = Array(repeating: 0, count: 60)
    /// 最近一次心率采样时间（供形变动画进度插值）
    var lastSampleAt: Date = .distantPast

    private let bleService = BleService.shared
    private let httpServer = HttpServerManager.shared
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

    override init() {
        super.init()
        setupBindings()
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
                // 曲线历史每秒都推进，并保存旧快照供形变动画（旧形态 → 新形态平滑过渡）
                self.previousHistory = self.heartRateHistory
                self.heartRateHistory.removeFirst()
                self.heartRateHistory.append(Double(rate))
                self.lastSampleAt = Date()
                // 数字大字 / 画中画仅在值变化时刷新，避免无效重绘
                guard rate != self.heartRate else { return }
                self.heartRate = rate
                self.pipOverlay?.update(heartRate: rate)
            }
            .store(in: &cancellables)

        bleService.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.connectionState = state
                // 连接成功后展示勾动画片刻再自动关闭弹窗
                if state == .connected {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                        self?.showConnectionOverlay = false
                    }
                }
            }
            .store(in: &cancellables)

        bleService.$isContact
            .receive(on: DispatchQueue.main)
            .assign(to: &$isContact)

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
        bleService.disconnect()
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
        addLog("悬浮窗 UI 已叠加到画中画窗口 ✅")
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

    // MARK: - HTTP 服务

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
}

// MARK: - AVPictureInPictureControllerDelegate

extension HeartRateViewModel: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // 记录主 window（启动 PiP 前的 keyWindow），用于区分新的 PiP window
        let mainWindow = pipCarrierView?.window
        isPipActive = true
        addLog("画中画已启动 ✅")
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
        numberLabel.text = heartRate > 0 ? "\(heartRate)" : "--"
        // 文本宽度变化后重新布局，避免被截断成省略号
        setNeedsLayout()
        layoutIfNeeded()
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

        // 字体随窗口尺寸缩放（基准 240x160 下的 size*2.5 / size*2）
        let scale = min(boundsW / 240.0, boundsH / 160.0)
        numberLabel.font = .systemFont(ofSize: CGFloat(s.bpmNumberSize) * 2.5 * scale, weight: .bold)
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
