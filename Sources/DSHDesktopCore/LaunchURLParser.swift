import Foundation

/// Incrementally extracts the authenticated loopback URL printed by `dsh web`.
public struct LaunchURLParser {
    private static let launchURLRegex = try! NSRegularExpression(
        pattern: #"https?://(?:127\.0\.0\.1|localhost|\[::1\]):\d+/\?token=[A-Za-z0-9_-]+"#
    )

    private var buffer = ""

    public init() {}

    public mutating func reset() {
        buffer = ""
    }

    public mutating func ingest(_ chunk: String) -> URL? {
        buffer.append(Self.strippingANSI(from: chunk))

        let searchRange = NSRange(buffer.startIndex..<buffer.endIndex, in: buffer)
        if let match = Self.launchURLRegex.firstMatch(in: buffer, range: searchRange),
           let swiftRange = Range(match.range, in: buffer),
           let url = URL(string: String(buffer[swiftRange])) {
            buffer = ""
            return url
        }

        if buffer.count > 65_536 {
            buffer = String(buffer.suffix(16_384))
        }
        return nil
    }

    public static func strippingANSI(from text: String) -> String {
        text.replacingOccurrences(
            of: #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
    }
}
