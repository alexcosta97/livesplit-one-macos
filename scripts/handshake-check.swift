// Connects to a LiveSplit One server (such as livesplit-asr-bridge) with
// URLSessionWebSocketTask, the client the app will use (spec §8.1), answers
// its commands and prints everything, to check the handshake (issue #7).
//
//   swift scripts/handshake-check.swift <url> [--origin <origin>] [--seconds <n>]
import Foundation

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
            case ("--seconds", let value?): options.seconds = Double(value) ?? options.seconds
            default: return nil
            }
        }
        return options
    }
}

/// The reply a timer that has no run in progress gives.
func reply(to command: String) -> String {
    if command.contains(#""command":"getCurrentState""#) {
        return #"{"success":{"state":"NotRunning"}}"#
    }
    return #"{"success":null}"#
}

final class Delegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    /// Set before the script closes the connection itself, so that isn't
    /// reported as a failure.
    var closing = false

    func urlSession(
        _ session: URLSession, webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        print("open: handshake succeeded")
    }

    func urlSession(
        _ session: URLSession, webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?
    ) {
        print("closed: code \(closeCode.rawValue)")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)
    {
        if let error, !closing {
            print("failed: \(error.localizedDescription)")
            if let response = task.response as? HTTPURLResponse {
                print("HTTP status \(response.statusCode)")
            }
            exit(1)
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
            print("receive failed: \(error.localizedDescription)")
        }
    }
}

guard let options = Options.parse(CommandLine.arguments) else {
    print("usage: swift scripts/handshake-check.swift <ws-url> [--origin <origin>] [--seconds <n>]")
    exit(2)
}
var request = URLRequest(url: options.url)
if let origin = options.origin {
    request.setValue(origin, forHTTPHeaderField: "Origin")
}
print("connecting to \(options.url.absoluteString), Origin: \(options.origin ?? "(not set)")")
let delegate = Delegate()
let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
let task = session.webSocketTask(with: request)
task.resume()
receive(task)
DispatchQueue.main.asyncAfter(deadline: .now() + options.seconds) {
    delegate.closing = true
    task.cancel(with: .normalClosure, reason: nil)
    print("done after \(Int(options.seconds)) s")
    exit(0)
}
dispatchMain()
