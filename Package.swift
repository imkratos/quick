// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "GlassSwitch", platforms: [.macOS(.v26)], targets: [.executableTarget(name: "GlassSwitch", path: "Sources", swiftSettings: [.swiftLanguageMode(.v5)])])
