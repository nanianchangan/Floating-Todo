// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FloatingTodo",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "FloatingTodo",
            path: "Sources/FloatingTodo",
            // 现有代码按 Swift 5 语义编写，先不引入严格并发检查
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FloatingTodoTests",
            dependencies: ["FloatingTodo"],
            path: "Tests/FloatingTodoTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
