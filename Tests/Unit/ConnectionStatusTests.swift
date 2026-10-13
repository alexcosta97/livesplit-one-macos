import Foundation
import Testing

@testable import LiveSplitOne

@Suite struct ConnectionStatusTests {
    let server = try! ServerURL.parse("192.168.1.20:9087").get()

    @Test func theMenuOffersToConnectWhileNotConnected() {
        #expect(ConnectionStatus.notConnected.menuTitle == "Connect to Server…")
        #expect(ConnectionStatus.notConnected.server == nil)
    }

    @Test func theMenuOffersToDisconnectOtherwise() {
        for status: ConnectionStatus in [
            .connecting(server), .connected(server), .retrying(server, attempt: 3),
        ] {
            #expect(status.menuTitle == "Disconnect from 192.168.1.20:9087")
            #expect(status.server == server)
        }
    }
}

@Suite struct ReconnectDelaysTests {
    @Test func theWaitsDoubleFromOneSecondUpToThirty() {
        let waits = (0...7).map { ReconnectDelays.seconds(beforeRetry: $0) }
        #expect(waits == [1, 2, 4, 8, 16, 30, 30, 30])
    }

    @Test func aHugeAttemptNumberWaitsThirtySeconds() {
        #expect(ReconnectDelays.seconds(beforeRetry: Int.max) == 30)
    }
}
