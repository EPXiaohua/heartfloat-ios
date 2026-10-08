import Foundation
import CoreBluetooth
import Combine

class BleService: NSObject, ObservableObject {
    static let shared = BleService()

    @Published var connectionState: ConnectionState = .disconnected
    @Published var currentHeartRate: Int = 0
    @Published var isContact: Bool = false
    @Published var logMessages: [String] = []
    /// 当前连接的设备名（断开后清空）
    @Published var connectedDeviceName: String = ""

    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case failed
    }

    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var heartRateCharacteristic: CBCharacteristic?
    private var scanTimeoutWork: DispatchWorkItem?
    private var directConnectTimeout: DispatchWorkItem?
    private var watchdogWork: DispatchWorkItem?
    private var gattTimeoutWork: DispatchWorkItem?
    private var lastNotificationAt: Date = .distantPast
    private var isSkippingDevice = false
    /// 上次成功连接的设备（直连不依赖广播，避免断开后设备恢复广播慢导致扫不到）
    @Published var lastConnectedIdentifier: UUID?
    /// 绑定设备的展示信息（蓝牙设备页用）
    @Published var lastConnectedName: String = UserDefaults.standard.string(forKey: "lastConnectedBLEName") ?? ""
    @Published var lastConnectedAt: Date? = {
        let time = UserDefaults.standard.double(forKey: "lastConnectedBLEAt")
        return time > 0 ? Date(timeIntervalSinceReferenceDate: time) : nil
    }()

    private let heartRateServiceUUID = CBUUID(string: "180D")
    private let heartRateMeasurementUUID = CBUUID(string: "2A37")

    private let targetDeviceNames = [
        "Mi Smart Band 9 Pro",
        "Mi Smart Band 9",
        "Mi Band 9 Pro",
        "Mi Band 9",
        "Band 9 Pro",
        "Band 9",
        "Mi Smart Band",
        "Mi Band",
        "Xiaomi Smart Band"
    ]

    private var discoveredDevices: [CBPeripheral] = []

    override init() {
        super.init()
        if let saved = UserDefaults.standard.string(forKey: "lastConnectedBLEPeripheral") {
            lastConnectedIdentifier = UUID(uuidString: saved)
        }
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        // 每次发起连接只展示本次日志
        logMessages.removeAll()

        guard let central = centralManager, central.state == .poweredOn else {
            addLog("蓝牙未开启或不可用")
            connectionState = .failed
            return
        }

        discoveredDevices.removeAll()

        // 优先直连上次成功连接的设备：设备断开后恢复广播可能很慢，
        // 靠扫描等广播包可能一直收不到；直连不依赖广播，只要设备在范围内即可建立链路
        if let identifier = lastConnectedIdentifier,
           let peripheral = central.retrievePeripherals(withIdentifiers: [identifier]).first {
            connectionState = .connecting
            addLog("正在直连上次设备...")
            connectedPeripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)

            directConnectTimeout?.cancel()
            let timeout = DispatchWorkItem { [weak self] in
                guard let self = self, self.connectionState == .connecting else { return }
                self.addLog("直连未响应，改为扫描附近设备...")
                // 取消挂起的直连尝试并放弃引用（didFailToConnect 回调到达时按已放弃处理）
                self.connectedPeripheral = nil
                self.centralManager?.cancelPeripheralConnection(peripheral)
                self.beginScan()
            }
            directConnectTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
            return
        }

        beginScan()
    }

    private func beginScan() {
        guard let central = centralManager else { return }
        connectionState = .connecting
        addLog("开始扫描BLE设备...")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])

        scanTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.connectionState == .connecting else { return }
            // 已进入设备识别阶段（GATT 已连上），由识别超时接管
            if self.connectedPeripheral != nil { return }
            self.centralManager?.stopScan()
            self.connectionState = .failed
            self.addLog("扫描超时，未找到手环")
        }
        scanTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
    }

    /// 数据看门狗：心率通知是 1Hz，连接状态下长时间收不到任何通知，
    /// 说明设备已失效（关机/超出范围/设备端停止推送），主动断开并置为未连接
    private func startWatchdog() {
        watchdogWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.connectionState == .connected else { return }
            if Date().timeIntervalSince(self.lastNotificationAt) > 15 {
                self.addLog("超过 15 秒未收到设备数据，已自动断开")
                self.disconnect()
                return
            }
            self.startWatchdog()
        }
        watchdogWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    /// 取消连接流程（扫描中或连接中），不产生自动重连
    func cancelScan() {
        scanTimeoutWork?.cancel()
        directConnectTimeout?.cancel()
        gattTimeoutWork?.cancel()
        centralManager?.stopScan()
        if connectionState != .connected {
            if let peripheral = connectedPeripheral {
                peripheral.delegate = nil
                centralManager?.cancelPeripheralConnection(peripheral)
            }
            connectedPeripheral = nil
            connectedDeviceName = ""
            heartRateCharacteristic = nil
            connectionState = .disconnected
            addLog("已取消连接")
        }
    }

    func stopScan() {
        centralManager?.stopScan()
    }

    /// 解绑上次连接的设备：清除本地记住的设备信息，下次连接恢复为扫描搜索
    func unbindLastDevice() {
        lastConnectedIdentifier = nil
        lastConnectedName = ""
        lastConnectedAt = nil
        UserDefaults.standard.removeObject(forKey: "lastConnectedBLEPeripheral")
        UserDefaults.standard.removeObject(forKey: "lastConnectedBLEName")
        UserDefaults.standard.removeObject(forKey: "lastConnectedBLEAt")
        addLog("已解绑设备，下次连接将重新搜索")
    }

    func disconnect() {
        scanTimeoutWork?.cancel()
        watchdogWork?.cancel()
        gattTimeoutWork?.cancel()
        if let peripheral = connectedPeripheral {
            peripheral.delegate = nil
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        connectedDeviceName = ""
        heartRateCharacteristic = nil
        connectionState = .disconnected
        addLog("已断开连接")
    }

    private func connect(to peripheral: CBPeripheral) {
        stopScan()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting
        addLog("连接设备: \(peripheral.name ?? "未知设备")")
        centralManager?.connect(peripheral, options: nil)
    }

    private func addLog(_ message: String) {
        DispatchQueue.main.async {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            self.logMessages.append("[\(timestamp)] \(message)")
            if self.logMessages.count > 200 {
                self.logMessages.removeFirst()
            }
        }
    }

    private func parseHeartRateData(_ data: Data) {
        guard data.count >= 2 else { return }

        let bytes = [UInt8](data)
        let flags = bytes[0]
        let is16Bit = (flags & 0x01) != 0
        let hasSensorContact = (flags & 0x02) != 0

        var heartRate: Int
        if is16Bit && bytes.count >= 3 {
            heartRate = Int(bytes[2]) << 8 | Int(bytes[1])
        } else if bytes.count >= 2 {
            heartRate = Int(bytes[1])
        } else {
            return
        }

        if heartRate >= 30 && heartRate <= 220 {
            currentHeartRate = heartRate
            isContact = hasSensorContact
        }
    }
}

extension BleService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            addLog("蓝牙已开启")
        case .poweredOff:
            addLog("蓝牙已关闭")
            connectionState = .disconnected
        case .resetting:
            addLog("蓝牙重置中")
        case .unauthorized:
            addLog("蓝牙未授权")
        case .unsupported:
            addLog("设备不支持蓝牙LE")
        case .unknown:
            addLog("蓝牙状态未知")
        @unknown default:
            addLog("蓝牙状态未知")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceName = peripheral.name ?? ""

        if deviceName.isEmpty == false {
            addLog("发现设备: \(deviceName)")
        }

        for targetName in targetDeviceNames {
            if deviceName.contains(targetName) {
                addLog("找到目标设备: \(deviceName)")
                connect(to: peripheral)
                return
            }
        }

        if discoveredDevices.contains(peripheral) == false {
            discoveredDevices.append(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        addLog("GATT链路已建立，识别心率服务中...")
        // 保持 connecting：发现心率服务/特征并成功开启通知后，才算真正连接成功
        isSkippingDevice = false
        directConnectTimeout?.cancel()
        directConnectTimeout = nil
        // 记住设备，下次连接直接直连（持久化，重启后依然有效）
        lastConnectedIdentifier = peripheral.identifier
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: "lastConnectedBLEPeripheral")
        if let name = peripheral.name, !name.isEmpty {
            lastConnectedName = name
            UserDefaults.standard.set(name, forKey: "lastConnectedBLEName")
        }
        lastConnectedAt = Date()
        UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: "lastConnectedBLEAt")

        // 识别超时保护：服务/特征发现迟迟不完成则放弃该设备
        gattTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.connectionState == .connecting else { return }
            self.addLog("心率服务识别超时，断开该设备")
            self.abandonCurrentPeripheral()
        }
        gattTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)

        peripheral.discoverServices([heartRateServiceUUID])
    }

    /// 放弃当前设备（没有心率服务/特征、识别超时等）：断开并继续扫描找其他设备
    private func abandonCurrentPeripheral() {
        gattTimeoutWork?.cancel()
        guard let peripheral = connectedPeripheral else { return }
        isSkippingDevice = true
        peripheral.delegate = nil
        connectedPeripheral = nil
        heartRateCharacteristic = nil
        centralManager?.cancelPeripheralConnection(peripheral)
        // connect 前扫描已停止，这里恢复扫描继续找
        if connectionState == .connecting, let central = centralManager, central.state == .poweredOn {
            addLog("继续扫描其他设备...")
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        watchdogWork?.cancel()
        gattTimeoutWork?.cancel()

        // 跳过无效设备（无心率服务/特征）时的主动断开：扫描已在 abandon 里恢复
        if isSkippingDevice {
            isSkippingDevice = false
            return
        }

        addLog("GATT连接断开")
        connectionState = .disconnected
        connectedPeripheral = nil
        connectedDeviceName = ""
        heartRateCharacteristic = nil
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // 直连超时后已主动放弃并转为扫描，晚到的失败回调按已放弃处理
        guard connectedPeripheral?.identifier == peripheral.identifier else { return }
        addLog("连接失败: \(error?.localizedDescription ?? "未知错误")")
        connectionState = .failed
    }
}

extension BleService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            addLog("服务发现失败: \(error.localizedDescription)")
            abandonCurrentPeripheral()
            return
        }

        if let hrService = peripheral.services?.first(where: { $0.uuid == heartRateServiceUUID }) {
            addLog("已找到心率服务 (180D)")
            peripheral.discoverCharacteristics([heartRateMeasurementUUID], for: hrService)
        } else {
            addLog("未发现心率服务，不是心率设备")
            abandonCurrentPeripheral()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            addLog("特征发现失败: \(error.localizedDescription)")
            abandonCurrentPeripheral()
            return
        }

        if let characteristic = service.characteristics?.first(where: { $0.uuid == heartRateMeasurementUUID }) {
            addLog("已找到心率特征 (2A37)，开启通知...")
            heartRateCharacteristic = characteristic
            // 只开通知即可：心率测量特征通常不允许读取（读会报 Reading is not permitted），数据由通知推送
            peripheral.setNotifyValue(true, for: characteristic)
        } else {
            addLog("未发现心率特征，不是心率设备")
            abandonCurrentPeripheral()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // 收到任何通知都刷新数据存活时间（看门狗依据）
        lastNotificationAt = Date()

        if let error = error {
            addLog("读取特征值失败: \(error.localizedDescription)")
            return
        }

        guard let data = characteristic.value else { return }

        if characteristic.uuid == heartRateMeasurementUUID {
            parseHeartRateData(data)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            addLog("开启心率通知失败: \(error.localizedDescription)")
            abandonCurrentPeripheral()
            return
        }

        guard characteristic.uuid == heartRateMeasurementUUID, characteristic.isNotifying else { return }
        // 心率通知就绪才算真正连接成功
        addLog("心率通知已就绪，连接成功 ✓")
        gattTimeoutWork?.cancel()
        connectionState = .connected
        connectedDeviceName = connectedPeripheral?.name ?? "未知设备"
        // 启动数据看门狗：设备只停数据不断链路时（如设备端关闭广播）系统不会报断连
        lastNotificationAt = Date()
        startWatchdog()
    }
}
