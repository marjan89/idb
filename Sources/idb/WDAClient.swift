import Foundation

/// HTTP client for WDA API (session setup, buttons, typing, screenshots)
class WDAClient {
    let baseURL: String
    var sessionID: String?

    init(baseURL: String) {
        self.baseURL = baseURL
    }

    func status() throws -> [String: Any] {
        let data = try syncGET("/status")
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return json["value"] as! [String: Any]
    }

    func createSession() throws -> String {
        let body: [String: Any] = ["capabilities": ["alwaysMatch": ["platformName": "iOS"]]]
        let data = try syncPOST("/session", json: body)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let value = json["value"] as! [String: Any]
        sessionID = value["sessionId"] as? String
        return sessionID!
    }

    func windowSize() throws -> (width: Double, height: Double) {
        guard let sid = sessionID else { throw IDBError.commandFailed("No session") }
        let data = try syncGET("/session/\(sid)/window/size")
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let value = json["value"] as! [String: Any]
        return (
            (value["width"] as! NSNumber).doubleValue,
            (value["height"] as! NSNumber).doubleValue
        )
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
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let raw = json["value"] as? String ?? ""
        // WDA returns XML with escaped forward slashes — unescape them
        return raw.replacingOccurrences(of: "\\/", with: "/")
    }

    func screenshot() throws -> Data {
        let data = try syncGET("/screenshot")
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        guard let b64 = json["value"] as? String,
              let imgData = Data(base64Encoded: b64) else {
            throw IDBError.commandFailed("Invalid screenshot response")
        }
        return imgData
    }

    func activeApp() throws -> [String: Any] {
        guard let sid = sessionID else { throw IDBError.commandFailed("No session") }
        let data = try syncGET("/session/\(sid)/wda/activeAppInfo")
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return json["value"] as? [String: Any] ?? [:]
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

    private func syncPOST(_ path: String, json: [String: Any]) throws -> Data {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        request.timeoutInterval = 10
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
