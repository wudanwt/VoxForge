// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TypeMore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TypeMore", targets: ["TypeMore"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "TypeMore",
            dependencies: [
                "CSherpaShim",
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ],
            path: "Sources/TypeMore",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("Speech")
            ]
        ),
        .target(
            name: "CSherpaShim",
            path: "Sources/CSherpaShim",
            publicHeadersPath: "include",
            cSettings: [
                .define("_DARWIN_C_SOURCE")
            ]
        ),
        .testTarget(
            name: "TypeMoreTests",
            dependencies: ["TypeMore"],
            path: "Tests/TypeMoreTests"
        )
    ]
)
