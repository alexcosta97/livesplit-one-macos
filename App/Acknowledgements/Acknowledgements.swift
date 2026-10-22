import Foundation

/// The notices of the third-party code built into the app (spec §4.4), which
/// `scripts/build-notices.sh` writes into the app's resources.
enum Acknowledgements {
    /// Shown instead if the file is missing, which only a broken build can cause.
    static let missing =
        "The acknowledgements are missing from this copy of the app. Download it again from "
        + "https://github.com/alexcosta97/livesplit-one-macos/releases/latest."

    /// The notices in `bundle`, or `nil` if its `Acknowledgements.txt` is missing or can't be
    /// read.
    static func text(in bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: "Acknowledgements", withExtension: "txt")
        else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
