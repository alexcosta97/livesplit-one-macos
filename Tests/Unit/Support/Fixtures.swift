import Foundation

/// The files in `Tests/Fixtures`, copied into each test bundle as a folder.
enum Fixtures {
    private final class Marker {}

    static func url(_ name: String) -> URL {
        guard let folder = Bundle(for: Marker.self).url(forResource: "Fixtures", withExtension: nil)
        else { preconditionFailure("The Fixtures folder is missing from the test bundle") }
        return folder.appending(path: name)
    }
}
