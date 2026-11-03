import Foundation

/// The sending side: what `notchhub emit` and `notchhub agent` use to reach a running app.
public enum Client {
    public enum Failure: Error { case notRunning, tooLong }

    /// Writes one JSON line to the app's socket. Throws `notRunning` when nobody is listening.
    public static func send(_ object: [String: Any], path: String = SocketServer.defaultPath) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        guard data.count <= Message.maxLine else { throw Failure.tooLong }
        data.append(0x0A)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { throw Failure.notRunning }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            path.withCString { _ = strlcpy(raw.baseAddress!.assumingMemoryBound(to: CChar.self), $0, capacity) }
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.notRunning }
        defer { close(fd) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw Failure.notRunning }
        let written = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
        guard written == data.count else { throw Failure.notRunning }
    }

    /// Turns `--key value` pairs into a message. `emit` defaults to a moment; `agent` sets the type.
    public static func object(type: String, arguments: [String]) -> [String: Any] {
        var result: [String: Any] = ["type": type]
        var index = 0
        while index + 1 < arguments.count {
            guard arguments[index].hasPrefix("--") else { index += 1; continue }
            let key = String(arguments[index].dropFirst(2)), value = arguments[index + 1]
            result[key] = ["ttl": Double(value), "priority": Int(value)][key] ?? nil ?? value
            index += 2
        }
        return result
    }
}
