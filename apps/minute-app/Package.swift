// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MinuteApp",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    .library(
      name: "MinuteAppAdapter",
      targets: ["MinuteAppAdapter"]
    ),
    .executable(
      name: "minute-app",
      targets: ["MinuteAppCLI"]
    ),
  ],
  dependencies: [
    .package(path: "../../mac/controller-core"),
  ],
  targets: [
    .target(
      name: "MinuteAppAdapter",
      dependencies: [
        .product(name: "FieldAppControllerCore", package: "controller-core"),
      ]
    ),
    .executableTarget(
      name: "MinuteAppCLI",
      dependencies: [
        "MinuteAppAdapter",
        .product(name: "FieldAppControllerCore", package: "controller-core"),
      ]
    ),
    .testTarget(
      name: "MinuteAppAdapterTests",
      dependencies: [
        "MinuteAppAdapter",
        .product(name: "FieldAppControllerCore", package: "controller-core"),
      ]
    ),
  ]
)
