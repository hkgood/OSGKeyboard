# ThirdParty

## mlx-audio-swift

macOS local ASR links `MLXAudioSTT` from [Blaizzy/mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift).

Before `xcodegen generate` or opening the project, run:

```bash
./Scripts/ensure-mlx-audio-swift.sh
```

This clones the package (if missing) and applies OSG's `StreamingConfig.context` patch for vocabulary prompts.

The clone lives at `ThirdParty/mlx-audio-swift/` (gitignored). SPM resolves mlx-audio-swift's own dependencies on first Mac build.
