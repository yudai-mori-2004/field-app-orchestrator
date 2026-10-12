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
  ],
  targets: [
    .target(name: "FieldAppControllerCore"),
    .testTarget(
      name: "FieldAppControllerCoreTests",
      dependencies: ["FieldAppControllerCore"]
    ),
  ]
)
