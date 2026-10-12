/// The waits before each retry after a lost connection: 1, 2, 4, 8 and 16 s, then 30 s for ever
/// (spec §8.3).
enum ReconnectDelays {
    /// The wait in seconds before retry `attempt`, counting from 0.
    static func seconds(beforeRetry attempt: Int) -> Int {
        attempt < 5 ? 1 << max(attempt, 0) : 30
    }
}
