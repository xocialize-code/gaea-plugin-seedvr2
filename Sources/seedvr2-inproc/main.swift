import Foundation
import GaeaProtocol
import MLXSeedVR2
import MLXServeCore
import MLXToolKit
import SeedVR2Plugin

// The in-process reference for the plugin: SeedVR2-3B loaded by MLXServeEngine in this process, with the lane
// configuration and the request the worker builds (SeedVR2Plugin). The clip is written to --out, and one JSON line of
// timings is printed. Not part of the plugin bundle.
//
//   seedvr2-inproc --video <mp4> [--scale 2] [--quant int8|fp16] [--models-root <dir>] [--out <mp4>]

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...(i + 1)) }
    return args[i + 1]
}
func seconds(since start: ContinuousClock.Instant) -> Double {
    let d = ContinuousClock.now - start
    return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
}

let modelsRoot = URL(fileURLWithPath: option("--models-root")
                     ?? NSHomeDirectory() + "/Library/Application Support/MLXEngine/Models", isDirectory: true)
guard let videoPath = option("--video") else { fatalError("seedvr2-inproc needs --video") }
let scale = Int(option("--scale") ?? "") ?? 2
let quant: Quant = option("--quant") == "fp16" ? .fp16 : .int8

// The budget Gaea sends a worker on a large Mac (wiresWeights off).
let engine = MLXServeEngine(workerBudget: WorkerBudget(ceilingBytes: 64_000_000_000, wiresWeights: false))
await engine.useModelStore(ModelStore(root: modelsRoot))
let id = PackageID(quant == .fp16 ? fp16ID : int8ID)
_ = try await engine.register(SeedVR2UpscalePackage.registration, configuration: lane(quant).configuration, id: id)
var clock = ContinuousClock.now
_ = try await engine.prepare(.videoUpscale, package: id)
var result: [String: Any] = ["model": id.rawValue, "scale": scale, "prepare_s": seconds(since: clock)]
clock = ContinuousClock.now
let video = try Data(contentsOf: URL(fileURLWithPath: videoPath))
guard let response = try await engine.run(request(video: video, scale: scale), package: id) as? VideoUpscaleResponse else {
    fatalError("SeedVR2 returned no video")
}
result["run_s"] = seconds(since: clock)
result["applied_scale"] = response.appliedScale
if let out = option("--out") { try response.video.data.write(to: URL(fileURLWithPath: out)) }
var usage = rusage()
getrusage(RUSAGE_SELF, &usage)
result["max_rss_gb"] = Double(usage.ru_maxrss) / 1e9
print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
