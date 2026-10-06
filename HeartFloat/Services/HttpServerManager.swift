import Foundation
import Network

class HttpServerManager: ObservableObject {
    static let shared = HttpServerManager()

    @Published var isRunning: Bool = false
    @Published var currentPort: Int = 8080
    /// 本机所有可用 IPv4 地址（WiFi / 热点 / 蜂窝），按连接优先级排序
    @Published var localIPs: [String] = []

    private var listener: NWListener?
    private var currentHeartRate: Int = 0
    private var isContact: Bool = false
    private var lastUpdateTime: Date = Date()

    func updateHeartRate(_ heartRate: Int, contact: Bool = true) {
        currentHeartRate = heartRate
        isContact = contact
        lastUpdateTime = Date()
    }

    func getHeartRateData() -> HeartRateData {
        return HeartRateData(
            bpm: currentHeartRate,
            isContact: isContact,
            lastUpdate: lastUpdateTime.timeIntervalSince1970 * 1000
        )
    }

    func startServer(port: Int) -> Bool {
        if isRunning { return true }

        currentPort = port
        localIPs = getLocalIPAddresses()

        do {
            let parameters = NWParameters.tcp
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(port)))
        } catch {
            return false
        }

        listener?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isRunning = true
                case .failed, .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.start(queue: .global(qos: .userInitiated))
        isRunning = true
        return true
    }

    func stopServer() {
        listener?.cancel()
        listener = nil
        isRunning = false
        localIPs = []
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                connection.cancel()
                return
            }

            guard let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let lines = request.split(separator: "\r\n")
            guard let firstLine = lines.first else {
                connection.cancel()
                return
            }

            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2 else {
                connection.cancel()
                return
            }

            let path = String(parts[1])
            let response = self.createResponse(for: path)

            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func createResponse(for path: String) -> Data {
        switch path {
        case "/heartbeat":
            return createTextResponse("\(currentHeartRate)")
        case "/heartbeat.json":
            let data = getHeartRateData()
            let json: [String: Any] = [
                "bpm": data.bpm,
                "isContact": data.isContact,
                "lastUpdate": data.lastUpdate,
                "timestamp": Date().timeIntervalSince1970 * 1000
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: json),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return createJSONResponse(jsonString)
            }
            return createErrorResponse()
        case "/live":
            // 直播页注入 WebSocket 端口（页面优先走 WS 实时推送，断线回退轮询）
            let html = loadHTMLPage("live")
                .replacingOccurrences(of: "__WS_PORT__", with: "\(WsServerManager.shared.currentPort)")
            return createHTMLResponse(html)
        case "/":
            return createHTMLResponse(loadHTMLPage("index"))
        default:
            return createErrorResponse()
        }
    }

    /// 从 Bundle 读取打包的网页资源（Resources/index.html、Resources/live.html）
    private func loadHTMLPage(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else {
            return "<!DOCTYPE html><html><head><meta charset=\"UTF-8\"></head><body>页面资源缺失</body></html>"
        }
        return html
    }

    private func createTextResponse(_ content: String) -> Data {
        let body = content.data(using: .utf8) ?? Data()
        var response = "HTTP/1.1 200 OK\r\n"
        response += "Content-Type: text/plain\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n"
        response += "\r\n"
        return (response.data(using: .utf8) ?? Data()) + body
    }

    private func createJSONResponse(_ content: String) -> Data {
        let body = content.data(using: .utf8) ?? Data()
        var response = "HTTP/1.1 200 OK\r\n"
        response += "Content-Type: application/json\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n"
        response += "\r\n"
        return (response.data(using: .utf8) ?? Data()) + body
    }

    private func createHTMLResponse(_ content: String) -> Data {
        let body = content.data(using: .utf8) ?? Data()
        var response = "HTTP/1.1 200 OK\r\n"
        response += "Content-Type: text/html\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n"
        response += "\r\n"
        return (response.data(using: .utf8) ?? Data()) + body
    }

    private func createErrorResponse() -> Data {
        let body = "Not Found".data(using: .utf8) ?? Data()
        var response = "HTTP/1.1 404 Not Found\r\n"
        response += "Content-Type: text/plain\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n"
        response += "\r\n"
        return (response.data(using: .utf8) ?? Data()) + body
    }

    /// 重新枚举本机地址（网络切换后由设置页触发刷新）
    func refreshIPs() {
        localIPs = getLocalIPAddresses()
    }

    /// 枚举本机所有 IPv4 地址：WiFi(enX)、个人热点(bridgeX)、蜂窝(pdp_ipX)，WiFi 优先
    private func getLocalIPAddresses() -> [String] {
        var entries: [(name: String, ip: String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return []
        }

        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            guard interface.ifa_addr != nil,
                  interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") || name.hasPrefix("pdp_ip") else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
            let ip = String(cString: hostname)
            if !ip.isEmpty {
                entries.append((name, ip))
            }
        }

        // WiFi 优先，其次热点，最后蜂窝；同优先级按接口名排序，最后去重
        func rank(_ name: String) -> Int {
            if name.hasPrefix("en") { return 0 }
            if name.hasPrefix("bridge") { return 1 }
            return 2
        }
        let sorted = entries.sorted {
            let r0 = rank($0.name), r1 = rank($1.name)
            if r0 != r1 { return r0 < r1 }
            return $0.name < $1.name
        }

        var seen = Set<String>()
        var result: [String] = []
        for entry in sorted where !seen.contains(entry.ip) {
            seen.insert(entry.ip)
            result.append(entry.ip)
        }
        return result
    }

    struct HeartRateData {
        let bpm: Int
        let isContact: Bool
        let lastUpdate: Double
    }
}

// MARK: - WebSocket 实时推送服务器

/// 基于 Network.framework 的 WebSocket 服务器：
/// 客户端连接后立即推送一次当前状态，之后每次心率采样广播一条 JSON
class WsServerManager: ObservableObject {
    static let shared = WsServerManager()

    @Published var isRunning: Bool = false
    @Published var currentPort: Int = 8081
    @Published var clientCount: Int = 0

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var lastHeartRate: Int = 0
    private var lastContact: Bool = false
    private let queue = DispatchQueue(label: "heartfloat.ws.server", qos: .userInitiated)

    func updateHeartRate(_ heartRate: Int, contact: Bool = true) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.lastHeartRate = heartRate
            self.lastContact = contact
            self.broadcastCurrent()
        }
    }

    func startServer(port: Int) {
        guard listener == nil else { return }
        currentPort = port

        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(port)))
        } catch {
            isRunning = false
            return
        }

        let newListener = listener
        newListener?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.isRunning = true
                case .failed, .cancelled:
                    self.isRunning = false
                    // 端口占用等失败场景清掉监听器，允许重新启动
                    if self.listener === newListener {
                        self.listener = nil
                    }
                default:
                    break
                }
            }
        }

        newListener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        newListener?.start(queue: queue)
    }

    func stopServer() {
        listener?.cancel()
        listener = nil
        isRunning = false
        queue.async { [weak self] in
            guard let self = self else { return }
            self.connections.forEach { $0.cancel() }
            self.connections.removeAll()
            DispatchQueue.main.async { self.clientCount = 0 }
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connections.append(connection)
        DispatchQueue.main.async { self.clientCount = self.connections.count }
        receiveNext(connection)
        // 新客户端立即同步一次当前状态
        broadcastCurrent()
    }

    private func receiveNext(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] _, _, _, error in
            if error == nil {
                // 客户端消息无需处理，继续等待（Ping 由 autoReplyPing 自动回复）
                self?.receiveNext(connection)
            } else {
                self?.dropConnection(connection)
            }
        }
    }

    private func broadcastCurrent() {
        let json: [String: Any] = [
            "bpm": lastHeartRate,
            "isContact": lastContact,
            "lastUpdate": Date().timeIntervalSince1970 * 1000
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "heartbeat", metadata: [metadata])

        for connection in connections {
            connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { [weak self] error in
                if error != nil {
                    self?.dropConnection(connection)
                }
            })
        }
    }

    private func dropConnection(_ connection: NWConnection) {
        queue.async { [weak self] in
            guard let self = self else { return }
            connection.cancel()
            self.connections.removeAll { $0 === connection }
            DispatchQueue.main.async { self.clientCount = self.connections.count }
        }
    }
}
