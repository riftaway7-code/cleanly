import CryptoKit
import Foundation

public struct FileScanner {
  private let fileManager: FileManager

  public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

  public func validatedDirectory(_ rawPath: String, defaultPath: String = ".") throws -> URL {
    let expanded = (rawPath.isEmpty ? defaultPath : rawPath) as NSString
    let url = URL(fileURLWithPath: expanded.expandingTildeInPath, isDirectory: true)
      .standardizedFileURL.resolvingSymlinksInPath()
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue
    else {
      throw CleanlyError.notDirectory("Directory does not exist: \(url.path)")
    }
    return url
  }

  public func validateSafeMutationRoot(_ url: URL) throws {
    let resolved = url.standardizedFileURL.resolvingSymlinksInPath().path
    let home = (ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()) as NSString
    let protected = [
      "/", home.expandingTildeInPath, "/Applications", "/Library", "/System", "/Users", "/Volumes",
      "/bin", "/sbin", "/usr", "/private", "/opt",
    ]
    if protected.contains(resolved) {
      throw CleanlyError.unsafePath(
        "Refusing to modify protected directory: \(resolved). Choose a folder inside it instead.")
    }
  }

  public func immediateEntries(
    in directory: URL,
    includeHidden: Bool,
    excludedNames: Set<String>
  ) throws -> [URL] {
    let keys: [URLResourceKey] = [
      .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey,
    ]
    let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
    do {
      return try fileManager.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: keys, options: options
      )
      .filter { !excludedNames.contains($0.lastPathComponent) }
      .sorted {
        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
      }
    } catch {
      throw CleanlyError.operation(
        "Could not scan \(directory.path): \(error.localizedDescription)")
    }
  }

  public func recursiveFiles(
    in directory: URL,
    includeHidden: Bool,
    excludedNames: Set<String>
  ) throws -> [FileRecord] {
    let keys: [URLResourceKey] = [
      .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey, .fileSizeKey,
      .contentModificationDateKey, .nameKey,
    ]
    var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
    if !includeHidden { options.insert(.skipsHiddenFiles) }
    guard
      let enumerator = fileManager.enumerator(
        at: directory, includingPropertiesForKeys: keys, options: options)
    else {
      throw CleanlyError.operation("Could not scan \(directory.path)")
    }
    var result: [FileRecord] = []
    while let url = enumerator.nextObject() as? URL {
      if excludedNames.contains(url.lastPathComponent) {
        enumerator.skipDescendants()
        continue
      }
      guard let values = try? url.resourceValues(forKeys: Set(keys)),
        values.isRegularFile == true, values.isSymbolicLink != true
      else { continue }
      result.append(
        FileRecord(
          url: url,
          size: Int64(values.fileSize ?? 0),
          modified: values.contentModificationDate ?? .distantPast
        ))
    }
    return result.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
  }

  public func emptyDirectories(
    in directory: URL,
    includeHidden: Bool,
    excludedNames: Set<String>
  ) throws -> [URL] {
    var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
    if !includeHidden { options.insert(.skipsHiddenFiles) }
    guard
      let enumerator = fileManager.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
        options: options
      )
    else { throw CleanlyError.operation("Could not scan \(directory.path)") }

    var directories: [URL] = []
    while let url = enumerator.nextObject() as? URL {
      if excludedNames.contains(url.lastPathComponent) {
        enumerator.skipDescendants()
        continue
      }
      let values = try? url.resourceValues(forKeys: [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
      ])
      if values?.isPackage == true || values?.isSymbolicLink == true {
        enumerator.skipDescendants()
        continue
      }
      if values?.isDirectory == true { directories.append(url) }
    }
    let deepestFirst = directories.sorted { $0.pathComponents.count > $1.pathComponents.count }
    var logicallyEmpty = Set<String>()
    for url in deepestFirst {
      guard
        let contents = try? fileManager.contentsOfDirectory(
          at: url,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: []
        )
      else { continue }
      if contents.allSatisfy({ logicallyEmpty.contains($0.path) }) {
        logicallyEmpty.insert(url.path)
      }
    }
    return
      directories
      .filter {
        logicallyEmpty.contains($0.path)
          && !logicallyEmpty.contains($0.deletingLastPathComponent().path)
      }
      .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
  }

  public func duplicateGroups(in files: [FileRecord]) throws -> [[FileRecord]] {
    let candidates = Dictionary(grouping: files, by: \.size).values.filter { $0.count > 1 }
    var groups: [[FileRecord]] = []
    for sizeGroup in candidates {
      var hashes: [String: [FileRecord]] = [:]
      for file in sizeGroup { hashes[try sha256(file.url), default: []].append(file) }
      groups.append(contentsOf: hashes.values.filter { $0.count > 1 })
    }
    return groups.sorted { ($0.first?.url.path ?? "") < ($1.first?.url.path ?? "") }
  }

  private func sha256(_ url: URL) throws -> String {
    guard let handle = FileHandle(forReadingAtPath: url.path) else {
      throw CleanlyError.operation("Could not read \(url.path)")
    }
    defer { try? handle.close() }
    var hasher = SHA256()
    while true {
      let data = try handle.read(upToCount: 1_048_576) ?? Data()
      if data.isEmpty { break }
      hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
