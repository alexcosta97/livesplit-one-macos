import Foundation

/// The overlay notices (spec §6): each shows for 4 seconds, one at a time, in the order they
/// came. A notice already shown or waiting isn't queued again, so a repeated status doesn't pile
/// up.
@MainActor
final class NoticeQueue {
    /// Runs an action on the main actor after a delay in seconds.
    typealias Schedule = (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void

    static let duration: TimeInterval = 4

    /// Called with the notice to show, or `nil` when none is left.
    var onChange: ((String?) -> Void)?
    private(set) var current: String?
    private(set) var waiting: [String] = []
    private let schedule: Schedule

    init(schedule: @escaping Schedule = NoticeQueue.afterDelay) {
        self.schedule = schedule
    }

    func show(_ text: String) {
        guard text != current, !waiting.contains(text) else { return }
        if current == nil {
            present(text)
        } else {
            waiting.append(text)
        }
    }

    private func present(_ text: String) {
        current = text
        onChange?(text)
        schedule(Self.duration) { [weak self] in self?.next() }
    }

    private func next() {
        if waiting.isEmpty {
            current = nil
            onChange?(nil)
        } else {
            present(waiting.removeFirst())
        }
    }

    nonisolated static func afterDelay(
        _ delay: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { action() }
        }
    }
}
