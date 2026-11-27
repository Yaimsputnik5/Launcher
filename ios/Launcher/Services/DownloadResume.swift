import Foundation

/// The portion of a client file that is already on disk after an interrupted
/// download, plus how the next HTTP response must be interpreted.
struct DownloadResumePlan: Equatable, Sendable {
    /// Bytes already present in the `.part` file and kept for the next write.
    let startingBytes: UInt64
    /// Full expected size, used to report progress as a fraction of the file.
    let totalBytes: UInt64?
    /// Discard stale partial bytes because the server restarted at offset 0.
    let shouldTruncate: Bool

    var rangeHeader: String? {
        startingBytes > 0 ? "bytes=\(startingBytes)-" : nil
    }
}

/// Wire-level rules for resuming a ranged download. The server may ignore
/// `Range`, answer 206 with an unrelated offset, or advertise an unknown total;
/// all three cases must fall back to a clean restart rather than concatenate
/// unrelated bytes.
enum DownloadResume {
    static func plan(
        existingBytes: UInt64,
        expectedSize: UInt64?,
        statusCode: Int,
        contentRange: String?,
        contentLength: Int64
    ) -> DownloadResumePlan {
        let candidate = expectedSize.map { existingBytes < $0 ? existingBytes : 0 } ?? 0

        if statusCode == 206,
           let range = parseContentRange(contentRange),
           range.start == candidate {
            let remaining = contentLength >= 0 ? UInt64(contentLength) : 0
            let total = range.total ?? expectedSize ?? (candidate + remaining)
            return DownloadResumePlan(
                startingBytes: candidate,
                totalBytes: total > 0 ? total : nil,
                shouldTruncate: false
            )
        }

        let total = expectedSize ?? (contentLength >= 0 ? UInt64(contentLength) : nil)
        return DownloadResumePlan(
            startingBytes: 0,
            totalBytes: total,
            shouldTruncate: true
        )
    }

    /// Parses `bytes 1024-2047/8192` and `bytes 1024-2047/*`.
    static func parseContentRange(_ value: String?) -> (start: UInt64, end: UInt64, total: UInt64?)? {
        guard let value, value.hasPrefix("bytes ") else { return nil }
        let specification = value.dropFirst("bytes ".count)
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            .first
        guard let specification else { return nil }
        let pieces = specification.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard let bounds = pieces.first else { return nil }
        let numbers = bounds.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard numbers.count == 2,
              let start = UInt64(numbers[0]),
              let end = UInt64(numbers[1]),
              end >= start
        else { return nil }

        var total: UInt64?
        if pieces.count == 2, pieces[1] != "*" {
            total = UInt64(pieces[1])
        }
        return (start, end, total)
    }
}
