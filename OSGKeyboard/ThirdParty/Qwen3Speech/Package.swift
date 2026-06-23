// swift-tools-version: 5.10
import PackageDescription

// Local fork of soniqo/speech-swift that ships ONLY what OSGKeyboard
// consumes: Qwen3ASR + Qwen3Chat. The original repo's `Package.swift`
// references a `CSpeechCore` binary target whose URL doesn't match
// its declared filename (`SpeechCore.xcframework.zip` vs target
// name `CSpeechCore`), which breaks SwiftPM resolve on a clean
// checkout. The only thing we need from speech-swift for the
// OSGKeyboard on-device path is the two Qwen3 modules and the
// AudioCommon / MLXCommon / SpeechVAD slices they depend on — the
// AudioServer / AudioCLI / AudioCLILib targets that pulled in
// SpeechCore aren't part of our build graph.
//
// Source provenance: every `.swift` file in `Sources/<Target>/` is
// copied from https://github.com/soniqo/speech-swift (commit pinned
// to v0.0.21 of the upstream tag tree). Original copyright
// headers are preserved in each file. Apache-2.0 license.
//
// Track upstream: when soniqo fixes the binary-target mismatch in
// their main `Package.swift`, delete this local package and
// re-enable the upstream dependency in the host project.

let package = Package(
    name: "Qwen3Speech",
    platforms: [
        .iOS("18.0"),
        .macOS("15.0")
    ],
    products: [
        .library(name: "Qwen3ASR", targets: ["Qwen3ASR"]),
        .library(name: "Qwen3Chat", targets: ["Qwen3Chat"]),
    ],
    dependencies: [
        // mlx-swift is the Apple MLX array framework bindings; Qwen3
        // runtime depends on the GPU side, the chat runtime depends
        // on the linear-attention kernels exposed by MLXNN / MLXFast.
        //
        // We pin to a local flattened copy at `~/.local/mlx-swift`
        // (an exported snapshot of mlx-swift 0.31.4 with its Cmlx /
        // mlx-c submodules baked in as plain directories) because
        // SwiftPM can't reliably fetch the upstream's git submodules
        // on this network — the Cmlx/mlx submodule is ~700 MB of
        // history and the clone drops mid-fetch. The snapshot is
        // generated once on a healthy network, kept outside the
        // project, and re-used on every resolve.
        .package(path: "/Users/rocky/.local/mlx-swift"),
        // swift-transformers exposes Hugging Face Hub and tokenizers
        // — AudioCommon uses Hub to resolve repo → snapshot path.
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.1.6"),
    ],
    targets: [
        .target(
            name: "AudioCommon",
            dependencies: [
                .product(name: "Hub", package: "swift-transformers"),
            ]
        ),
        .target(
            name: "MLXCommon",
            dependencies: [
                "AudioCommon",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
            ]
        ),
        .target(
            name: "SpeechVAD",
            dependencies: [
                "AudioCommon",
                "MLXCommon",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
            ]
        ),
        .target(
            name: "Qwen3ASR",
            dependencies: [
                "AudioCommon",
                "MLXCommon",
                "SpeechVAD",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
            ]
        ),
        .target(
            name: "Qwen3Chat",
            dependencies: [
                "AudioCommon",
                "MLXCommon",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
            ]
        ),
    ]
)
