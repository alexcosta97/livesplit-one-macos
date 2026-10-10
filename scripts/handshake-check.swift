// Connects to a LiveSplit One server (such as livesplit-asr-bridge) with
// URLSessionWebSocketTask, the client the app will use (spec §8.1), answers
// its commands and prints everything, to check the handshake (issue #7).
//
//   swift scripts/handshake-check.swift <url> [--origin <origin>] [--seconds <n>]
//
// Exit codes: 0 the connection stayed up for the whole --seconds, 1 the
// handshake failed, 2 usage error, 3 the connection ended after the handshake
// had succeeded.
import Foundation
import Synchronization

struct Options {
    var url: URL
    var origin: String?
    var seconds: Double = 30

    static func parse(_ arguments: [String]) -> Options? {
        var rest = arguments.dropFirst()
        guard var text = rest.popFirst() else { return nil }
        if !text.contains("://") { text = "ws://" + text }
        guard let url = URL(string: text), ["ws", "wss"].contains(url.scheme) else { return nil }
        var options = Options(url: url)
        while let flag = rest.popFirst() {
            switch (flag, rest.popFirst()) {
            case ("--origin", let value?): options.origin = value
            case ("--seconds", let value?):
                guard let seconds = Double(value), seconds.isFinite, seconds >= 0.1,
                    seconds <= 86400
                else { return nil }
                options.seconds = seconds
            default: return nil
            }
        }
        return options
    }
}

/// 30 as `30`, 0.5 as `0.5`.
func format(seconds: Double) -> String {
    seconds == seconds.rounded() ? String(Int(seconds)) : String(seconds)
}

func printError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

/// The reply a timer that has no run in progress gives. The match is
/// deliberately loose (a compact substring): the `received:` line shows the
/// raw command, so a command that doesn't match is visible.
func reply(to command: String) -> String {
    if command.contains(#""command":"getCurrentState""#) {
        return #"{"success":{"state":"NotRunning"}}"#
    }
    return #"{"success":null}"#
}

final class Delegate: NSObject, URLSessionWebSocketDelegate, Sendable {
    private struct State {
        var opened = false
        /// Set by whichever event ends the run first (a drop, or the script's
        /// own end), so that the script cancelling isn't reported as a drop
        /// and a drop isn't reported twice.
        var ended = false
    }
    private let state = Mutex(State())

    func urlSession(
        _ session: URLSession, webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        state.withLock { $0.opened = true }
        print("open: handshake succeeded")
    }

    func urlSession(
        _ session: URLSession, webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?
    ) {
        connectionEnded("the server closed it (close code \(closeCode.rawValue))")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)
    {
        if let error {
            connectionEnded(error.localizedDescription, status: task.response as? HTTPURLResponse)
        }
    }

    /// Reports the end of the connection and exits: 3 if the handshake had
    /// succeeded, 1 if it hadn't. Does nothing if the run already ended.
    func connectionEnded(_ reason: String, status: HTTPURLResponse? = nil) {
        let (first, opened) = state.withLock { state in
            defer { state.ended = true }
            return (!state.ended, state.opened)
        }
        guard first else { return }
        if opened {
            print("connection ended after the handshake: \(reason)")
            print("the handshake itself succeeded; the connection was lost afterwards")
            exit(3)
        }
        printError("handshake failed: \(reason)")
        if let status {
            printError("HTTP status \(status.statusCode)")
        }
        exit(1)
    }

    /// Marks the run as ended by the script itself. Returns nil if a drop got
    /// there first, otherwise whether the handshake had succeeded.
    func finishRun() -> Bool? {
        state.withLock { state in
            defer { state.ended = true }
            return state.ended ? nil : state.opened
        }
    }
}

func receive(_ task: URLSessionWebSocketTask) {
    task.receive { result in
        switch result {
        case .success(.string(let text)):
            print("received: \(text)")
            let answer = reply(to: text)
            task.send(.string(answer)) { error in
                print(error.map { "send failed: \($0)" } ?? "sent: \(answer)")
            }
            receive(task)
        case .success(let other):
            print("received non-text message: \(other)")
            receive(task)
        case .failure(let error):
            var reason = error.localizedDescription
            if task.closeCode != .invalid {
                reason +=
                    task.closeCode == .noStatusReceived
                    ? " (the server closed it without a close code)"
                    : " (the server closed it with close code \(task.closeCode.rawValue))"
            }
            delegate.connectionEnded(reason, status: task.response as? HTTPURLResponse)
        }
    }
}

let delegate = Delegate()
guard let options = Options.parse(CommandLine.arguments) else {
    printError(
        """
        usage: swift scripts/handshake-check.swift <ws-url> [--origin <origin>] [--seconds <n>]
        n is from 0.1 to 86400 seconds (default 30)
        """)
    exit(2)
}
var request = URLRequest(url: options.url)
if let origin = options.origin {
    request.setValue(origin, forHTTPHeaderField: "Origin")
}
print("connecting to \(options.url.absoluteString), Origin: \(options.origin ?? "(not set)")")
let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
let task = session.webSocketTask(with: request)
task.resume()
receive(task)
DispatchQueue.main.asyncAfter(deadline: .now() + options.seconds) {
    guard let opened = delegate.finishRun() else { return }
    guard opened else {
        printError(
            "handshake failed: no handshake response within \(format(seconds: options.seconds)) s")
        exit(1)
    }
    task.cancel(with: .normalClosure, reason: nil)
    print("done after \(format(seconds: options.seconds)) s")
    exit(0)
}
dispatchMain()
