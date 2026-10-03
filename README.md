# DOS Boxer

DOS Boxer turns DOS games into Mac apps. It's a from-scratch, native successor to [Boxer](https://github.com/alinebee/Boxer), built for macOS 26 and Apple Silicon. It's written in Swift, uses Apple's Liquid Glass design, and runs on the [DOSBox Staging](https://github.com/dosbox-staging/dosbox-staging) emulator.

> **Status:** early proof of concept. It boots to a DOS prompt in a Metal view, with sound and keyboard and mouse input.

## Requirements

- A Mac with Apple Silicon, running macOS 26 or later
- Xcode 26 or later
- Homebrew packages: `brew install cmake ninja pkg-config autoconf automake libtool xcodegen`

## Building

```bash
git clone --recursive <repo-url> dos-boxer
cd dos-boxer
Scripts/bootstrap.sh
open DOSBoxer.xcodeproj
```

The first build compiles the emulator and its dependencies, which takes a while (about 20–30 minutes). Later builds are incremental.

## Layout

| Path | What's there |
|---|---|
| `Sources/DOSBoxerApp` | The SwiftUI app |
| `Sources/DOSBoxerKit` | Swift framework: emulator lifecycle, Metal renderer, audio, input |
| `Core/` | C++ host layer that embeds DOSBox Staging and exposes a small C API (`DOSBoxerHost.h`) |
| `Core/patches/` | Small patches applied to DOSBox Staging (hooks for video, audio and building as a library) |
| `Vendor/dosbox-staging` | DOSBox Staging, as a git submodule |
| `Scripts/` | Bootstrap and core build scripts |

## License

DOS Boxer is free software, licensed under the GNU General Public License, version 2 or (at your option) any later version. See [LICENSE](LICENSE). DOSBox Staging is licensed under GPL-2.0-or-later. The floppy-disk icon is from [Phosphor Icons](https://phosphoricons.com) (MIT; see `Licenses/`).
