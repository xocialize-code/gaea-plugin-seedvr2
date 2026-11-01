# gaea-plugin-seedvr2

ByteDance-Seed's **SeedVR2-3B** (Apache-2.0 weights) as a [Gaea](https://github.com/xocialize-code/gaea) plugin: video
super-resolution, on MES Video 0.1's `video.upscale`. It is built on
[GaeaPluginKit](https://github.com/xocialize-code/gaea-plugin-kit) over
[mlx-seedvr2-swift](https://github.com/xocialize/mlx-seedvr2-swift), runs in its own process, and speaks the Gaea Plugin
Protocol v1. Add it to Gaea by its repo URL:

```bash
gaea plugins add https://github.com/xocialize-code/gaea-plugin-seedvr2
```

## What it offers

Two models on `video.upscale`, one per quality tier:

| Model | `quality` | Weights |
|---|---|---|
| `seedvr2-int8` | `draft`, `standard` (the default) | int8, 4.7 GB, near-lossless against fp16 |
| `seedvr2-fp16` | `best` | fp16, 8.4 GB |

Each has one lane, so a request that names a tier runs at it or is refused: a tier refused for memory is never
swapped for the other (Video §3.4).

- **`scale`** 2 or 4 (the default is 2). Every frame is enlarged by a Lanczos pre-upscale, then a one-step diffusion
  refines it in 256-pixel tiles.
- **Frames.** The output is exactly the source's width and height × `scale`, with the same frames and rate. They are
  refined in windows of 9 frames, with the VAE's memory carried across the joins so detail holds still from frame to
  frame; a scene cut ends a window.
- **`content`** is required by the profile; both `live_action` and `drawn` are listed.
- **Sound and markings.** The package writes the picture alone. Gaea puts the source's audio track and its markings
  (comment, copyright) back, unchanged, as Video §1.7 and §1.9 ask.
- **Limits:** up to 1920×1080 out (so 960×540 in at ×2, 480×270 at ×4), and clips up to 60 s. Gaea refuses a larger
  output with 422 `out_of_limits` once it has read the source.
- **Determinism:** no seed (`supports.seed: false`, `deterministic: true`). The package draws its noise from a seed in
  its configuration, so the same clip gives the same frames.
- **Output:** an HEVC MP4, BT.709-tagged. Gaea retimes it to the exact rate and gives H.264 when the request's
  `output.codec` asks.

On an M5 Max a 128×96, 17-frame clip upscales ×2 in a few seconds warm.

## Lanes and memory

The package declares 4.8 GB resident and 4.5 GB more while running (int8; fp16 7.5 GB resident). Its 9-frame windows
measure more: about 11.8 GiB for one 256-pixel tile stream, and about 0.8 GiB for each further tile position, so a
1920×1080 output is about 48 GiB. The package narrows the window, down to 1 frame (about 7.8 GiB at any size), to
fit the budget Gaea gives the worker, and Gaea's governor charges the worker's measured footprint.

## Weights

Gaea sends its models root in `configure` (MLXEngine's store by default). The engine materializes
`mlx-community/SeedVR2-3B-mlx-int8` or `mlx-community/SeedVR2-3B-mlx` there on the first prepare, at
`models--mlx-community--SeedVR2-3B-mlx-int8` and `models--mlx-community--SeedVR2-3B-mlx`.

## Build and check locally

```bash
scripts/build-plugin.sh
```

```bash
scripts/check-plugin.sh
```

`check-plugin.sh` upscales `Tests/Fixtures/clip.mp4` over GPP on the signed bundle, with every `.build` folder hidden.
It then shows that the bare worker, outside the bundle, finds no metallib.

`scripts/release.sh` builds, checks, notarizes with the fleet's `mlx-notary` profile, and publishes the GitHub release.
The release workflow does the same in CI when a `v<version>` tag is pushed.

`seedvr2-inproc` (its header lists the options) is not part of the plugin. It runs the same lane in-process through
MLXServeEngine, with the worker's request: the reference Gaea's runs are compared against.

```bash
scripts/golden.sh <out-dir>
```

`golden.sh` upscales the fixtures over GPP on the signed bundle and through `seedvr2-inproc`, and needs each pair to
decode to the same frames, byte for byte (ffmpeg's `framemd5`), at the right size and count.
- The cases: `clip.mp4` (128×96, 17 frames at 24 fps, with sound) at ×2 and ×4 on int8 and ×2 on fp16, and
  `clip180.mp4` (320×180, 48 frames) at ×2 on int8.
- The MP4s themselves differ only in their creation time. The fixtures were made with ffmpeg's `testsrc2`.

## CI secrets

The release workflow signs with Developer ID and notarizes. It reads four organization secrets on xocialize-code:
`DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `NOTARY_APPLE_ID` and `NOTARY_APP_PASSWORD` (Gaea's
`Docs/Signing secrets.md`).

## Licence

The plugin is Apache-2.0 (Gaea G-21). SeedVR2's weights are Apache-2.0 (ByteDance-Seed), and the port,
mlx-seedvr2-swift, is MIT.
