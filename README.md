# effing-ffmpeg-builds

Static FFmpeg binaries for [Effing](https://github.com/builtbyfew/effing).

Builds FFmpeg from source on GitHub-hosted runners for four targets:

| Target | Runner | Libc |
| --- | --- | --- |
| `linux-x64` | `ubuntu-latest` + `alpine:3.19` | musl (fully static) |
| `linux-arm64` | `ubuntu-24.04-arm` + `alpine:3.19` | musl (fully static) |
| `darwin-x64` | `macos-15-intel` | system (libx264/ffmpeg libs static) |
| `darwin-arm64` | `macos-15` | system (libx264/ffmpeg libs static) |
| `win32-x64` | `windows-latest` + MSYS2/MinGW64 | mingw (fully static) |

All builds are configured with `--enable-gpl --enable-libx264`. The Linux binaries are fully static and run on Alpine and any other Linux distro without glibc. The Windows binary is fully static (no DLL deps).

libx264 is built from source during the Linux and Windows jobs (Alpine and MinGW don't package a static `libx264.a`). On macOS, libx264 comes from Homebrew. The x264 revision is pinned in `build.sh` for reproducibility.

## Triggering a release

1. Go to **Actions → Release → Run workflow**
2. Enter the FFmpeg version (e.g. `6.1.4`)
3. Optionally tick **overwrite** to delete and recreate an existing release (useful when rebuilding the same version with different flags)
4. The workflow builds all four targets in parallel, creates tag `v<version>`, and publishes a GitHub release with the binaries

## Release assets

Each release contains:

```
ffmpeg-darwin-arm64           ffmpeg-darwin-arm64.gz
ffmpeg-darwin-x64             ffmpeg-darwin-x64.gz
ffmpeg-linux-arm64            ffmpeg-linux-arm64.gz
ffmpeg-linux-x64              ffmpeg-linux-x64.gz
ffmpeg-win32-x64              ffmpeg-win32-x64.gz
LICENSE.txt                   # FFmpeg GPLv3 license
```

## Licensing

The binaries in releases include libx264 and are therefore licensed under **GPLv3**. The `LICENSE.txt` file in each release carries the FFmpeg license text. The build scripts (`build.sh`, workflow) in this repo are under the MIT license (see `LICENSE`).
