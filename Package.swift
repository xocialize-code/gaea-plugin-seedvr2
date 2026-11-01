// swift-tools-version: 6.2
import PackageDescription

// gaea-plugin-seedvr2: ByteDance-Seed's SeedVR2-3B (Apache-2.0 weights) as a Gaea plugin on MES Video 0.1's
// video.upscale. One worker executable built on GaeaPluginKit over mlx-seedvr2-swift, packaged as a signed
// .gaeaplugin by scripts/build-plugin.sh.
//
// seedvr2-inproc is not part of the plugin: it runs the same package in-process through MLXServeEngine, with the
// same dependency resolution and requests, as the reference a run through Gaea is compared against.
//
// GAEA_PLUGIN_KIT_PATH points the kit at a local checkout while you work on both.
let kitPath = Context.environment["GAEA_PLUGIN_KIT_PATH"]

let package = Package(
    name: "gaea-plugin-seedvr2",
    platforms: [.macOS(.v26)], // mlx-engine-swift's MLXToolKit requires macOS 26
    dependencies: [
        kitPath.map { .package(path: $0) }
            ?? .package(url: "https://github.com/xocialize-code/gaea-plugin-kit.git", from: "0.9.0"),
        .package(url: "https://github.com/xocialize/mlx-seedvr2-swift.git", exact: "0.10.1"),
        .package(url: "https://github.com/xocialize/mlx-engine-swift.git", from: "0.73.0"),
    ],
    targets: [
        .target(
            name: "SeedVR2Plugin",
            dependencies: [
                .product(name: "GaeaPluginKit", package: "gaea-plugin-kit"),
                .product(name: "MLXSeedVR2", package: "mlx-seedvr2-swift"),
                .product(name: "MLXToolKit", package: "mlx-engine-swift"),
            ]
        ),
        .executableTarget(
            name: "gaea-seedvr2-worker",
            dependencies: [
                "SeedVR2Plugin",
                .product(name: "GaeaPluginKit", package: "gaea-plugin-kit"),
            ]
        ),
        .executableTarget(
            name: "seedvr2-inproc",
            dependencies: [
                "SeedVR2Plugin",
                .product(name: "GaeaProtocol", package: "gaea-plugin-kit"),
                .product(name: "MLXSeedVR2", package: "mlx-seedvr2-swift"),
                .product(name: "MLXToolKit", package: "mlx-engine-swift"),
                .product(name: "MLXServeCore", package: "mlx-engine-swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "SeedVR2PluginTests",
                    dependencies: ["SeedVR2Plugin", .product(name: "MLXSeedVR2", package: "mlx-seedvr2-swift")]),
    ]
)
