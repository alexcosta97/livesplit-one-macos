import Foundation

/// A server address the user typed into the Connect sheet (spec §8.1).
struct ServerURL: Equatable, Sendable {
    let url: URL
    /// What the menu, notices and log call the server: the host, with `:<port>` when the URL
    /// names a port, such as `192.168.1.20:9087`.
    let host: String

    /// Why the address can't be used.
    enum Problem: Error, Equatable {
        case scheme, host

        /// What the sheet says below the field (spec §8.1).
        var message: String {
            switch self {
            case .scheme: "Use a ws:// or wss:// address."
            case .host: "Enter the server's address."
            }
        }
    }

    /// Reads what the user typed: trimmed, with `ws://` added when it has no scheme.
    static func parse(_ text: String) -> Result<ServerURL, Problem> {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "ws://" + text }
        guard var components = URLComponents(string: text),
            let scheme = components.scheme?.lowercased()
        else { return .failure(.host) }
        guard scheme == "ws" || scheme == "wss" else { return .failure(.scheme) }
        components.scheme = scheme
        guard var host = components.host, !host.isEmpty, let url = components.url
        else { return .failure(.host) }
        // An IPv6 address keeps its brackets, so the port can't be read as part of it.
        if host.contains(":"), !host.hasPrefix("[") { host = "[\(host)]" }
        let shown = components.port.map { "\(host):\($0)" } ?? host
        return .success(ServerURL(url: url, host: shown))
    }
}
