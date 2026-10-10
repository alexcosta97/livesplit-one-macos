import Foundation

/// Folders that test runs choose at launch, so tests never touch the user's own settings and
/// logs (spec §14.2). Only Debug builds, which tests use, read them; a Release build doesn't
/// contain them.
enum LaunchOverrides {
    #if DEBUG
        static let logDirectoryArgument = "-LSOLogDirectory"

        /// The log folder for this run, if a test chose one.
        static var logDirectory: URL? {
            directory(after: logDirectoryArgument, in: ProcessInfo.processInfo.arguments)
                ?? testHostDirectory("Logs", environment: ProcessInfo.processInfo.environment)
        }

        /// The absolute folder after `argument`, as in `-LSOLogDirectory /private/tmp/x`.
        static func directory(after argument: String, in arguments: [String]) -> URL? {
            guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count
            else { return nil }
            let path = arguments[index + 1]
            guard path.hasPrefix("/") else { return nil }
            return URL(filePath: path, directoryHint: .isDirectory)
        }

        /// A temporary folder when the app is hosting unit or headless UI tests, so test runs
        /// don't add to the developer's own files.
        static func testHostDirectory(_ name: String, environment: [String: String]) -> URL? {
            guard environment["XCTestConfigurationFilePath"] != nil else { return nil }
            return FileManager.default.temporaryDirectory
                .appending(path: "lso-test-host/\(name)", directoryHint: .isDirectory)
        }
    #else
        static var logDirectory: URL? { nil }
    #endif
}
