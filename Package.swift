// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EasyEq",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FormulaCore", targets: ["FormulaCore"]),
        .executable(name: "EasyEq", targets: ["EasyEq"]),
    ],
    targets: [
        .target(name: "FormulaCore"),
        .executableTarget(name: "EasyEq", dependencies: ["FormulaCore"]),
        .testTarget(name: "FormulaCoreTests", dependencies: ["FormulaCore"]),
    ]
)
