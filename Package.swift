import PackageDescription

let package = Package(
    name: "FilesProvider",
    products: [
        .library(name: "FilesProvider",  targets: ["FilesProvider"])
    ],
    dependencies: [],
    targets: [
        .target(name: "FilesProvider", path: "Sources")
    ]
)
