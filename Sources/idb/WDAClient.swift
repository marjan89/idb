import Foundation

/// HTTP client for WDA API
class WDAClient {
    let baseURL: String
    var sessionID: String?

    init(baseURL: String) {
        self.baseURL = baseURL
    }

    private func json(_ data: Data) throws -> [String: Any] {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IDBError.commandFailed("Invalid JSON response")
        }
        return obj
    }

    private func value(_ data: Data) throws -> [String: Any] {
        let j = try json(data)
        guard let v = j["value"] as? [String: Any] else {
            throw IDBError.commandFailed("Missing 'value' in response")
        }
        return v
    }

    func status() throws -> [String: Any] {
        try value(syncGET("/status"))
    }

    func createSession() throws -> String {
        let body: [String: Any] = ["capabilities": ["alwaysMatch": ["platformName": "iOS"]]]
        let data = try syncPOST("/session", json: body)
        let v = try value(data)
        guard let sid = v["sessionId"] as? String else {
            throw IDBError.commandFailed("No sessionId in response")
        }
        sessionID = sid
        return sid
    }

    func windowSize() throws -> (width: Double, height: Double) {
        guard let sid = sessionID else { throw IDBError.commandFailed("No session") }
        let v = try value(syncGET("/session/\(sid)/window/size"))
        guard let w = (v["width"] as? NSNumber)?.doubleValue,
              let h = (v["height"] as? NSNumber)?.doubleValue else {
            throw IDBError.commandFailed("Invalid window size response")
        }
        return (w, h)
    }

    func configureMJPEG(fps: Int = 30, quality: Int = 50, scalingFactor: Int = 50) {
        guard let sid = sessionID else { return }
        let _ = try? syncPOST("/session/\(sid)/appium/settings", json: [
            "settings": [
                "mjpegServerFramerate": fps,
                "mjpegServerScreenshotQuality": quality,
                "mjpegScalingFactor": scalingFactor
            ]
        ])
    }

    func tap(_ x: Double, _ y: Double) throws {
        guard let sid = sessionID else { throw IDBError.commandFailed("No session") }
        let _ = try syncPOST("/session/\(sid)/wda/tap", json: ["x": x, "y": y])
    }

    func swipe(fromX: Double, fromY: Double, toX: Double, toY: Double, duration: Double) throws {
        guard let sid = sessionID else { throw IDBError.commandFailed("No session") }
        let _ = try syncPOST("/session/\(sid)/wda/dragfromtoforduration",
                             json: ["fromX": fromX, "fromY": fromY,
                                    "toX": toX, "toY": toY, "duration": duration])
    }

    /// Pinch at center point. scale > 1 = zoom in, scale < 1 = zoom out.
    func pinch(centerX: Double, centerY: Double, scale: Double, duration: Double = 0.3) throws {
        guard let sid = sessionID else { throw IDBError.commandFailed("No session") }

        let spread: Double = 80
        let startDist = scale > 1 ? spread * 0.3 : spread
        let endDist = scale > 1 ? spread : spread * 0.3
        let ms = Int(duration * 1000)

        let actions: [[String: Any]] = [
            [
                "type": "pointer", "id": "finger1",
                "parameters": ["pointerType": "touch"],
                "actions": [
                    ["type": "pointerMove", "duration": 0, "x": Int(centerX), "y": Int(centerY - startDist)],
                    ["type": "pointerDown", "button": 0],
                    ["type": "pointerMove", "duration": ms, "x": Int(centerX), "y": Int(centerY - endDist)],
                    ["type": "pointerUp", "button": 0],
                ]
            ],
            [
                "type": "pointer", "id": "finger2",
                "parameters": ["pointerType": "touch"],
                "actions": [
                    ["type": "pointerMove", "duration": 0, "x": Int(centerX), "y": Int(centerY + startDist)],
                    ["type": "pointerDown", "button": 0],
                    ["type": "pointerMove", "duration": ms, "x": Int(centerX), "y": Int(centerY + endDist)],
                    ["type": "pointerUp", "button": 0],
                ]
            ]
        ]

        let _ = try syncPOST("/session/\(sid)/actions", json: ["actions": actions])
    }

    func pressButton(_ name: String) throws {
        guard let sid = sessionID else { throw IDBError.commandFailed("No session") }
        let _ = try syncPOST("/session/\(sid)/wda/pressButton", json: ["name": name])
    }

    func typeKeys(_ keys: [String]) throws {
        guard let sid = sessionID else { throw IDBError.commandFailed("No session") }
        let _ = try syncPOST("/session/\(sid)/wda/keys", json: ["value": keys])
    }

    func source() throws -> String {
        let data = try syncGET("/source")
        let j = try json(data)
        guard let raw = j["value"] as? String else {
            throw IDBError.commandFailed("Invalid source response")
        }
        return raw.replacingOccurrences(of: "\\/", with: "/")
    }

    func screenshot() throws -> Data {
        let data = try syncGET("/screenshot")
        let j = try json(data)
        guard let b64 = j["value"] as? String,
              let imgData = Data(base64Encoded: b64) else {
            throw IDBError.commandFailed("Invalid screenshot response")
        }
        return imgData
    }

    func activeApp() throws -> [String: Any] {
        guard let sid = sessionID else { throw IDBError.commandFailed("No session") }
        return try value(syncGET("/session/\(sid)/wda/activeAppInfo"))
    }

    func launch(bundleId: String) throws {
        guard let sid = sessionID else { throw IDBError.commandFailed("No session") }
        let _ = try syncPOST("/session/\(sid)/wda/apps/launch", json: ["bundleId": bundleId])
    }

    func terminate(bundleId: String) throws {
        guard let sid = sessionID else { throw IDBError.commandFailed("No session") }
        let _ = try syncPOST("/session/\(sid)/wda/apps/terminate", json: ["bundleId": bundleId])
    }

    // MARK: - HTTP helpers

    private func syncGET(_ path: String) throws -> Data {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.timeoutInterval = 10
        return try syncRequest(request)
    }

    private func syncPOST(_ path: String, json body: [String: Any]) throws -> Data {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        return try syncRequest(request)
    }

    private func syncRequest(_ request: URLRequest) throws -> Data {
        var result: Data?
        var error: Error?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, err in
            result = data; error = err; sem.signal()
        }.resume()
        sem.wait()
        if let error = error { throw error }
        return result ?? Data()
    }
}
