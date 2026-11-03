import Foundation

/// Listens on a Unix domain socket that only the current user can open and hands each parsed message to
/// `onMessage` on the main queue. No network port; event driven, so it costs nothing while nobody is connected.
public final class SocketServer: @unchecked Sendable {
    public static var defaultPath: String {
        if let custom = ProcessInfo.processInfo.environment["NOTCHHUB_SOCKET"], !custom.isEmpty { return custom }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NotchHub/notchhub.sock").path
    }

    public let path: String
    private let onMessage: @Sendable (Message) -> Void
    private let queue = DispatchQueue(label: "notchhub.socket")
    private var listener: DispatchSourceRead?
    private var rate = RateLimit()
    private var descriptor: Int32 = -1

    public init(path: String = SocketServer.defaultPath, onMessage: @escaping @Sendable (Message) -> Void) {
        self.path = path
        self.onMessage = onMessage
    }

    @discardableResult
    public func start() -> Bool {
        guard listener == nil else { return true }
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        unlink(path)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { return false }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            path.withCString { _ = strlcpy(raw.baseAddress!.assumingMemoryBound(to: CChar.self), $0, capacity) }
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 8) == 0 else { close(fd); return false }
        chmod(path, 0o600)
        descriptor = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.accept() }
        source.setCancelHandler { close(fd) }
        source.resume()
        listener = source
        return true
    }

    public func stop() {
        listener?.cancel(); listener = nil
        unlink(path)
    }

    private func accept() {
        let client = Darwin.accept(descriptor, nil, nil)
        guard client >= 0 else { return }
        let reader = DispatchSource.makeReadSource(fileDescriptor: client, queue: queue)
        var lines = LineBuffer()
        reader.setEventHandler { [weak self] in
            var chunk = [UInt8](repeating: 0, count: 4096)
            let count = read(client, &chunk, chunk.count)
            if count <= 0 { reader.cancel(); return }
            for line in lines.feed(Data(chunk[0..<count])) {
                guard let self, self.rate.allow(now: ProcessInfo.processInfo.systemUptime), let message = try? Message.parse(line) else { continue }
                let deliver = self.onMessage
                DispatchQueue.main.async { deliver(message) }
            }
        }
        reader.setCancelHandler { close(client) }
        reader.resume()
    }
}
