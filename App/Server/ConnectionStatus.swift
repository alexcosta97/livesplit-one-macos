/// Where the connection to the server is (spec §8.3).
enum ConnectionStatus: Equatable, Sendable {
    case notConnected
    /// The first attempt, after Connect.
    case connecting(ServerURL)
    case connected(ServerURL)
    /// Lost after being open: waiting for a retry, or retrying. `attempt` counts the retries
    /// that failed since, from 0.
    case retrying(ServerURL, attempt: Int)

    /// The server, unless not connected.
    var server: ServerURL? {
        switch self {
        case .notConnected: nil
        case .connecting(let server), .connected(let server), .retrying(let server, _): server
        }
    }

    /// The Connect item's title in both menus (spec §8.3).
    var menuTitle: String {
        server.map { "Disconnect from \($0.host)" } ?? "Connect to Server…"
    }
}
