import Foundation

public final class HistoryStore: @unchecked Sendable {
  private let url: URL
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(paths: CleanlyPaths = CleanlyPaths(), fileManager: FileManager = .default) {
    url = paths.history
    self.fileManager = fileManager
    encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    decoder = JSONDecoder()
  }

  public var fileURL: URL { url }

  public func read() throws -> [HistoryRun] {
    guard fileManager.fileExists(atPath: url.path) else { return [] }
    do { return try decoder.decode([HistoryRun].self, from: Data(contentsOf: url)) } catch {
      throw CleanlyError.operation("History is unreadable: \(error.localizedDescription)")
    }
  }

  public func append(entries: [HistoryEntry], command: String, limit: Int) throws {
    guard !entries.isEmpty else { return }
    var history = try read()
    history.append(HistoryRun(time: Self.timestamp(), entries: entries, command: command))
    if history.count > limit { history.removeFirst(history.count - limit) }
    try write(history)
  }

  public func replace(_ runs: [HistoryRun]) throws { try write(runs) }

  private func write(_ runs: [HistoryRun]) throws {
    do {
      try fileManager.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try encoder.encode(runs).write(to: url, options: .atomic)
    } catch {
      throw CleanlyError.operation("Could not save history: \(error.localizedDescription)")
    }
  }

  private static func timestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
  }
}
