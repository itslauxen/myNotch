// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "myNotch",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "Excecoes", path: "Sources/Excecoes"),
        .executableTarget(name: "myNotch", dependencies: ["Excecoes"], path: "Sources/myNotch")
    ]
)
