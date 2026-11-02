import Foundation
import GaeaPluginKit
import GaeaProtocol
import MLXSeedVR2
import MLXToolKit

// gaea-plugin-seedvr2: ByteDance-Seed's SeedVR2-3B (weights Apache-2.0; the MLX port, mlx-seedvr2-swift, is MIT) on MES
// Video 0.1's video.upscale (media-engine-spec v0.9.0, Gaea AB-T-0403). Every frame is enlarged 2 or 4 times (Video
// §3.4): a Lanczos pre-upscale, then a one-step diffusion refines it tile by tile, in windows of 9 frames with the
// VAE's memory carried across the joins, so the detail holds still from frame to frame. A scene cut ends a window.
//
// - Two models on one package, one per quality tier (VIDEO-EVALUATION §6.2): seedvr2-int8 for draft and standard,
//   seedvr2-fp16 for best. Each has one lane, so a tier refused for memory is never swapped for the other (§3.4).
// - Fit for live action and drawn content alike.
// - The output is exactly the source's size × scale, with the same frames; Gaea retimes it, and puts the source's
//   sound and markings back (the package writes the picture alone).
// - No seed: the package draws its noise from a seed fixed in its configuration, so the same clip gives the same
//   frames. Output is an HEVC MP4, BT.709-tagged.

public let int8ID = "seedvr2-int8", fp16ID = "seedvr2-fp16"
public let scales = [2, 4]
/// The largest output an offer makes. The diffusion works in 256-pixel tiles, so frame size sets the time, and, at a
/// 9-frame window, the memory: each tile position keeps about 0.8 GiB of the VAE's stream, so 1920×1080 is about 48 GiB.
/// The package narrows the window to fit the budget Gaea gives the worker (down to 1 frame, about 7.8 GiB at any size).
public let maxWidth = 1920, maxHeight = 1080
/// The longest clip an offer takes: about 0.3 s a frame at 256×192 out, and seconds a frame at 1080p.
public let maxSourceSeconds = 60.0

/// What an upscale job asks of the package, validated: the scale (Gaea fills in the offer's default, 2).
public func scale(_ job: Job) throws -> Int {
    let scale = job.param("scale")?.intValue ?? 2
    guard scales.contains(scale) else {
        throw GPPError(.invalidRequest, "SeedVR2 upscales 2 or 4 times.", detail: ["param": "scale"])
    }
    return scale
}

/// The engine request for a clip.
public func request(video: Data, scale: Int) -> VideoUpscaleRequest {
    VideoUpscaleRequest(video: Video(format: .mp4, data: video), scale: scale)
}

let upscaleOperation = EngineOperation("video.upscale") { job, session in
    guard let source = job.input("video") else {
        throw GPPError(.invalidRequest, "video.upscale needs the video.", detail: ["param": "video"])
    }
    let scale = try scale(job)
    guard let response = try await session.run(request(video: try Data(contentsOf: source), scale: scale)) as? VideoUpscaleResponse else {
        throw GPPError(.modelError, "SeedVR2 returned no video.")
    }
    let url = session.outputDir.appending(path: "video-0.mp4")
    try response.video.data.write(to: url)
    return RunResult(outputs: [.file("video", url, mediaType: "video/mp4")],
                     effective: ["scale": .int(Int64(response.appliedScale))])
}

// MARK: - The plugin

/// The lane each model runs in: the package's defaults (9-frame windows, 256-pixel tiles, colour correction on) at
/// the model's quant.
public func lane(_ quant: Quant) -> LaneDefinition {
    LaneDefinition(id: quant == .fp16 ? "fp16" : "int8", default: true, configuration: SeedVR2Configuration(quant: quant))
}

let int8Model = ModelDefinition.engine(SeedVR2UpscalePackage.self, id: int8ID, title: "SeedVR2 3B (int8)",
                                       lanes: [lane(.int8)], operations: [upscaleOperation])
let fp16Model = ModelDefinition.engine(SeedVR2UpscalePackage.self, id: fp16ID, title: "SeedVR2 3B (fp16)",
                                       lanes: [lane(.fp16)], operations: [upscaleOperation])

func offer(_ id: String, title: String, memory: String, tiers: [String], notes: String) -> PluginManifest.Offer {
    PluginManifest.Offer(
        operation: "video.upscale", profile: "video",
        model: [
            "id": .string(id), "title": .string(title),
            "license": ["spdx": "Apache-2.0", "commercial_use": true, "terms_url": "https://huggingface.co/ByteDance-Seed/SeedVR2-3B"],
            "memory_class": .string(memory), "speed_class": "slow", "quality_tiers": .array(tiers.map { .string($0) }),
            "notes": .string(notes),
            "supports": ["scales": .array(scales.map { .int(Int64($0)) }), "content": ["live_action", "drawn"],
                         "seed": false, "deterministic": true],
            "limits": ["max_width": .int(Int64(maxWidth)), "max_height": .int(Int64(maxHeight)),
                       "max_source_s": .double(maxSourceSeconds)],
        ],
        defaults: ["scale": 2])
}

let int8Offer = offer(int8ID, title: "SeedVR2 3B", memory: "large", tiers: ["draft", "standard"],
                      notes: "Enlarges a clip 2 or 4 times with one-step diffusion, for live action and drawn content alike, keeping its frames, sound and markings. Up to 1920×1080 out and 60 s. The int8 weights (4.7 GB), near-lossless against fp16.")
let fp16Offer = offer(fp16ID, title: "SeedVR2 3B (fp16)", memory: "large", tiers: ["best"],
                      notes: "SeedVR2 at full precision (8.4 GB of weights), for quality best. Otherwise the same as seedvr2-int8.")

public let seedvr2Plugin = GaeaPluginDefinition(
    id: "com.xocialize.gaea.seedvr2", version: "0.1.1", minGaea: "0.10.1", team: "CFZS6RXUCP",
    repo: "https://github.com/xocialize-code/gaea-plugin-seedvr2", title: "SeedVR2",
    summary: "SeedVR2-3B: video super-resolution (MES video.upscale), 2 or 4 times, live action and drawn, up to 1080p out.",
    license: "Apache-2.0", executable: "gaea-seedvr2-worker",
    models: [int8Model, fp16Model], offers: [int8Offer, fp16Offer])
