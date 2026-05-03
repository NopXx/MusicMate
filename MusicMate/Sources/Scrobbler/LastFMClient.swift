import Foundation
import CryptoKit

enum LastFMClient {
    static let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!

    static func sign(_ params: [String: String], secret: String) -> String {
        let keys = params.keys
            .filter { $0 != "format" && $0 != "callback" }
            .sorted()
        var raw = ""
        for k in keys { raw += "\(k)\(params[k] ?? "")" }
        raw += secret
        let digest = Insecure.MD5.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func call(method: String,
                     params: [String: String],
                     secret: String? = nil,
                     post: Bool = false) async -> [String: Any] {
        var p = params
        p["method"] = method
        if let secret { p["api_sig"] = sign(p, secret: secret) }
        p["format"] = "json"

        let body = formEncode(p)
        var request: URLRequest
        if post {
            request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(body.utf8)
        } else {
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
            components.queryItems = p.map { URLQueryItem(name: $0.key, value: $0.value) }
            request = URLRequest(url: components.url!)
        }
        request.timeoutInterval = 8

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }
        } catch {
            return ["error": -1, "message": error.localizedDescription]
        }
        return ["error": -1, "message": "invalid response"]
    }

    private static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return params
            .map { "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
    }
}
