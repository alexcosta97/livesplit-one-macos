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

        static let configDirectoryArgument = "-LSOConfigDirectory"

        /// The settings folder for this run, if a test chose one.
        static var configDirectory: URL? {
            directory(after: configDirectoryArgument, in: ProcessInfo.processInfo.arguments)
                ?? testHostDirectory("Config", environment: ProcessInfo.processInfo.environment)
        }

        static let pickedFilesArgument = "-LSOPickedFiles"

        /// The answers the scripted file picker gives, if a test chose them (spec §14.2).
        static var pickedFiles: [String?]? {
            pickedFiles(in: ProcessInfo.processInfo.arguments)
        }

        /// The JSON array after `-LSOPickedFiles`: each answer an absolute path, or `null` for
        /// a cancel. `nil` when absent, or when it isn't such an array, which is logged.
        static func pickedFiles(in arguments: [String], log: Log = .shared) -> [String?]? {
            guard let index = arguments.firstIndex(of: pickedFilesArgument),
                index + 1 < arguments.count
            else { return nil }
            do {
                return try JSONDecoder().decode(
                    [String?].self, from: Data(arguments[index + 1].utf8))
            } catch {
                log.record(
                    .error, "Ignoring \(pickedFilesArgument), which isn't a JSON array: \(error)")
                return nil
            }
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
        static var configDirectory: URL? { nil }
        static var pickedFiles: [String?]? { nil }
    #endif
}
