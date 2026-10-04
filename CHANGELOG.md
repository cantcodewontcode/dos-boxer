# Changelog

## Unreleased

- **Collections**: hand-built lists of games in the sidebar, like playlists. Make one with the + button or File › New Collection (⌘N), drag games onto it or use right-click › Add to Collection, and rename or delete it from its right-click menu.
- **Tidier library window**: Import and DOS Prompt, Sort, and Info buttons in the toolbar; search at the top of the sidebar; the game count and cover size slider in a footer. The File and View menus now hold Import Games (⇧⌘I), New DOS Prompt (⌥⌘N), Show Info (⌘I), Bigger/Smaller Covers (⌘+ / ⌘−), sorting, and the library's Finder and location commands.
- The info panel shows each game's publisher, developer and genre, which you can fill in yourself.
- New DOS Prompt windows start straight at the DOS prompt.

- **Library sidebar**: All Games, Favorites, Recently Played, Never Played, and one list per decade.
- **Info panel**: a fold-out panel on the right (the ⓘ button, or right-click > Get Info) with the game's cover, Play and Favorite buttons, play stats, which program it starts with, its own display look, whether it returns to the library when it ends, and the readmes and manuals that came with it.
- **Roland MT-32 music**: add your own MT-32 or CM-32L ROMs once in Settings › Music, and every game set up for the MT-32 uses them.
- **Pause**: the pause button in the game controls, or ⌘P. The sound stops and a "Paused" badge shows until you resume.
- **Paste into DOS**: Edit › Paste (⌘V) types the clipboard's text into the game, handy for long commands or copy-protection answers.
- **Game controllers**: Xbox, PlayStation, Switch and other controllers macOS supports work as a DOS joystick in the game that's in front. About 200 games that came from eXoDOS also get DOSBox Staging's tailored controller layouts (games added from now on).
- **Full screen**: a toolbar button (or ⌃⌘F); the toolbar stays hidden until you point at the top of the screen.
- **Display looks**: Crisp Pixels, Smooth, Arcade Monitor (scanlines and a colour mask) and Family TV (a curved, glowing screen). Choose one for all games in Settings, or for a single game from the in-game controls or the info panel.
- **Named programs for menu games**: games whose start script offers a menu ("Press 1 for… with Sound Blaster, Press 2 for… with MT-32") get each option as a named program, and the first one starts by default.
- Games no longer pick up settings from your own DOSBox Staging configuration, and DOS uses the keyboard layout you're typing with (it used to pick a non-US layout if one was merely enabled).

- Remove Cover Art, for a wrong cover or none at all; the game then stays without one until you look for art again.

- **Game library.** Drop game folders, ZIP files (including eXoDOS archives) or gameboxes onto the library window, and DOS Boxer keeps a copy of each as a `.dosgame` gamebox in `~/DOSBoxer/Games` (you can choose another location, including iCloud Drive, Dropbox or OneDrive). Box art that comes with a game becomes its cover. Double-click a game to play it in its own window; several games can run at once.
- **Game controls in Liquid Glass.** Move the pointer over a running game to show floating controls: slower and faster, volume, next disc (multi-disc games) and screenshot (saved to the library's Screenshots folder). They fade when the pointer rests or the mouse is captured.
- Rename games in place, as in Finder: click a selected game's name (or right-click > Rename), type, and press Return. Move them to the Trash with right-click > Move to Trash… or ⌘⌫, confirmed in a glass popover. Deleting only removes DOS Boxer's copy; it can be restored from the Trash.
- **Sorting**: Name, Year, Recently Played, Most Played or Recently Added, from the library's … menu (ties sort by name). DOS Boxer now records how often and how long each game is played; each Mac keeps its own record, so shared libraries don't conflict.
- **Cover size**: a slider in the library toolbar, or pinch to zoom on a trackpad; remembered between launches.
- **Box art.** Games without a cover get one automatically from the community libretro-thumbnails collection (about half of eXoDOS's games are covered; edition tags like "SCI" or "CD" in a game's name are ignored when matching). Right-click a game for Find Cover Art, or drop any image onto a game to make it the cover.
- **Gameboxes** hold a game's files, settings, launchers and cover. Everything a game writes (saves, high scores, settings) goes to a separate Saves folder, so the original files stay untouched and "Revert to Original" can undo it all.
- When a game quits back to DOS, its window closes and you're back in the library (each gamebox can turn this off). The Programs menu also offers a DOS prompt with the game's drives.
- Games that start straight away skip DOS Boxer's header, and games started from a batch file now close properly when they end.
- Games without box art show a floppy-disk placeholder.
- DOS Boxer picks the program that starts each game (start scripts first, never setup tools), and lists the game's other programs in the toolbar.
- Opens original Boxer gameboxes (`.boxer`) without changing them, and adding one to the library converts it, keeping its box art.
- Games being added appear in the library straight away with a progress spinner.
- If another Mac sharing the library is playing a game, DOS Boxer warns before you play it too.
- A DOS Prompt button in the library toolbar.
- CD-based games: disc images (CUE, ISO, CCD, MDF) found in a game are mounted as drive D, including multi-disc games.
- Better at picking the right program: skips DOS extenders, runtimes, patch tools and installers.
- Fixed: starting several games at once could make one fail to start.
- DOSBoxerLab, a developer tool that runs a game collection through DOS Boxer unattended and records which games start.
- Games in a cloud-synced library are fully downloaded before they start, so they never stall mid-game.
- DOS Boxer is no longer sandboxed (it's distributed outside the App Store with Developer ID signing and notarization).

- Choosing a game folder while DOS is running mounts it as drive C straight away, with no restart. At the Z: prompt, DOS switches to the new drive.
- Each DOS session runs in its own helper process (DOS Boxer Engine), so Restart and choosing a folder happen in the same window, and a crashing game can't take the app down.
- ⌘⌥ releases the mouse without pressing Alt in the game. A hint next to the toolbar buttons explains how to capture and release the mouse.
- DOS Boxer's own header replaces the emulator's welcome banner.
- The DOS screen sits below the toolbar and clear of the rounded window corners.
- Proof of concept: DOSBox Staging is embedded as a library and runs a DOS prompt in a SwiftUI and Metal window, with AVAudioEngine sound and keyboard and mouse input.
