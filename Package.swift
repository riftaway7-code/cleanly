// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "cleanly",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "cleanly", targets: ["CleanlyCLI"])
  ],
  targets: [
    .target(name: "CleanlyCore"),
    .executableTarget(name: "CleanlyCLI", dependencies: ["CleanlyCore"]),
    .testTarget(name: "CleanlyCoreTests", dependencies: ["CleanlyCore"]),
  ],
  swiftLanguageVersions: [.v5]
)
