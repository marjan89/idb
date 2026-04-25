import Foundation

/// Binary TCP client for FBFastTouchServer (port 9200)
/// 21-byte messages, ~5ms round-trip
class FastTouchClient {
    private var fd: Int32 = -1
    private(set) var connected = false

    func connect(host: String, port: UInt16) -> Bool {
        fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }

        var flag: Int32 = 1
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &flag, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, host, &addr.sin_addr)

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        connected = result == 0
        if !connected { close(fd); fd = -1 }
        return connected
    }

    func disconnect() {
        if fd >= 0 { close(fd); fd = -1; connected = false }
    }

    private func pack(_ cmd: UInt8, _ x: Float, _ y: Float, _ x2: Float, _ y2: Float, _ dur: Float) -> Data {
        var data = Data(capacity: 21)
        data.append(cmd)
        withUnsafeBytes(of: x.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: y.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: x2.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: y2.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: dur.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        return data
    }

    private func send(_ data: Data) -> UInt8 {
        data.withUnsafeBytes { buf in
            Darwin.send(fd, buf.baseAddress!, buf.count, 0)
        }
        var resp: UInt8 = 0xFF
        recv(fd, &resp, 1, 0)
        return resp
    }

    func tap(_ x: Float, _ y: Float) -> Bool {
        send(pack(0x01, x, y, 0, 0, 0)) == 0
    }

    func swipe(fromX: Float, fromY: Float, toX: Float, toY: Float, duration: Float = 0.01) -> Bool {
        send(pack(0x02, fromX, fromY, toX, toY, duration)) == 0
    }
}
