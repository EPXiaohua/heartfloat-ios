import Foundation
import CoreBluetooth
import Combine

class BleService: NSObject, ObservableObject {
    static let shared = BleService()

    @Published var connectionState: ConnectionState = .disconnected
    @Published var currentHeartRate: Int = 0
    @Published var isContact: Bool = false
    @Published var logMessages: [String] = []

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
    private var lastNotificationAt: Date = .distantPast
    private var isManualStop = false
    /// 上次成功连接的设备（直连不依赖广播，避免断开后设备恢复广播慢导致扫不到）
    private var lastConnectedIdentifier: UUID?

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
        centralManager?.stopScan()
        if connectionState != .connected {
            if let peripheral = connectedPeripheral {
                peripheral.delegate = nil
                centralManager?.cancelPeripheralConnection(peripheral)
            }
            connectedPeripheral = nil
            heartRateCharacteristic = nil
            isManualStop = true
            connectionState = .disconnected
            addLog("已取消连接")
        }
    }

    func stopScan() {
        centralManager?.stopScan()
    }

    func disconnect() {
        isManualStop = true
        scanTimeoutWork?.cancel()
        watchdogWork?.cancel()
        if let peripheral = connectedPeripheral {
            peripheral.delegate = nil
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
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

    private var lastLoggedHeartRate: Int = -1
    private var lastLogTime: Date = .distantPast

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

            let now = Date()
            let timeSinceLastLog = now.timeIntervalSince(lastLogTime)
            let rateChanged = heartRate != lastLoggedHeartRate

            if rateChanged || timeSinceLastLog > 10 {
                let contactStatus = hasSensorContact ? "(已接触)" : "(未接触)"
                addLog("心率: \(heartRate) BPM \(contactStatus)")
                lastLoggedHeartRate = heartRate
                lastLogTime = now
            }
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
        addLog("GATT连接成功")
        connectionState = .connected
        directConnectTimeout?.cancel()
        directConnectTimeout = nil
        // 记住设备，下次连接直接直连（持久化，重启后依然有效）
        lastConnectedIdentifier = peripheral.identifier
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: "lastConnectedBLEPeripheral")
        // 启动数据看门狗：设备只停数据不断链路时（如设备端关闭广播）系统不会报断连
        lastNotificationAt = Date()
        startWatchdog()
        peripheral.discoverServices([heartRateServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        addLog("GATT连接断开")
        connectionState = .disconnected
        watchdogWork?.cancel()
        connectedPeripheral = nil
        heartRateCharacteristic = nil

        // 用户主动断开时不自动重连
        if isManualStop {
            isManualStop = false
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.connectionState == .disconnected {
                self?.addLog("尝试重新连接...")
                self?.startScan()
            }
        }
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
            return
        }

        guard let services = peripheral.services else { return }
        addLog("服务发现成功，共\(services.count)个服务")

        for service in services {
            addLog("服务: \(service.uuid.uuidString)")

            if service.uuid == heartRateServiceUUID {
                addLog("找到标准心率服务 (180d)")
                peripheral.discoverCharacteristics([heartRateMeasurementUUID], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            addLog("特征发现失败: \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            addLog("特征: \(characteristic.uuid.uuidString)")

            if characteristic.uuid == heartRateMeasurementUUID {
                addLog("找到心率测量特征 (2a37)")
                heartRateCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                peripheral.readValue(for: characteristic)
            }
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
            addLog("通知状态更新失败: \(error.localizedDescription)")
            return
        }

        if characteristic.isNotifying {
            addLog("通知已启用")
        } else {
            addLog("通知已关闭")
        }
    }
}
