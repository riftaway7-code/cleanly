import Foundation

public struct CleanlyPaths: Sendable {
  public let base: URL
  public var settings: URL { base.appendingPathComponent("settings.json") }
  public var legacyConfig: URL { base.appendingPathComponent("config.json") }
  public var history: URL { base.appendingPathComponent("data/history.json") }

  public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    if let override = environment["CLEANLY_HOME"], !override.isEmpty {
      base = URL(fileURLWithPath: override, isDirectory: true)
    } else {
      let home = environment["HOME"] ?? NSHomeDirectory()
      base = URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent(
        ".cleanly", isDirectory: true)
    }
  }

  public init(base: URL) { self.base = base }
}

public final class SettingsStore: @unchecked Sendable {
  private let paths: CleanlyPaths
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(paths: CleanlyPaths = CleanlyPaths(), fileManager: FileManager = .default) {
    self.paths = paths
    self.fileManager = fileManager
    encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    decoder = JSONDecoder()
  }

  public var fileURL: URL { paths.settings }

  public func load() throws -> CleanlySettings {
    if fileManager.fileExists(atPath: paths.settings.path) {
      do {
        return try decoder.decode(CleanlySettings.self, from: Data(contentsOf: paths.settings))
      } catch {
        throw CleanlyError.settings("Settings file is invalid: \(error.localizedDescription)")
      }
    }
    if fileManager.fileExists(atPath: paths.legacyConfig.path),
      let data = try? Data(contentsOf: paths.legacyConfig),
      let migrated = try? decoder.decode(CleanlySettings.self, from: data)
    {
      try save(migrated)
      return migrated
    }
    let settings = CleanlySettings()
    try save(settings)
    return settings
  }

  public func save(_ settings: CleanlySettings) throws {
    try fileManager.createDirectory(at: paths.base, withIntermediateDirectories: true)
    do {
      let data = try encoder.encode(settings)
      try data.write(to: paths.settings, options: .atomic)
    } catch {
      throw CleanlyError.settings("Could not save settings: \(error.localizedDescription)")
    }
  }

  public func reset() throws -> CleanlySettings {
    let settings = CleanlySettings()
    try save(settings)
    return settings
  }
}
