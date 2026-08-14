# ThirdParty

## mlx-audio-swift

macOS local ASR links `MLXAudioSTT` from [Blaizzy/mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift).

Before `xcodegen generate` or opening the project, run:

```bash
./Scripts/ensure-mlx-audio-swift.sh
```

This clones the package (if missing) and applies OSG's `StreamingConfig.context` patch for vocabulary prompts.

The clone lives at `ThirdParty/mlx-audio-swift/` (gitignored). SPM resolves mlx-audio-swift's own dependencies on first Mac build.

The resolved Mac speech stack also includes:

- `mlx-swift` and `mlx-swift-lm` (MIT)
- `swift-transformers` and `swift-huggingface` (Apache-2.0)
- optional Qwen3-ASR 0.6B / 1.7B MLX 4-bit model downloads
  (Apache-2.0)

See `NOTICE-TYPING.md` and the in-app Third-Party Licenses screen for pinned
versions, purposes, upstream links, and license texts.
