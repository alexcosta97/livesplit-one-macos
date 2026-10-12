/// Text for log lines.
enum LogText {
    /// `text` on one line, safe for a log. A path from a splits file, `app.toml` or a script
    /// can't be trusted: backslashes, line breaks (U+2028 and U+2029 included) and other control
    /// characters are written escaped, so it can't forge a log line.
    static func escaped(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                switch scalar.properties.generalCategory {
                case .control, .lineSeparator, .paragraphSeparator:
                    result += "\\u{" + String(scalar.value, radix: 16) + "}"
                default:
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }
}
