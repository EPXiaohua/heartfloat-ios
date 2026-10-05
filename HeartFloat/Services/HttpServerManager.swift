import Foundation
import Network

class HttpServerManager: ObservableObject {
    static let shared = HttpServerManager()

    @Published var isRunning: Bool = false
    @Published var currentPort: Int = 8080
    @Published var localIP: String?

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
        localIP = getLocalIPAddress()

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
        localIP = nil
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
            return createHTMLResponse(loadHTMLPage("live"))
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

    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }

        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }

        return address
    }

    struct HeartRateData {
        let bpm: Int
        let isContact: Bool
        let lastUpdate: Double
    }
}
