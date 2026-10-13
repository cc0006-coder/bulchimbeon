import Foundation

public struct DutyLogEntry: Equatable, Sendable {
    public let date: Date
    public let text: String

    public var line: String {
        "\(DutyLogEntry.formatter.string(from: date))  \(text)"
    }

    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
}

/// 근무일지. 메모리에는 최근 `capacity` 건, 파일에는 전부 append.
public final class DutyLog {
    public private(set) var recent: [DutyLogEntry] = []
    private let fileURL: URL?
    private let capacity: Int

    public init(fileURL: URL?, capacity: Int = 50) {
        self.fileURL = fileURL
        self.capacity = capacity
    }

    public static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Bulchimbeon", isDirectory: true)
            .appendingPathComponent("duty-log.txt")
    }

    public func write(_ text: String, at date: Date = Date()) {
        let entry = DutyLogEntry(date: date, text: text)
        recent.insert(entry, at: 0) // 최신순
        if recent.count > capacity { recent.removeLast(recent.count - capacity) }
        append(entry)
    }

    private func append(_ entry: DutyLogEntry) {
        guard let fileURL else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data((ISO8601DateFormatter().string(from: entry.date) + "  " + entry.text + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }
}
