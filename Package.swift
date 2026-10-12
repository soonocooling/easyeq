// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EasyEq",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FormulaCore", targets: ["FormulaCore"]),
    ],
    targets: [
        .target(name: "FormulaCore"),
        .executableTarget(name: "EasyEqSpike", dependencies: ["FormulaCore"]),
        .testTarget(name: "FormulaCoreTests", dependencies: ["FormulaCore"]),
    ]
)
