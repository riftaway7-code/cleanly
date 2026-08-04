import Foundation

public final class CleanlyApplication {
  public static let version = "2.0.0"

  private let settingsStore: SettingsStore
  private let historyStore: HistoryStore
  private let scanner: FileScanner
  private let fileOperator: FileOperator
  private let write: (String) -> Void
  private let read: () -> String?

  public init(
    settingsStore: SettingsStore = SettingsStore(),
    historyStore: HistoryStore = HistoryStore(),
    scanner: FileScanner = FileScanner(),
    fileOperator: FileOperator = FileOperator(),
    write: @escaping (String) -> Void = { print($0) },
    read: @escaping () -> String? = { readLine() }
  ) {
    self.settingsStore = settingsStore
    self.historyStore = historyStore
    self.scanner = scanner
    self.fileOperator = fileOperator
    self.write = write
    self.read = read
  }

  @discardableResult
  public func run(_ rawArguments: [String]) -> Int32 {
    do {
      return try dispatch(rawArguments)
    } catch let error as CleanlyError {
      write("Error: \(error.localizedDescription)")
      return 1
    } catch {
      write("Error: \(error.localizedDescription)")
      return 1
    }
  }

  private func dispatch(_ rawArguments: [String]) throws -> Int32 {
    var arguments = rawArguments
    if arguments.isEmpty {
      write(Self.generalHelp)
      return 0
    }
    if arguments == ["-v"] || arguments == ["--version"] || arguments == ["version"] {
      write("cleanly v\(Self.version)")
      return 0
    }
    if arguments.first == "--undo" { arguments = ["undo"] + arguments.dropFirst() }
    if arguments.first == "-h" || arguments.first == "--help" {
      write(Self.generalHelp)
      return 0
    }
    if arguments.first == "help" {
      let command = arguments.dropFirst().first
      write(Self.help(for: command))
      return 0
    }

    let commands = Set([
      "clean", "preview", "undo", "history", "remove", "duplicates", "empty", "large", "old",
      "settings", "update",
    ])
    let first = arguments[0]
    if !commands.contains(first) {
      if first.hasPrefix("-") {
        throw CleanlyError.invalidArguments(
          "Unknown option: \(first). Run `cleanly help` for available commands.")
      }
      let expanded = (first as NSString).expandingTildeInPath
      if !FileManager.default.fileExists(atPath: expanded), !first.contains("/"),
        !first.hasPrefix("."),
        let suggestion = commands.min(by: { editDistance(first, $0) < editDistance(first, $1) }),
        editDistance(first, suggestion) <= 3
      {
        throw CleanlyError.invalidArguments(
          "Unknown command: \(first). Did you mean `cleanly \(suggestion)`?")
      }
      arguments.insert("clean", at: 0)
    }
    let command = arguments.removeFirst()
    if arguments.contains("--help") || arguments.contains("-h") {
      write(Self.help(for: command))
      return 0
    }

    switch command {
    case "clean": return try runClean(arguments, previewOnly: false)
    case "preview": return try runClean(arguments, previewOnly: true)
    case "undo": return try runUndo(arguments)
    case "history": return try runHistory(arguments)
    case "remove": return try runRemove(arguments)
    case "duplicates": return try runDuplicates(arguments)
    case "empty": return try runEmpty(arguments)
    case "large": return try runFileReport(arguments, kind: .large)
    case "old": return try runFileReport(arguments, kind: .old)
    case "settings": return try runSettings(arguments)
    case "update": return try runUpdate(arguments)
    default: throw CleanlyError.invalidArguments("Unknown command: \(command)")
    }
  }

  private func runClean(_ arguments: [String], previewOnly: Bool) throws -> Int32 {
    let settings = try settingsStore.load()
    let options = try parseCleanOptions(arguments, defaultPath: settings.defaultPath)
    let directory = try scanner.validatedDirectory(options.path, defaultPath: settings.defaultPath)
    if !previewOnly { try scanner.validateSafeMutationRoot(directory) }
    let catalog = CategoryCatalog(settings: settings)
    let moves = try fileOperator.cleanPlan(
      directory: directory,
      options: options,
      settings: settings,
      catalog: catalog,
      scanner: scanner
    )

    write("Directory: \(directory.path)")
    write("Mode: \(previewOnly ? "Preview only" : "Clean")")
    if moves.isEmpty {
      write("Result: Everything is already clean. No items need to move.")
      if !previewOnly { finishClean(settings: settings, moved: 0) }
      return 0
    }
    write("Plan: \(moves.count) item\(moves.count == 1 ? "" : "s") will be organized.")
    for move in moves {
      write(
        "Move: \(move.source.lastPathComponent) -> \(move.category)/\(move.destination.lastPathComponent)"
      )
    }
    if previewOnly {
      write(
        "Result: No files were changed. Run `cleanly clean \(shellQuote(directory.path))` to apply this plan."
      )
      return 0
    }
    guard
      confirm(
        label: "Move confirmation",
        prompt: "Move \(moves.count) item\(moves.count == 1 ? "" : "s") into labeled folders?",
        token: settings.confirmationLevel == .strict ? "MOVE" : nil,
        assumeYes: options.assumeYes
      )
    else {
      write("Result: Cancelled. No files were changed.")
      return 2
    }

    let result = fileOperator.performMoves(moves)
    try saveOrRollback(result: result, command: "clean", settings: settings)
    for entry in result.entries {
      write(
        "Moved: \(URL(fileURLWithPath: entry.from).lastPathComponent) -> \(relativeDestination(entry.to, root: directory))"
      )
    }
    reportFailures(result.failures)
    finishClean(settings: settings, moved: result.entries.count)
    return result.failures.isEmpty ? 0 : 1
  }

  private func runUndo(_ arguments: [String]) throws -> Int32 {
    guard arguments.isEmpty else { throw CleanlyError.invalidArguments("Usage: cleanly undo") }
    let result = try fileOperator.undoLastRun(historyStore: historyStore)
    write("Restored: \(result.restored) item\(result.restored == 1 ? "" : "s")")
    if result.skippedPermanent > 0 {
      write(
        "Not recoverable: \(result.skippedPermanent) permanently deleted item\(result.skippedPermanent == 1 ? "" : "s")"
      )
    }
    write("Result: The latest recorded operation was undone.")
    return 0
  }

  private func runHistory(_ arguments: [String]) throws -> Int32 {
    var limit = 10
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--limit":
        limit = try integerValue(after: &index, in: arguments, option: "--limit", minimum: 1)
      default: throw CleanlyError.invalidArguments("Unknown history option: \(arguments[index])")
      }
      index += 1
    }
    let runs = try historyStore.read().suffix(limit).reversed()
    write("History file: \(historyStore.fileURL.path)")
    if runs.isEmpty {
      write("Result: History is empty.")
      return 0
    }
    write("Runs: \(runs.count)")
    for run in runs {
      let permanent = run.entries.filter(\.isPermanent).count
      write(
        "Run: \(run.time) | command: \(run.command ?? "legacy") | items: \(run.entries.count) | permanent: \(permanent)"
      )
    }
    return 0
  }

  private func runRemove(_ arguments: [String]) throws -> Int32 {
    let settings = try settingsStore.load()
    var path = settings.defaultPath
    var extensions = Set<String>()
    var categories = Set<String>()
    var permanent = false
    var assumeYes = false
    var permanentToken: String?
    var positionals: [String] = []
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--extension", "-f":
        index += 1
        guard index < arguments.count, !arguments[index].hasPrefix("-") else {
          throw CleanlyError.invalidArguments("\(argument) requires at least one extension.")
        }
        while index < arguments.count, !arguments[index].hasPrefix("-") {
          extensions.formUnion(splitList(arguments[index]).map(CategoryCatalog.normalizeExtension))
          index += 1
        }
        index -= 1
      case "--category", "-c":
        index += 1
        guard index < arguments.count, !arguments[index].hasPrefix("-") else {
          throw CleanlyError.invalidArguments("\(argument) requires at least one category.")
        }
        while index < arguments.count, !arguments[index].hasPrefix("-") {
          categories.formUnion(splitList(arguments[index]).map { $0.lowercased() })
          index += 1
        }
        index -= 1
      case "--permanent", "-p": permanent = true
      case "--yes", "-y": assumeYes = true
      case "--confirm-permanent":
        permanentToken = try stringValue(after: &index, in: arguments, option: argument)
      default:
        if argument.hasPrefix("-") {
          throw CleanlyError.invalidArguments("Unknown remove option: \(argument)")
        }
        positionals.append(argument)
      }
      index += 1
    }
    if let positionalPath = positionals.first { path = positionalPath }
    guard positionals.count <= 1 else {
      throw CleanlyError.invalidArguments("Remove accepts one directory path.")
    }
    guard !extensions.isEmpty || !categories.isEmpty else {
      throw CleanlyError.invalidArguments(
        "Choose files with --extension or --category. Run `cleanly help remove` for examples.")
    }
    let directory = try scanner.validatedDirectory(path, defaultPath: settings.defaultPath)
    try scanner.validateSafeMutationRoot(directory)
    let catalog = CategoryCatalog(settings: settings)
    let urls = try scanner.immediateEntries(
      in: directory,
      includeHidden: settings.includeHidden,
      excludedNames: Set(settings.excludedNames)
    ).filter { url in
      let values = try? url.resourceValues(forKeys: [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
      ])
      guard values?.isSymbolicLink != true, values?.isDirectory != true || values?.isPackage == true
      else { return false }
      let ext = CategoryCatalog.normalizeExtension(url.pathExtension)
      let category = catalog.category(for: url, isDirectory: false).lowercased()
      return extensions.contains(ext) || categories.contains(category)
    }

    write("Directory: \(directory.path)")
    write("Action: \(permanent ? "Permanent deletion" : "Move to Trash")")
    if urls.isEmpty {
      write("Result: No files matched.")
      return 0
    }
    write("Matches: \(urls.count)")
    for url in urls { write("File: \(url.lastPathComponent)") }

    let confirmed: Bool
    if permanent {
      confirmed =
        permanentToken == "DELETE" && assumeYes
        || confirm(
          label: "Permanent deletion confirmation",
          prompt:
            "Permanently delete \(urls.count) file\(urls.count == 1 ? "" : "s")? This cannot be undone.",
          token: "DELETE",
          assumeYes: false
        )
    } else {
      confirmed = confirm(
        label: "Trash confirmation",
        prompt: "Move \(urls.count) file\(urls.count == 1 ? "" : "s") to the Trash?",
        token: settings.confirmationLevel == .strict ? "TRASH" : nil, assumeYes: assumeYes)
    }
    guard confirmed else {
      write("Result: Cancelled. No files were changed.")
      return 2
    }

    let result = permanent ? fileOperator.permanentlyDelete(urls) : fileOperator.trash(urls)
    try saveOrRollback(
      result: result, command: permanent ? "remove-permanent" : "remove", settings: settings)
    write("Changed: \(result.entries.count) file\(result.entries.count == 1 ? "" : "s")")
    reportFailures(result.failures)
    write(
      permanent
        ? "Result: Selected files were permanently deleted."
        : "Result: Selected files are in the Trash and can be restored with `cleanly undo`.")
    return result.failures.isEmpty ? 0 : 1
  }

  private func runDuplicates(_ arguments: [String]) throws -> Int32 {
    let settings = try settingsStore.load()
    let options = try parseMaintenanceOptions(arguments, defaultPath: settings.defaultPath)
    let directory = try scanner.validatedDirectory(options.path, defaultPath: settings.defaultPath)
    let files = try scanner.recursiveFiles(
      in: directory, includeHidden: options.includeHidden ?? settings.includeHidden,
      excludedNames: Set(settings.excludedNames))
    let groups = try scanner.duplicateGroups(in: files)
    write("Directory: \(directory.path)")
    write("Mode: Duplicate scan")
    if groups.isEmpty {
      write("Result: No duplicate files were found.")
      return 0
    }
    var duplicates: [URL] = []
    for (offset, group) in groups.enumerated() {
      let sorted = group.sorted {
        if $0.modified != $1.modified { return $0.modified < $1.modified }
        return $0.url.path < $1.url.path
      }
      write("Duplicate group \(offset + 1): \(humanSize(sorted[0].size)) each")
      write("Keep: \(sorted[0].url.path)")
      for duplicate in sorted.dropFirst() {
        write("Duplicate: \(duplicate.url.path)")
        duplicates.append(duplicate.url)
      }
    }
    write(
      "Reclaimable: \(humanSize(duplicates.reduce(0) { total, url in total + (files.first { $0.url == url }?.size ?? 0) }))"
    )
    guard options.trash else {
      write("Result: Preview only. Add --trash to move duplicate copies to the Trash.")
      return 0
    }
    try scanner.validateSafeMutationRoot(directory)
    guard
      confirm(
        label: "Duplicate confirmation",
        prompt:
          "Keep the oldest copy in each group and move \(duplicates.count) duplicate\(duplicates.count == 1 ? "" : "s") to the Trash?",
        token: settings.confirmationLevel == .strict ? "TRASH" : nil, assumeYes: options.assumeYes)
    else {
      write("Result: Cancelled. No files were changed.")
      return 2
    }
    let result = fileOperator.trash(duplicates)
    try saveOrRollback(result: result, command: "duplicates", settings: settings)
    write("Trashed: \(result.entries.count) duplicate\(result.entries.count == 1 ? "" : "s")")
    reportFailures(result.failures)
    write("Result: Duplicate copies were moved to the Trash. Use `cleanly undo` to restore them.")
    return result.failures.isEmpty ? 0 : 1
  }

  private func runEmpty(_ arguments: [String]) throws -> Int32 {
    let settings = try settingsStore.load()
    let options = try parseMaintenanceOptions(arguments, defaultPath: settings.defaultPath)
    let directory = try scanner.validatedDirectory(options.path, defaultPath: settings.defaultPath)
    let directories = try scanner.emptyDirectories(
      in: directory, includeHidden: options.includeHidden ?? settings.includeHidden,
      excludedNames: Set(settings.excludedNames))
    write("Directory: \(directory.path)")
    write("Mode: Empty folder scan")
    if directories.isEmpty {
      write("Result: No empty folders were found.")
      return 0
    }
    write("Empty folders: \(directories.count)")
    for directory in directories { write("Folder: \(directory.path)") }
    guard options.trash else {
      write("Result: Preview only. Add --trash to move these folders to the Trash.")
      return 0
    }
    try scanner.validateSafeMutationRoot(directory)
    guard
      confirm(
        label: "Empty folder confirmation",
        prompt:
          "Move \(directories.count) empty folder\(directories.count == 1 ? "" : "s") to the Trash?",
        token: settings.confirmationLevel == .strict ? "TRASH" : nil, assumeYes: options.assumeYes)
    else {
      write("Result: Cancelled. No folders were changed.")
      return 2
    }
    let result = fileOperator.trash(directories)
    try saveOrRollback(result: result, command: "empty", settings: settings)
    write("Trashed: \(result.entries.count) folder\(result.entries.count == 1 ? "" : "s")")
    reportFailures(result.failures)
    write("Result: Empty folders were moved to the Trash. Use `cleanly undo` to restore them.")
    return result.failures.isEmpty ? 0 : 1
  }

  private enum ReportKind { case large, old }

  private func runFileReport(_ arguments: [String], kind: ReportKind) throws -> Int32 {
    let settings = try settingsStore.load()
    let options = try parseMaintenanceOptions(
      arguments, defaultPath: settings.defaultPath,
      acceptedThreshold: kind == .large ? "--size" : "--days")
    let threshold =
      options.threshold ?? (kind == .large ? settings.largeFileMB : settings.oldFileDays)
    let directory = try scanner.validatedDirectory(options.path, defaultPath: settings.defaultPath)
    let files = try scanner.recursiveFiles(
      in: directory, includeHidden: options.includeHidden ?? settings.includeHidden,
      excludedNames: Set(settings.excludedNames))
    let matches: [FileRecord]
    let title: String
    if kind == .large {
      let bytes = Int64(threshold) * 1_048_576
      matches = files.filter { $0.size >= bytes }.sorted { $0.size > $1.size }
      title = "Files at least \(threshold) MB"
    } else {
      let cutoff = Calendar.current.date(byAdding: .day, value: -threshold, to: Date()) ?? Date()
      matches = files.filter { $0.modified < cutoff }.sorted { $0.modified < $1.modified }
      title = "Files not modified in \(threshold) days"
    }
    write("Directory: \(directory.path)")
    write("Mode: \(title)")
    if matches.isEmpty {
      write("Result: No matching files were found.")
      return 0
    }
    write("Matches: \(matches.count)")
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .medium
    for file in matches {
      write(
        "File: \(humanSize(file.size)) | \(dateFormatter.string(from: file.modified)) | \(file.url.path)"
      )
    }
    guard options.trash else {
      write("Result: Preview only. Add --trash to move these files to the Trash.")
      return 0
    }
    try scanner.validateSafeMutationRoot(directory)
    guard
      confirm(
        label: "File cleanup confirmation",
        prompt:
          "Move all \(matches.count) matching file\(matches.count == 1 ? "" : "s") to the Trash?",
        token: settings.confirmationLevel == .strict ? "TRASH" : nil, assumeYes: options.assumeYes)
    else {
      write("Result: Cancelled. No files were changed.")
      return 2
    }
    let result = fileOperator.trash(matches.map(\.url))
    try saveOrRollback(
      result: result, command: kind == .large ? "large" : "old", settings: settings)
    write("Trashed: \(result.entries.count) file\(result.entries.count == 1 ? "" : "s")")
    reportFailures(result.failures)
    write("Result: Matching files were moved to the Trash. Use `cleanly undo` to restore them.")
    return result.failures.isEmpty ? 0 : 1
  }

  private func runSettings(_ arguments: [String]) throws -> Int32 {
    var settings = try settingsStore.load()
    let action = arguments.first ?? "show"
    let rest = Array(arguments.dropFirst())
    switch action {
    case "show":
      guard rest.isEmpty else {
        throw CleanlyError.invalidArguments("Usage: cleanly settings show")
      }
      printSettings(settings)
    case "path":
      guard rest.isEmpty else {
        throw CleanlyError.invalidArguments("Usage: cleanly settings path")
      }
      write("Settings file: \(settingsStore.fileURL.path)")
    case "get":
      guard rest.count == 1 else {
        throw CleanlyError.invalidArguments("Usage: cleanly settings get KEY")
      }
      write("\(rest[0]): \(try settingValue(rest[0], settings: settings))")
    case "set":
      guard rest.count >= 2 else {
        throw CleanlyError.invalidArguments("Usage: cleanly settings set KEY VALUE")
      }
      try setSetting(
        key: rest[0], value: rest.dropFirst().joined(separator: " "), settings: &settings)
      try settingsStore.save(settings)
      write("Updated: \(rest[0]) = \(try settingValue(rest[0], settings: settings))")
    case "reset":
      let assumeYes = rest == ["--yes"] || rest == ["-y"]
      guard rest.isEmpty || assumeYes else {
        throw CleanlyError.invalidArguments("Usage: cleanly settings reset [--yes]")
      }
      guard
        confirm(
          label: "Settings confirmation",
          prompt: "Reset every setting and custom category to its default?", token: "RESET",
          assumeYes: assumeYes)
      else {
        write("Result: Cancelled. Settings were not changed.")
        return 2
      }
      settings = try settingsStore.reset()
      write("Result: Settings were reset to defaults.")
    case "category":
      try updateCategory(arguments: rest, settings: &settings)
    case "tips":
      guard rest.count == 1, ["on", "off"].contains(rest[0].lowercased()) else {
        throw CleanlyError.invalidArguments("Usage: cleanly settings tips on|off")
      }
      settings.tipsEnabled = rest[0].lowercased() == "on"
      try settingsStore.save(settings)
      write("Updated: tips.enabled = \(settings.tipsEnabled)")
    default:
      throw CleanlyError.invalidArguments(
        "Unknown settings action: \(action). Run `cleanly help settings`.")
    }
    return 0
  }

  private func runUpdate(_ arguments: [String]) throws -> Int32 {
    guard arguments.isEmpty else { throw CleanlyError.invalidArguments("Usage: cleanly update") }
    let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    guard let brew = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    else {
      throw CleanlyError.operation(
        "Homebrew was not found. Install cleanly again from https://brew.sh or update the manual checkout with Git."
      )
    }
    write("Update: Running Homebrew upgrade for thecatthatflies/tap/cleanly.")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: brew)
    process.arguments = ["upgrade", "thecatthatflies/tap/cleanly"]
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw CleanlyError.operation(
        "Homebrew update failed with status \(process.terminationStatus).")
    }
    write("Result: cleanly is up to date.")
    return 0
  }
}

private struct MaintenanceOptions {
  var path: String
  var trash = false
  var assumeYes = false
  var includeHidden: Bool?
  var threshold: Int?
}

extension CleanlyApplication {
  fileprivate func parseCleanOptions(_ arguments: [String], defaultPath: String) throws
    -> CleanOptions
  {
    var options = CleanOptions(path: defaultPath)
    var paths: [String] = []
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--category", "-c":
        let value = try stringValue(after: &index, in: arguments, option: argument)
        options.categories.formUnion(splitList(value).map { $0.lowercased() })
      case "--include-hidden": options.includeHidden = true
      case "--exclude-hidden": options.includeHidden = false
      case "--folders": options.organizeFolders = true
      case "--no-folders": options.organizeFolders = false
      case "--yes", "-y": options.assumeYes = true
      case "--no-clean":
        write("Notice: --no-clean is deprecated. Swift cleanly always verifies completed moves.")
      default:
        if argument.hasPrefix("-") {
          throw CleanlyError.invalidArguments("Unknown clean option: \(argument)")
        }
        paths.append(argument)
      }
      index += 1
    }
    guard paths.count <= 1 else {
      throw CleanlyError.invalidArguments("Clean accepts one directory path.")
    }
    if let path = paths.first { options.path = path }
    return options
  }

  fileprivate func parseMaintenanceOptions(
    _ arguments: [String],
    defaultPath: String,
    acceptedThreshold: String? = nil
  ) throws -> MaintenanceOptions {
    var options = MaintenanceOptions(path: defaultPath)
    var paths: [String] = []
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--trash": options.trash = true
      case "--yes", "-y": options.assumeYes = true
      case "--include-hidden": options.includeHidden = true
      case "--exclude-hidden": options.includeHidden = false
      case acceptedThreshold:
        options.threshold = try integerValue(
          after: &index, in: arguments, option: argument, minimum: 1)
      default:
        if argument.hasPrefix("-") {
          throw CleanlyError.invalidArguments("Unknown option: \(argument)")
        }
        paths.append(argument)
      }
      index += 1
    }
    guard paths.count <= 1 else {
      throw CleanlyError.invalidArguments("This command accepts one directory path.")
    }
    if let path = paths.first { options.path = path }
    return options
  }

  fileprivate func saveOrRollback(
    result: OperationResult, command: String, settings: CleanlySettings
  ) throws {
    guard !result.entries.isEmpty else { return }
    do {
      try historyStore.append(
        entries: result.entries, command: command, limit: settings.historyLimit)
    } catch {
      if !result.entries.contains(where: \.isPermanent) { fileOperator.rollback(result.entries) }
      throw error
    }
  }

  fileprivate func confirm(label: String, prompt: String, token: String?, assumeYes: Bool) -> Bool {
    if assumeYes {
      write("Confirmation: \(label) accepted by --yes.")
      return true
    }
    if let token {
      write("Confirmation: \(prompt)")
      write("Type \(token) to continue:")
      return read()?.trimmingCharacters(in: .whitespacesAndNewlines) == token
    }
    write("Confirmation: \(prompt) [y/N]")
    guard let answer = read()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
      return false
    }
    return answer == "y" || answer == "yes"
  }

  fileprivate func reportFailures(_ failures: [String]) {
    guard !failures.isEmpty else { return }
    write("Failures: \(failures.count)")
    for failure in failures { write("Failed: \(failure)") }
  }

  fileprivate func finishClean(settings: CleanlySettings, moved: Int) {
    write("Result: Clean complete. \(moved) item\(moved == 1 ? "" : "s") moved.")
    write("undo that movement using `cleanly undo`")
    guard settings.tipsEnabled else { return }
    let tips = [
      "Run `cleanly preview PATH` whenever you want to inspect a sort without changing anything.",
      "Use `cleanly settings category add NAME EXTENSIONS` to create a category that matches your workflow.",
      "Use `cleanly duplicates PATH` to compare file contents and find exact duplicate copies.",
      "Use `cleanly empty PATH` to find empty folder trees before moving them to the Trash.",
      "Use `cleanly large PATH --size 1000` to review files that use at least one gigabyte.",
      "Use `cleanly old PATH --days 180` to review files you have not modified in six months.",
      "Add `--category Images,Documents` when you only want to organize selected categories.",
      "Add `--include-hidden` for a single scan without changing your hidden-file setting.",
      "Use `cleanly history` to see which recorded operation `cleanly undo` will reverse.",
      "Set strict confirmations with `cleanly settings set confirmations strict`.",
      "Use `cleanly settings set collisions skip` if duplicate names should stay in place.",
      "Use `cleanly settings set clean.organize-folders true` only when you want loose folders placed in Folders.",
      "Files moved to the macOS Trash stay recoverable until the Trash is emptied.",
      "Permanent removal always requires the word DELETE, even when other confirmations are automated.",
      "Disable these tips with `cleanly settings set tips.enabled false`.",
    ]
    let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
    write("Tip: \(tips[(day + moved) % tips.count])")
  }

  fileprivate func printSettings(_ settings: CleanlySettings) {
    write("Settings file: \(settingsStore.fileURL.path)")
    write("tips.enabled: \(settings.tipsEnabled)")
    write("confirmations: \(settings.confirmationLevel.rawValue)")
    write("clean.include-hidden: \(settings.includeHidden)")
    write("clean.organize-folders: \(settings.organizeFolders)")
    write("collisions: \(settings.collisionStrategy.rawValue)")
    write("thresholds.old-days: \(settings.oldFileDays)")
    write("thresholds.large-mb: \(settings.largeFileMB)")
    write("history.limit: \(settings.historyLimit)")
    write("default.path: \(settings.defaultPath)")
    write("exclusions: \(settings.excludedNames.joined(separator: ","))")
    write("disabled-categories: \(settings.disabledCategories.joined(separator: ","))")
    if settings.customCategories.isEmpty {
      write("custom-categories: none")
    } else {
      for name in settings.customCategories.keys.sorted() {
        write(
          "custom-category: \(name) = \(settings.customCategories[name, default: []].joined(separator: ","))"
        )
      }
    }
  }

  fileprivate func settingValue(_ key: String, settings: CleanlySettings) throws -> String {
    switch key.lowercased() {
    case "tips.enabled": return String(settings.tipsEnabled)
    case "confirmations": return settings.confirmationLevel.rawValue
    case "clean.include-hidden": return String(settings.includeHidden)
    case "clean.organize-folders": return String(settings.organizeFolders)
    case "collisions": return settings.collisionStrategy.rawValue
    case "thresholds.old-days": return String(settings.oldFileDays)
    case "thresholds.large-mb": return String(settings.largeFileMB)
    case "history.limit": return String(settings.historyLimit)
    case "default.path": return settings.defaultPath
    case "exclusions": return settings.excludedNames.joined(separator: ",")
    case "disabled-categories": return settings.disabledCategories.joined(separator: ",")
    default:
      throw CleanlyError.settings(
        "Unknown setting: \(key). Run `cleanly settings show` for valid keys.")
    }
  }

  fileprivate func setSetting(key: String, value: String, settings: inout CleanlySettings) throws {
    switch key.lowercased() {
    case "tips.enabled": settings.tipsEnabled = try boolean(value, key: key)
    case "confirmations":
      guard let level = ConfirmationLevel(rawValue: value.lowercased()) else {
        throw CleanlyError.settings("confirmations must be standard or strict.")
      }
      settings.confirmationLevel = level
    case "clean.include-hidden": settings.includeHidden = try boolean(value, key: key)
    case "clean.organize-folders": settings.organizeFolders = try boolean(value, key: key)
    case "collisions":
      guard let strategy = CollisionStrategy(rawValue: value.lowercased()) else {
        throw CleanlyError.settings("collisions must be rename or skip.")
      }
      settings.collisionStrategy = strategy
    case "thresholds.old-days": settings.oldFileDays = try positiveInteger(value, key: key)
    case "thresholds.large-mb": settings.largeFileMB = try positiveInteger(value, key: key)
    case "history.limit": settings.historyLimit = try positiveInteger(value, key: key)
    case "default.path":
      _ = try scanner.validatedDirectory(value)
      settings.defaultPath = value
    case "exclusions": settings.excludedNames = splitList(value)
    case "disabled-categories": settings.disabledCategories = splitList(value)
    default:
      throw CleanlyError.settings(
        "Unknown setting: \(key). Run `cleanly settings show` for valid keys.")
    }
  }

  fileprivate func updateCategory(arguments: [String], settings: inout CleanlySettings) throws {
    guard let action = arguments.first else {
      throw CleanlyError.invalidArguments(
        "Usage: cleanly settings category add|remove|disable|enable|list ...")
    }
    let rest = Array(arguments.dropFirst())
    switch action {
    case "list":
      guard rest.isEmpty else {
        throw CleanlyError.invalidArguments("Usage: cleanly settings category list")
      }
      let catalog = CategoryCatalog(settings: settings)
      for name in catalog.categories.keys.sorted() {
        let marker = settings.customCategories[name] == nil ? "built-in" : "custom"
        write(
          "Category: \(name) | \(marker) | \(catalog.categories[name, default: []].joined(separator: ","))"
        )
      }
      return
    case "add":
      guard rest.count >= 2 else {
        throw CleanlyError.invalidArguments(
          "Usage: cleanly settings category add NAME EXTENSION...")
      }
      let name = rest[0].trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty, name != ".", name != "..", !name.hasPrefix("."), !name.contains("/")
      else { throw CleanlyError.settings("Category name must be a visible, safe folder name.") }
      let values = rest.dropFirst().flatMap(splitList).map(CategoryCatalog.normalizeExtension)
        .filter { !$0.isEmpty }
      guard !values.isEmpty else { throw CleanlyError.settings("Provide at least one extension.") }
      settings.customCategories[name] = Array(Set(values)).sorted()
      settings.disabledCategories.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
      try settingsStore.save(settings)
      write(
        "Updated category: \(name) = \(settings.customCategories[name, default: []].joined(separator: ","))"
      )
    case "remove":
      guard rest.count == 1 else {
        throw CleanlyError.invalidArguments("Usage: cleanly settings category remove NAME")
      }
      guard settings.customCategories.removeValue(forKey: rest[0]) != nil else {
        throw CleanlyError.settings("Custom category not found: \(rest[0])")
      }
      try settingsStore.save(settings)
      write("Removed custom category: \(rest[0])")
    case "disable":
      guard rest.count == 1 else {
        throw CleanlyError.invalidArguments("Usage: cleanly settings category disable NAME")
      }
      if !settings.disabledCategories.contains(where: {
        $0.caseInsensitiveCompare(rest[0]) == .orderedSame
      }) {
        settings.disabledCategories.append(rest[0])
      }
      try settingsStore.save(settings)
      write("Disabled category: \(rest[0])")
    case "enable":
      guard rest.count == 1 else {
        throw CleanlyError.invalidArguments("Usage: cleanly settings category enable NAME")
      }
      settings.disabledCategories.removeAll { $0.caseInsensitiveCompare(rest[0]) == .orderedSame }
      try settingsStore.save(settings)
      write("Enabled category: \(rest[0])")
    default: throw CleanlyError.invalidArguments("Unknown category action: \(action)")
    }
  }

  fileprivate func stringValue(after index: inout Int, in arguments: [String], option: String)
    throws -> String
  {
    index += 1
    guard index < arguments.count else {
      throw CleanlyError.invalidArguments("\(option) requires a value.")
    }
    return arguments[index]
  }

  fileprivate func integerValue(
    after index: inout Int, in arguments: [String], option: String, minimum: Int
  ) throws -> Int {
    let string = try stringValue(after: &index, in: arguments, option: option)
    guard let value = Int(string), value >= minimum else {
      throw CleanlyError.invalidArguments("\(option) requires a number of at least \(minimum).")
    }
    return value
  }

  fileprivate func splitList(_ value: String) -> [String] {
    value.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init).filter { !$0.isEmpty }
  }

  fileprivate func boolean(_ value: String, key: String) throws -> Bool {
    switch value.lowercased() {
    case "true", "on", "yes", "1": return true
    case "false", "off", "no", "0": return false
    default: throw CleanlyError.settings("\(key) requires true or false.")
    }
  }

  fileprivate func positiveInteger(_ value: String, key: String) throws -> Int {
    guard let number = Int(value), number > 0 else {
      throw CleanlyError.settings("\(key) requires a positive whole number.")
    }
    return number
  }

  fileprivate func relativeDestination(_ path: String, root: URL) -> String {
    let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
    return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
  }

  fileprivate func humanSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }

  fileprivate func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  fileprivate func editDistance(_ lhs: String, _ rhs: String) -> Int {
    let left = Array(lhs.lowercased())
    let right = Array(rhs.lowercased())
    var previous = Array(0...right.count)
    for (leftIndex, leftCharacter) in left.enumerated() {
      var current = [leftIndex + 1]
      for (rightIndex, rightCharacter) in right.enumerated() {
        current.append(
          min(
            current[rightIndex] + 1,
            previous[rightIndex + 1] + 1,
            previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
          ))
      }
      previous = current
    }
    return previous[right.count]
  }
}

extension CleanlyApplication {
  fileprivate static let generalHelp = """
    cleanly v\(version) — safely organize and clean folders on macOS

    USAGE
      cleanly clean [PATH] [OPTIONS]       Preview, confirm, and organize a folder
      cleanly preview [PATH] [OPTIONS]     Show the exact organization plan
      cleanly undo                         Reverse the latest recoverable operation
      cleanly history [--limit NUMBER]     Show recorded operations
      cleanly remove [PATH] SELECTOR       Trash or permanently delete matching files
      cleanly duplicates [PATH] [--trash]  Find exact duplicate file contents
      cleanly empty [PATH] [--trash]       Find empty folders
      cleanly large [PATH] [--size MB]     Find large files
      cleanly old [PATH] [--days DAYS]     Find old files
      cleanly settings [ACTION]            View and edit cleaning behavior
      cleanly update                       Upgrade with Homebrew
      cleanly version                      Print the installed version

    SAFE DEFAULTS
      Cleaning displays every planned move and asks before changing files.
      Removal uses the macOS Trash unless --permanent is explicit.
      Protected system and home roots cannot be changed.
      Existing files are never overwritten; collisions receive numbered names.
      Symlinks, hidden files, and loose folders are skipped by default.

    COMMON OPTIONS
      -c, --category LIST       Organize selected categories only
      --include-hidden          Include hidden files for this command
      --folders                 Organize loose folders into Folders
      -y, --yes                 Accept recoverable move or Trash confirmations
      -h, --help                Show command-specific help

    EXAMPLES
      cleanly preview ~/Downloads
      cleanly clean ~/Downloads
      cleanly ~/Downloads -c Images,Documents
      cleanly duplicates ~/Downloads --trash
      cleanly settings set tips.enabled false
      cleanly help settings

    Run `cleanly help COMMAND` for detailed command options.
    """

  fileprivate static func help(for command: String?) -> String {
    switch command {
    case nil: return generalHelp
    case "clean", "preview":
      return """
        cleanly \(command!) — \(command == "clean" ? "organize a folder after confirmation" : "show an organization plan without changing files")

        USAGE
          cleanly \(command!) [PATH] [OPTIONS]

        OPTIONS
          -c, --category LIST   Include categories such as Images,Documents
          --include-hidden      Include hidden entries
          --exclude-hidden      Exclude hidden entries
          --folders             Put loose folders in Folders
          --no-folders          Leave loose folders in place
          -y, --yes             Accept the move confirmation
          -h, --help            Show this help

        DETAILS
          Only immediate children are organized. Packages such as .app bundles remain intact.
          Compound extensions such as .tar.gz are recognized. Existing category folders are skipped.
        """
    case "remove":
      return """
        cleanly remove — remove selected files safely

        USAGE
          cleanly remove [PATH] --extension LIST [--trash options]
          cleanly remove [PATH] --category LIST [--trash options]

        OPTIONS
          -f, --extension LIST          Match extensions without leading dots
          -c, --category LIST           Match category names
          -p, --permanent               Delete instead of using the Trash
          --confirm-permanent DELETE    Required with --yes for scripted permanent deletion
          -y, --yes                     Accept a Trash confirmation

        Permanent deletion always requires DELETE interactively, or both --yes and
        --confirm-permanent DELETE. Permanently deleted files cannot be undone.
        """
    case "duplicates":
      return """
        cleanly duplicates — find exact duplicate files recursively

        USAGE
          cleanly duplicates [PATH] [--trash] [--include-hidden] [--yes]

        Files are grouped by size and SHA-256 content. The oldest path-stable copy is kept.
        Without --trash this command is a read-only report.
        """
    case "empty":
      return """
        cleanly empty — find empty folders recursively

        USAGE
          cleanly empty [PATH] [--trash] [--include-hidden] [--yes]

        Without --trash this command is a read-only report. macOS packages and symlinks are skipped.
        """
    case "large":
      return """
        cleanly large — find large files recursively

        USAGE
          cleanly large [PATH] [--size MB] [--trash] [--include-hidden] [--yes]

        The default threshold comes from thresholds.large-mb. Without --trash no files change.
        """
    case "old":
      return """
        cleanly old — find files not modified recently

        USAGE
          cleanly old [PATH] [--days DAYS] [--trash] [--include-hidden] [--yes]

        The default threshold comes from thresholds.old-days. Without --trash no files change.
        """
    case "settings":
      return """
        cleanly settings — inspect and customize cleanly

        USAGE
          cleanly settings show
          cleanly settings path
          cleanly settings get KEY
          cleanly settings set KEY VALUE
          cleanly settings reset [--yes]
          cleanly settings tips on|off
          cleanly settings category list
          cleanly settings category add NAME EXTENSION...
          cleanly settings category remove NAME
          cleanly settings category disable NAME
          cleanly settings category enable NAME

        KEYS
          tips.enabled                 true or false
          confirmations                standard or strict
          clean.include-hidden         true or false
          clean.organize-folders       true or false
          collisions                   rename or skip
          thresholds.old-days          positive number
          thresholds.large-mb          positive number
          history.limit                positive number
          default.path                 existing directory
          exclusions                   comma-separated names
          disabled-categories          comma-separated category names

        EXAMPLES
          cleanly settings set tips.enabled false
          cleanly settings set confirmations strict
          cleanly settings category add Screenshots png,jpg
        """
    case "undo":
      return
        "cleanly undo — reverse the latest recorded recoverable operation\n\nUSAGE\n  cleanly undo"
    case "history":
      return
        "cleanly history — list recorded operations\n\nUSAGE\n  cleanly history [--limit NUMBER]"
    case "update":
      return "cleanly update — upgrade the Homebrew installation\n\nUSAGE\n  cleanly update"
    case "version":
      return
        "cleanly version — print the installed version\n\nUSAGE\n  cleanly version\n  cleanly --version\n  cleanly -v"
    default: return "Unknown help topic: \(command!).\n\n\(generalHelp)"
    }
  }
}
