# Changelog

## Unreleased

- **Game library.** Drop game folders, ZIP files (including eXoDOS archives) or gameboxes onto the library window, and DOS Boxer keeps a copy of each as a `.dosgame` gamebox in `~/DOSBoxer` (you can choose another location, including iCloud Drive, Dropbox or OneDrive). Box art that comes with a game becomes its cover. Double-click a game to play it in its own window; several games can run at once.
- **Gameboxes** hold a game's files, settings, launchers and cover. Everything a game writes (saves, high scores, settings) goes to a separate Saves folder, so the original files stay untouched and "Revert to Original" can undo it all.
- When a game quits back to DOS, its window closes and you're back in the library (each gamebox can turn this off). The Programs menu also offers a DOS prompt with the game's drives.
- Games that start straight away skip DOS Boxer's header, and games started from a batch file now close properly when they end.
- Games without box art show a floppy-disk placeholder.
- DOS Boxer picks the program that starts each game (start scripts first, never setup tools), and lists the game's other programs in the toolbar.
- Opens original Boxer gameboxes (`.boxer`) without changing them.
- Games in a cloud-synced library are fully downloaded before they start, so they never stall mid-game.
- DOS Boxer is no longer sandboxed (it's distributed outside the App Store with Developer ID signing and notarization).

- Choosing a game folder while DOS is running mounts it as drive C straight away, with no restart. At the Z: prompt, DOS switches to the new drive.
- Each DOS session runs in its own helper process (DOS Boxer Engine), so Restart and choosing a folder happen in the same window, and a crashing game can't take the app down.
- ⌘⌥ releases the mouse without pressing Alt in the game. A hint next to the toolbar buttons explains how to capture and release the mouse.
- DOS Boxer's own header replaces the emulator's welcome banner.
- The DOS screen sits below the toolbar and clear of the rounded window corners.
- Proof of concept: DOSBox Staging is embedded as a library and runs a DOS prompt in a SwiftUI and Metal window, with AVAudioEngine sound and keyboard and mouse input.
