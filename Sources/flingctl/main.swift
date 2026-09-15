// flingctl: sends its arguments to the running Fling over a Unix socket and prints the reply.
// All commands are parsed and run inside Fling (see Sources/Fling/CommandLine.swift); run `flingctl help`.
import Foundation

// Must match CommandServer.socketPath in the app.
let socketPath = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: "Library/Application Support/Fling/fling.sock").path

func connectToFling() -> Int32? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        buffer.copyBytes(from: socketPath.utf8.prefix(buffer.count - 1))
    }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    if connected == 0 { return fd }
    close(fd)
    return nil
}

var fd = connectToFling()
if fd == nil {
    // Not running: launch it and wait briefly for its socket.
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-g", "-b", "com.lucabv.Fling"]
    try? open.run()
    open.waitUntilExit()
    for _ in 0..<40 where fd == nil {
        usleep(250_000)
        fd = connectToFling()
    }
}
guard let fd else {
    FileHandle.standardError.write(Data("flingctl: couldn't reach Fling. Is it installed and allowed to run?\n".utf8))
    exit(2)
}

// The working directory lets Fling resolve relative paths (e.g. `flingctl config import ./fling.json`).
var request = try! JSONSerialization.data(withJSONObject: [
    "args": Array(CommandLine.arguments.dropFirst()),
    "cwd": FileManager.default.currentDirectoryPath,
])
request.append(UInt8(ascii: "\n"))
_ = request.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }

var reply = Data()
var buffer = [UInt8](repeating: 0, count: 65_536)
while case let count = read(fd, &buffer, buffer.count), count > 0 {
    reply.append(buffer, count: count)
}
close(fd)

guard let object = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
      let ok = object["ok"] as? Bool, let output = object["output"] as? String else {
    FileHandle.standardError.write(Data("flingctl: unexpected reply from Fling\n".utf8))
    exit(2)
}
if !output.isEmpty {
    (ok ? FileHandle.standardOutput : FileHandle.standardError).write(Data((output.hasSuffix("\n") ? output : output + "\n").utf8))
}
exit(ok ? 0 : 1)
