import Foundation

public final class FileOperator: @unchecked Sendable {
  private let fileManager: FileManager

  public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

  public func cleanPlan(
    directory: URL,
    options: CleanOptions,
    settings: CleanlySettings,
    catalog: CategoryCatalog,
    scanner: FileScanner = FileScanner()
  ) throws -> [PlannedMove] {
    let includeHidden = options.includeHidden ?? settings.includeHidden
    let organizeFolders = options.organizeFolders ?? settings.organizeFolders
    let entries = try scanner.immediateEntries(
      in: directory,
      includeHidden: includeHidden,
      excludedNames: Set(settings.excludedNames)
    )
    let knownDestinationNames = Set(catalog.categories.keys.map { $0.lowercased() }).union([
      "other", "folders",
    ])
    var reservedDestinations = Set<String>()
    var moves: [PlannedMove] = []

    for source in entries {
      let values = try source.resourceValues(forKeys: [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
      ])
      if values.isSymbolicLink == true { continue }
      let isPlainDirectory = values.isDirectory == true && values.isPackage != true
      if isPlainDirectory && knownDestinationNames.contains(source.lastPathComponent.lowercased()) {
        continue
      }
      if isPlainDirectory && !organizeFolders { continue }

      let category = catalog.category(for: source, isDirectory: isPlainDirectory)
      if !options.categories.isEmpty && !options.categories.contains(category.lowercased()) {
        continue
      }

      let destinationFolder = directory.appendingPathComponent(category, isDirectory: true)
      let proposed = destinationFolder.appendingPathComponent(
        source.lastPathComponent, isDirectory: isPlainDirectory)
      guard
        let destination = destinationURL(
          for: proposed,
          strategy: settings.collisionStrategy,
          reserved: &reservedDestinations
        )
      else { continue }
      moves.append(PlannedMove(source: source, destination: destination, category: category))
    }
    return moves
  }

  public func performMoves(_ moves: [PlannedMove]) -> OperationResult {
    var result = OperationResult()
    for move in moves {
      do {
        try fileManager.createDirectory(
          at: move.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: move.source, to: move.destination)
        guard fileManager.fileExists(atPath: move.destination.path),
          !fileManager.fileExists(atPath: move.source.path)
        else {
          throw CleanlyError.operation("Move could not be verified")
        }
        result.entries.append(
          HistoryEntry(from: move.source.path, to: move.destination.path, action: .move))
      } catch {
        result.failures.append("\(move.source.lastPathComponent): \(error.localizedDescription)")
        let folder = move.destination.deletingLastPathComponent()
        if let contents = try? fileManager.contentsOfDirectory(atPath: folder.path),
          contents.isEmpty
        {
          try? fileManager.removeItem(at: folder)
        }
      }
    }
    return result
  }

  public func trash(_ urls: [URL]) -> OperationResult {
    var result = OperationResult()
    for url in urls {
      do {
        var resultingURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
        guard let trashed = resultingURL as URL? else {
          throw CleanlyError.operation("macOS did not return the Trash location")
        }
        result.entries.append(HistoryEntry(from: url.path, to: trashed.path, action: .trash))
      } catch {
        result.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
      }
    }
    return result
  }

  public func permanentlyDelete(_ urls: [URL]) -> OperationResult {
    var result = OperationResult()
    for url in urls {
      do {
        try fileManager.removeItem(at: url)
        result.entries.append(HistoryEntry(from: url.path, to: "PERMANENT", action: .permanent))
      } catch {
        result.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
      }
    }
    return result
  }

  public func rollback(_ entries: [HistoryEntry]) {
    for entry in entries.reversed() where !entry.isPermanent {
      guard fileManager.fileExists(atPath: entry.to), !fileManager.fileExists(atPath: entry.from)
      else { continue }
      try? fileManager.createDirectory(
        at: URL(fileURLWithPath: entry.from).deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try? fileManager.moveItem(atPath: entry.to, toPath: entry.from)
    }
  }

  public func undoLastRun(historyStore: HistoryStore) throws -> (
    restored: Int, skippedPermanent: Int
  ) {
    var history = try historyStore.read()
    guard let run = history.last else {
      throw CleanlyError.operation("History is empty. There is nothing to undo.")
    }
    let recoverable = run.entries.filter { !$0.isPermanent }

    for entry in recoverable {
      guard fileManager.fileExists(atPath: entry.to) else {
        throw CleanlyError.operation(
          "Cannot undo because the recorded item is missing: \(entry.to)")
      }
      guard !fileManager.fileExists(atPath: entry.from) else {
        throw CleanlyError.operation(
          "Cannot undo because the original location is occupied: \(entry.from)")
      }
    }

    var restored: [HistoryEntry] = []
    do {
      for entry in recoverable.reversed() {
        let parent = URL(fileURLWithPath: entry.from).deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try fileManager.moveItem(atPath: entry.to, toPath: entry.from)
        restored.append(entry)
      }
    } catch {
      for entry in restored.reversed() where fileManager.fileExists(atPath: entry.from) {
        try? fileManager.createDirectory(
          at: URL(fileURLWithPath: entry.to).deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try? fileManager.moveItem(atPath: entry.from, toPath: entry.to)
      }
      throw CleanlyError.operation(
        "Undo stopped safely and rolled back: \(error.localizedDescription)")
    }

    history.removeLast()
    do { try historyStore.replace(history) } catch {
      for entry in restored.reversed() where fileManager.fileExists(atPath: entry.from) {
        try? fileManager.createDirectory(
          at: URL(fileURLWithPath: entry.to).deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try? fileManager.moveItem(atPath: entry.from, toPath: entry.to)
      }
      throw error
    }
    removeNewlyEmptyParents(from: recoverable)
    return (recoverable.count, run.entries.count - recoverable.count)
  }

  private func destinationURL(
    for proposed: URL,
    strategy: CollisionStrategy,
    reserved: inout Set<String>
  ) -> URL? {
    if !fileManager.fileExists(atPath: proposed.path), !reserved.contains(proposed.path) {
      reserved.insert(proposed.path)
      return proposed
    }
    guard strategy == .rename else { return nil }
    let ext = proposed.pathExtension
    let stem = proposed.deletingPathExtension().lastPathComponent
    let folder = proposed.deletingLastPathComponent()
    var number = 2
    while number < 10_000 {
      let suffix = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
      let candidate = folder.appendingPathComponent(suffix)
      if !fileManager.fileExists(atPath: candidate.path), !reserved.contains(candidate.path) {
        reserved.insert(candidate.path)
        return candidate
      }
      number += 1
    }
    return nil
  }

  private func removeNewlyEmptyParents(from entries: [HistoryEntry]) {
    let originalParents = Set(
      entries.map { URL(fileURLWithPath: $0.from).deletingLastPathComponent().path })
    let destinationParents = Set(
      entries.map { URL(fileURLWithPath: $0.to).deletingLastPathComponent().path })
    for path in destinationParents.subtracting(originalParents) {
      guard let contents = try? fileManager.contentsOfDirectory(atPath: path), contents.isEmpty
      else { continue }
      try? fileManager.removeItem(atPath: path)
    }
  }
}
