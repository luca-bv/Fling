import Foundation

/// Serves `flingctl`: a Unix socket (owner-only) that takes one `{"args": [String], "cwd": String}` request per
/// connection and answers `{"ok": Bool, "output": String}`.
@MainActor
final class CommandServer {
    static let socketPath: String = {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Fling/fling.sock").path
        return smokeTesting ? path + ".smoke" : path
    }()

    private let handler: (_ args: [String], _ cwd: String) -> (ok: Bool, output: String)
    private var listener: Int32 = -1
    private var source: DispatchSourceRead?

    init(handler: @escaping (_ args: [String], _ cwd: String) -> (ok: Bool, output: String)) {
        self.handler = handler
        start()
    }

    private func start() {
        try? FileManager.default.createDirectory(atPath: (Self.socketPath as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        unlink(Self.socketPath) // a stale socket from a previous run
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: Self.socketPath.utf8.prefix(buffer.count - 1))
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard listener >= 0, bound == 0, chmod(Self.socketPath, 0o600) == 0, listen(listener, 8) == 0 else {
            return NSLog("Fling: couldn't open the flingctl socket at \(Self.socketPath) (errno \(errno))")
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.acceptClient() }
        }
        source.resume()
        self.source = source
    }

    private func acceptClient() {
        let client = accept(listener, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }
        // flingctl writes its request right away; don't let a stuck client block Fling.
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var request = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !request.contains(UInt8(ascii: "\n")), case let count = read(client, &buffer, buffer.count), count > 0 {
            request.append(buffer, count: count)
        }
        let reply: (ok: Bool, output: String)
        if let object = try? JSONSerialization.jsonObject(with: request) as? [String: Any], let args = object["args"] as? [String] {
            reply = handler(args, object["cwd"] as? String ?? NSHomeDirectory())
        } else {
            reply = (false, "Couldn't read the request.")
        }
        guard var data = try? JSONSerialization.data(withJSONObject: ["ok": reply.ok, "output": reply.output]) else { return }
        data.append(UInt8(ascii: "\n"))
        _ = data.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
    }
}
