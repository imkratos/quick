// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "GlassSwitch", platforms: [.macOS(.v26)], dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")], targets: [.executableTarget(name: "GlassSwitch", dependencies: [.product(name: "Sparkle", package: "Sparkle")], path: "Sources", swiftSettings: [.swiftLanguageMode(.v5)], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])])])
