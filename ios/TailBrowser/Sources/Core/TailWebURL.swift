import Foundation

enum TailWebURL {
    /// Accepts either a full URL or host[:port] and returns a normalized URL.
    static func normalize(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if trimmed.contains("://") {
            return URL(string: trimmed)
        }
        return URL(string: "http://\(trimmed)")
    }

    static func make(host: String, port: Int, scheme: String = "http") -> URL? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, (1...65535).contains(port) else {
            return nil
        }
        if trimmed.contains("://") {
            return normalize(trimmed)
        }
        let hostPart: String
        if trimmed.contains(":") && !trimmed.hasPrefix("[") {
            hostPart = "[\(trimmed)]"
        } else {
            hostPart = trimmed
        }
        return URL(string: "\(scheme)://\(hostPart):\(port)")
    }
}
