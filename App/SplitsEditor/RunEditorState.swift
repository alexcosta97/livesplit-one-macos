import Foundation

/// `RunEditor`'s state, as `stateAsJson` encodes it (livesplit-core's `run/editor/state.rs`;
/// spec §9). The run's metadata is in the JSON too, and is ignored.
struct RunEditorState: Decodable, Equatable {
    /// An image id; `ImageCache` has no data for the empty image, which means no icon.
    var icon: String
    var game: String
    var category: String
    var offset: String
    var attempts: UInt32
    var timingMethod: TimingMethod
    var rows: [Row]
    var comparisonNames: [String]
    var buttons: Buttons

    /// Which actions can run with the current selection.
    struct Buttons: Decodable, Equatable {
        var canRemove: Bool
        var canMoveUp: Bool
        var canMoveDown: Bool
        var canCreateSegmentGroup: Bool
        var canRemoveSegmentGroups: Bool
    }

    enum Selection: String, Decodable {
        case notSelected = "NotSelected"
        case selected = "Selected"
        /// Selected, and the one segment whose fields are being edited.
        case active = "Active"
    }

    struct Segment: Decodable, Equatable {
        /// The segment's index in the run. Row numbers differ when groups are present.
        var segmentIndex: Int
        var icon: String
        var name: String
        var splitTime: String
        var segmentTime: String
        var bestSegmentTime: String
        /// One per name in `comparisonNames`, in that order.
        var comparisonTimes: [String]
        var selected: Selection
        var isIndented: Bool
    }

    struct Group: Decodable, Equatable {
        /// The group's index in the run. Row numbers differ from it.
        var groupIndex: Int
        /// The name shown: `explicitName`, or the last segment's name.
        var name: String
        var explicitName: String?
        var icon: String
        var hasExplicitIcon: Bool
        /// Whether every segment of the group is selected.
        var selected: Bool
    }

    /// A row of the editor, tagged by `"kind"`: `"Segment"` or `"SegmentGroup"`.
    enum Row: Decodable, Equatable {
        case segment(Segment)
        case group(Group)

        private enum Key: String, CodingKey { case kind }

        init(from decoder: any Decoder) throws {
            let kind = try decoder.container(keyedBy: Key.self).decode(String.self, forKey: .kind)
            switch kind {
            case "Segment": self = .segment(try Segment(from: decoder))
            case "SegmentGroup": self = .group(try Group(from: decoder))
            default:
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: decoder.codingPath, debugDescription: "Unknown row kind \(kind)"
                    ))
            }
        }
    }

    /// The state in `json`.
    static func decode(_ json: String) throws -> RunEditorState {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RunEditorState.self, from: Data(json.utf8))
    }
}

/// The editor names the timing methods "RealTime" and "GameTime".
extension TimingMethod: Decodable {
    init(from decoder: any Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        switch name {
        case "RealTime": self = .realTime
        case "GameTime": self = .gameTime
        default:
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown timing method \(name)"))
        }
    }
}
