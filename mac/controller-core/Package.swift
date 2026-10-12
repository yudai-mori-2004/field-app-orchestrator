// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "FieldAppControllerCore",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    .library(
      name: "FieldAppControllerCore",
      targets: ["FieldAppControllerCore"]
    ),
    .executable(
      name: "field-app",
      targets: ["FieldAppCLI"]
    ),
  ],
  targets: [
    .target(name: "FieldAppControllerCore"),
    .executableTarget(
      name: "FieldAppCLI",
      dependencies: ["FieldAppControllerCore"]
    ),
    .testTarget(
      name: "FieldAppControllerCoreTests",
      dependencies: ["FieldAppControllerCore"]
    ),
  ]
)
