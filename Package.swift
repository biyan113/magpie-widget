// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MagpieCore", platforms: [.macOS(.v14)], products: [.library(name: "MagpieCore", targets: ["MagpieCore"])], targets: [.target(name: "MagpieCore", path: "Shared", exclude: ["Components.swift"]), .testTarget(name: "MagpieCoreTests", dependencies: ["MagpieCore"], path: "Tests")])
