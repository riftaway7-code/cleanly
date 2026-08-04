import Foundation
import XCTest

@testable import CleanlyCore

final class CleanlyCoreTests: XCTestCase {
  func testCategorization() {
    let catalog = CategoryCatalog(settings: CleanlySettings())
    XCTAssertEqual(
      catalog.category(for: URL(fileURLWithPath: "/tmp/photo.HEIC"), isDirectory: false), "Images")
    XCTAssertEqual(
      catalog.category(for: URL(fileURLWithPath: "/tmp/archive.tar.gz"), isDirectory: false),
      "Archives")
    XCTAssertEqual(
      catalog.category(for: URL(fileURLWithPath: "/tmp/main.swift"), isDirectory: false), "Code")
    XCTAssertEqual(
      catalog.category(for: URL(fileURLWithPath: "/tmp/novel.epub"), isDirectory: false), "Books")
    XCTAssertEqual(
      catalog.category(for: URL(fileURLWithPath: "/tmp/installer.dmg"), isDirectory: false),
      "Disk Images")
    XCTAssertEqual(
      catalog.category(for: URL(fileURLWithPath: "/tmp/unknown.cleanlytest"), isDirectory: false),
      "Other")
  }

  func testCustomCategory() {
    var settings = CleanlySettings()
    settings.customCategories["Screenshots"] = ["png"]
    let catalog = CategoryCatalog(settings: settings)
    XCTAssertEqual(
      catalog.category(for: URL(fileURLWithPath: "/tmp/capture.png"), isDirectory: false),
      "Screenshots")
  }

  func testSettingsPersistence() throws {
    let temporary = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporary) }
    let store = SettingsStore(paths: CleanlyPaths(base: temporary))
    var settings = try store.load()
    settings.tipsEnabled = false
    settings.oldFileDays = 45
    try store.save(settings)
    XCTAssertFalse(try store.load().tipsEnabled)
    XCTAssertEqual(try store.load().oldFileDays, 45)
    XCTAssertEqual(try store.reset(), CleanlySettings())
  }

  func testCollisionRename() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("new".utf8).write(to: root.appendingPathComponent("photo.jpg"))
    let images = root.appendingPathComponent("Images", isDirectory: true)
    try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: images.appendingPathComponent("photo.jpg"))

    let settings = CleanlySettings()
    let moves = try FileOperator().cleanPlan(
      directory: root,
      options: CleanOptions(path: root.path),
      settings: settings,
      catalog: CategoryCatalog(settings: settings)
    )
    XCTAssertEqual(moves.count, 1)
    XCTAssertEqual(moves[0].destination.lastPathComponent, "photo 2.jpg")
  }

  func testCleanAndUndo() throws {
    let root = try temporaryDirectory()
    let state = try temporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: state)
    }
    try Data("image".utf8).write(to: root.appendingPathComponent("photo.png"))
    let paths = CleanlyPaths(base: state)
    let settingsStore = SettingsStore(paths: paths)
    let historyStore = HistoryStore(paths: paths)
    var output: [String] = []
    let app = CleanlyApplication(
      settingsStore: settingsStore,
      historyStore: historyStore,
      write: { output.append($0) },
      read: { nil }
    )

    XCTAssertEqual(app.run(["clean", root.path, "--yes"]), 0)
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: root.appendingPathComponent("Images/photo.png").path))
    XCTAssertTrue(output.contains("undo that movement using `cleanly undo`"))
    XCTAssertEqual(try historyStore.read().count, 1)
    XCTAssertEqual(app.run(["undo"]), 0)
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: root.appendingPathComponent("photo.png").path))
  }

  func testProtectedRoots() {
    XCTAssertThrowsError(
      try FileScanner().validateSafeMutationRoot(URL(fileURLWithPath: "/"))
    )
  }

  func testEmptyTrees() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let nested = root.appendingPathComponent("one/two/three", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    let result = try FileScanner().emptyDirectories(
      in: root, includeHidden: false, excludedNames: [])
    XCTAssertEqual(result.map(\.lastPathComponent), ["one"])
  }

  func testPreviewOnly() throws {
    let root = try temporaryDirectory()
    let state = try temporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: state)
    }
    try Data("document".utf8).write(to: root.appendingPathComponent("notes.pdf"))
    let paths = CleanlyPaths(base: state)
    var output: [String] = []
    let app = CleanlyApplication(
      settingsStore: SettingsStore(paths: paths),
      historyStore: HistoryStore(paths: paths),
      write: { output.append($0) }
    )
    XCTAssertEqual(app.run(["preview", root.path]), 0)
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: root.appendingPathComponent("notes.pdf").path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: root.appendingPathComponent("Documents").path))
    XCTAssertTrue(output.contains(where: { $0.contains("Preview only") }))
  }

  func testTipsDisabled() throws {
    let root = try temporaryDirectory()
    let state = try temporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: state)
    }
    try Data("audio".utf8).write(to: root.appendingPathComponent("track.mp3"))
    let paths = CleanlyPaths(base: state)
    let settingsStore = SettingsStore(paths: paths)
    var settings = try settingsStore.load()
    settings.tipsEnabled = false
    try settingsStore.save(settings)
    var output: [String] = []
    let app = CleanlyApplication(
      settingsStore: settingsStore,
      historyStore: HistoryStore(paths: paths),
      write: { output.append($0) }
    )
    XCTAssertEqual(app.run(["clean", root.path, "--yes"]), 0)
    XCTAssertTrue(output.contains("undo that movement using `cleanly undo`"))
    XCTAssertFalse(output.contains(where: { $0.hasPrefix("Tip:") }))
  }

  func testApplicationPackage() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let app = root.appendingPathComponent("Example.app", isDirectory: true)
    try FileManager.default.createDirectory(
      at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    let settings = CleanlySettings()
    let moves = try FileOperator().cleanPlan(
      directory: root,
      options: CleanOptions(path: root.path),
      settings: settings,
      catalog: CategoryCatalog(settings: settings)
    )
    XCTAssertEqual(moves.count, 1)
    XCTAssertEqual(moves[0].category, "Applications")
    XCTAssertEqual(moves[0].source.lastPathComponent, "Example.app")
  }

  func testLegacyHistory() throws {
    let state = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: state) }
    let paths = CleanlyPaths(base: state)
    try FileManager.default.createDirectory(
      at: paths.history.deletingLastPathComponent(), withIntermediateDirectories: true)
    let json = """
      [{"time":"2025-01-01T00:00:00Z","entries":[{"from":"/tmp/a","to":"/tmp/b"}]}]
      """
    try Data(json.utf8).write(to: paths.history)
    let runs = try HistoryStore(paths: paths).read()
    XCTAssertEqual(runs.count, 1)
    XCTAssertNil(runs[0].command)
    XCTAssertNil(runs[0].entries[0].action)
  }

  func testDuplicateContents() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("same".utf8).write(to: root.appendingPathComponent("a.txt"))
    try Data("same".utf8).write(to: root.appendingPathComponent("b.txt"))
    try Data().write(to: root.appendingPathComponent("empty-one"))
    try Data().write(to: root.appendingPathComponent("empty-two"))
    let scanner = FileScanner()
    let files = try scanner.recursiveFiles(in: root, includeHidden: false, excludedNames: [])
    let groups = try scanner.duplicateGroups(in: files)
    XCTAssertEqual(groups.count, 2)
    XCTAssertTrue(groups.allSatisfy { $0.count == 2 })
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "cleanly-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
