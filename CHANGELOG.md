# Changelog

## Unreleased

- Choosing a game folder while DOS is running mounts it as drive C straight away, with no restart. At the Z: prompt, DOS switches to the new drive.
- Each DOS session runs in its own helper process (DOS Boxer Engine), so Restart and choosing a folder happen in the same window, and a crashing game can't take the app down.
- ⌘⌥ releases the mouse without pressing Alt in the game. A hint next to the toolbar buttons explains how to capture and release the mouse.
- DOS Boxer's own header replaces the emulator's welcome banner.
- The DOS screen sits below the toolbar and clear of the rounded window corners.
- Proof of concept: DOSBox Staging is embedded as a library and runs a DOS prompt in a SwiftUI and Metal window, with AVAudioEngine sound and keyboard and mouse input.
