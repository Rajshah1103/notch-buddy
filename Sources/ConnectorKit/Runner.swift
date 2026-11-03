import Foundation
import Security

/// Runs a connector's script and reads its items. The script gets its own folder as the working directory
/// and, if the manifest names one, its secret in an environment variable. Nothing else of yours is passed on.
public enum Runner {
    public enum Failure: Error, Equatable { case notFound, timedOut, badOutput, failed(Int32) }

    public static let timeout: TimeInterval = 20
    public static let maxOutput = 256 * 1024

    public static func run(_ manifest: Manifest, in folder: URL, secret: String?) async throws -> [Item] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do { continuation.resume(returning: try runSync(manifest, in: folder, secret: secret)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    static func runSync(_ manifest: Manifest, in folder: URL, secret: String?) throws -> [Item] {
        var words = manifest.run
        let process = Process()
        if words[0].hasPrefix("./") {
            let program = folder.appendingPathComponent(String(words[0].dropFirst(2)))
            guard FileManager.default.isExecutableFile(atPath: program.path) else { throw Failure.notFound }
            process.executableURL = program
            words.removeFirst()
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        }
        process.arguments = words
        process.currentDirectoryURL = folder
        var environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8"]
        if let name = manifest.secret, let secret { environment[name] = secret }
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { throw Failure.notFound }

        var data = Data()
        let reader = DispatchGroup()
        reader.enter()
        DispatchQueue.global().async {
            while true {
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                if data.count < maxOutput { data.append(chunk) }
            }
            reader.leave()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); throw Failure.timedOut }
        reader.wait()
        guard process.terminationStatus == 0 else { throw Failure.failed(process.terminationStatus) }
        guard data.count <= maxOutput, let items = Item.parse(data) else { throw Failure.badOutput }
        return items
    }
}

/// A connector's secret in the login Keychain, one item per connector.
public enum ConnectorSecret {
    private static func service(_ id: String) -> String { "dev.notchhub.connector.\(id)" }

    public static func save(_ value: String, for id: String) {
        clear(id)
        SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: service(id), kSecAttrAccount: "secret",
                    kSecValueData: Data(value.utf8)] as CFDictionary, nil)
    }

    public static func read(_ id: String) -> String? {
        var result: CFTypeRef?
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service(id), kSecAttrAccount: "secret",
                     kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary
        guard SecItemCopyMatching(query, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func clear(_ id: String) {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service(id), kSecAttrAccount: "secret"] as CFDictionary)
    }
}
