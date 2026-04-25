import AppKit
import Foundation

/// Reads JPEG frames from WDA's MJPEG server
class MJPEGStream: NSObject, URLSessionDataDelegate {
    let url: URL
    private var buffer = Data()
    private var urlSession: URLSession?
    private(set) var latestImage: NSImage?
    private(set) var imagePixelSize: NSSize?
    var onFrame: ((NSImage) -> Void)?
    private var frameCount = 0
    private var lastFPSTime = Date()

    init(url: URL) {
        self.url = url
    }

    func start() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        urlSession?.dataTask(with: url).resume()
    }

    func stop() {
        urlSession?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        extractFrames()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as? NSError, error.code == -999 { return }
        buffer.removeAll()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.start()
        }
    }

    private func extractFrames() {
        while true {
            guard let startRange = buffer.range(of: Data([0xFF, 0xD8])),
                  let endRange = buffer.range(of: Data([0xFF, 0xD9]),
                                               in: startRange.lowerBound..<buffer.endIndex)
            else { break }

            let jpegData = buffer[startRange.lowerBound..<endRange.upperBound]
            buffer.removeSubrange(buffer.startIndex..<endRange.upperBound)

            if let image = NSImage(data: Data(jpegData)) {
                if imagePixelSize == nil, let rep = image.representations.first {
                    imagePixelSize = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
                }
                latestImage = image
                onFrame?(image)

                frameCount += 1
                let now = Date()
                if now.timeIntervalSince(lastFPSTime) >= 5.0 {
                    let fps = Double(frameCount) / now.timeIntervalSince(lastFPSTime)
                    fputs("[mirror] \(String(format: "%.0f", fps)) FPS\n", stderr)
                    frameCount = 0
                    lastFPSTime = now
                }
            }
        }
    }
}
