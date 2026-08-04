import Foundation

public enum CleanlyError: LocalizedError, Equatable {
  case invalidArguments(String)
  case unsafePath(String)
  case notDirectory(String)
  case settings(String)
  case operation(String)

  public var errorDescription: String? {
    switch self {
    case .invalidArguments(let message), .unsafePath(let message),
      .notDirectory(let message), .settings(let message), .operation(let message):
      return message
    }
  }
}

public enum HistoryAction: String, Codable, Sendable {
  case move
  case trash
  case permanent
}

public struct HistoryEntry: Codable, Equatable, Sendable {
  public let from: String
  public let to: String
  public let action: HistoryAction?

  public init(from: String, to: String, action: HistoryAction? = nil) {
    self.from = from
    self.to = to
    self.action = action
  }

  public var isPermanent: Bool { to == "PERMANENT" || action == .permanent }
}

public struct HistoryRun: Codable, Equatable, Sendable {
  public let time: String
  public let entries: [HistoryEntry]
  public let command: String?

  public init(time: String, entries: [HistoryEntry], command: String? = nil) {
    self.time = time
    self.entries = entries
    self.command = command
  }
}

public struct PlannedMove: Equatable, Sendable {
  public let source: URL
  public let destination: URL
  public let category: String

  public init(source: URL, destination: URL, category: String) {
    self.source = source
    self.destination = destination
    self.category = category
  }
}

public struct FileRecord: Equatable, Sendable {
  public let url: URL
  public let size: Int64
  public let modified: Date

  public init(url: URL, size: Int64, modified: Date) {
    self.url = url
    self.size = size
    self.modified = modified
  }
}

public struct OperationResult: Equatable, Sendable {
  public var entries: [HistoryEntry]
  public var failures: [String]

  public init(entries: [HistoryEntry] = [], failures: [String] = []) {
    self.entries = entries
    self.failures = failures
  }
}

public enum ConfirmationLevel: String, Codable, CaseIterable, Sendable {
  case standard
  case strict
}

public enum CollisionStrategy: String, Codable, CaseIterable, Sendable {
  case rename
  case skip
}

public struct CleanlySettings: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var tipsEnabled: Bool
  public var confirmationLevel: ConfirmationLevel
  public var includeHidden: Bool
  public var organizeFolders: Bool
  public var collisionStrategy: CollisionStrategy
  public var oldFileDays: Int
  public var largeFileMB: Int
  public var historyLimit: Int
  public var defaultPath: String
  public var excludedNames: [String]
  public var customCategories: [String: [String]]
  public var disabledCategories: [String]

  public init(
    schemaVersion: Int = 1,
    tipsEnabled: Bool = true,
    confirmationLevel: ConfirmationLevel = .standard,
    includeHidden: Bool = false,
    organizeFolders: Bool = false,
    collisionStrategy: CollisionStrategy = .rename,
    oldFileDays: Int = 90,
    largeFileMB: Int = 500,
    historyLimit: Int = 100,
    defaultPath: String = ".",
    excludedNames: [String] = [".git", ".cleanly"],
    customCategories: [String: [String]] = [:],
    disabledCategories: [String] = []
  ) {
    self.schemaVersion = schemaVersion
    self.tipsEnabled = tipsEnabled
    self.confirmationLevel = confirmationLevel
    self.includeHidden = includeHidden
    self.organizeFolders = organizeFolders
    self.collisionStrategy = collisionStrategy
    self.oldFileDays = oldFileDays
    self.largeFileMB = largeFileMB
    self.historyLimit = historyLimit
    self.defaultPath = defaultPath
    self.excludedNames = excludedNames
    self.customCategories = customCategories
    self.disabledCategories = disabledCategories
  }
}

public struct CleanOptions: Equatable, Sendable {
  public var path: String
  public var categories: Set<String>
  public var includeHidden: Bool?
  public var organizeFolders: Bool?
  public var assumeYes: Bool

  public init(
    path: String = ".",
    categories: Set<String> = [],
    includeHidden: Bool? = nil,
    organizeFolders: Bool? = nil,
    assumeYes: Bool = false
  ) {
    self.path = path
    self.categories = categories
    self.includeHidden = includeHidden
    self.organizeFolders = organizeFolders
    self.assumeYes = assumeYes
  }
}
