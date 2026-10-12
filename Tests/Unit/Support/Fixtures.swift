import Foundation

/// The files in `Tests/Fixtures`, copied into each test bundle as a folder.
enum Fixtures {
    private final class Marker {}

    static func url(_ name: String) -> URL {
        Bundle(for: Marker.self).url(forResource: "Fixtures", withExtension: nil)!
            .appending(path: name)
    }
}
