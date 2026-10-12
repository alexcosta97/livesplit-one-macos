import Foundation
import LiveSplitCore

/// Splits files (spec §7.1): any format livesplit-core reads, always saved as `.lss`.
enum SplitsFile {
    /// The run in `url`, through livesplit-core's composite parser.
    static func load(_ url: URL) throws(FileLoadError) -> Run {
        let data = try FileLoadError.read(url)
        guard !data.isEmpty else { throw .notSplits }
        let result = data.withUnsafeBytes { bytes in
            // No path: with one, livesplit-core would also open the files WSplit, SplitterZ,
            // FaceSplit and LibreSplit splits name for their icons (any path, read without
            // limit: "/dev/zero" or a pipe would hang the main thread), and TimeSplitTracker's
            // "-RunLog.txt". So icons of those formats and TimeSplitTracker's attempt history
            // aren't loaded; the splits and times are.
            Run.parse(UnsafeMutableRawPointer(mutating: bytes.baseAddress), bytes.count, "")
        }
        guard result.parsedSuccessfully() else { throw .notSplits }
        let run = result.unwrap()
        // A timer can't use a run with no segments.
        guard run.len() > 0 else { throw .notSplits }
        return run
    }

    /// Whether Save Splits has to ask for a file name: the run has no file, or one that isn't
    /// `.lss`, which saving would overwrite in another format.
    static func needsNewName(_ path: String?) -> Bool {
        guard let path else { return true }
        return URL(filePath: path).pathExtension.lowercased() != "lss"
    }

    /// The name Save Splits As… suggests: the file's own name with `.lss`, or the game and
    /// category for a run with no file.
    static func suggestedName(path: String?, run: RunRef) -> String {
        if let path {
            return URL(filePath: path).deletingPathExtension().lastPathComponent + ".lss"
        }
        let name = run.extendedFileName(false)
        return (name.isEmpty ? "Splits" : name) + ".lss"
    }
}
