# Changelog

## [0.1.1]

Fixes and polish from the first round of real use.

- **Speed sticks.** Slow a game down (⌘[) or speed it up (⌘]) and it remembers, every time you play. Reset it from the info panel.
- **Better box art.** Covers now come from the LaunchBox Games Database first, including fan-made art for games with no box scan.
- **Duplicates.** Adding a game you already have asks whether to replace it, keep both or skip it. Libraries that ended up with duplicates fix themselves.
- **Genres.** All 28 LaunchBox genres. Type to add one in the info panel.
- **Libraries.** File › New Library, Open Library and Move Library.
- **Fixes.** ⌘⌥ always releases the mouse; long names no longer spill out of the info panel; Collections dim with the rest of the sidebar.

## [0.1.0]

The first release. Everything's new, so here's what DOS Boxer does, what it doesn't do yet, and a few details for the curious.

### What works

**Running games**
- Built on DOSBox Staging 0.83.0, with a small set of patches so it can run inside a Mac app. Each game runs in its own helper process, so several games can run at once and one crashing can't take the others down.
- Apple Silicon only, macOS 26 or later.
- Video is drawn with Metal. Four display looks: Crisp Pixels, Smooth, Arcade Monitor (scanlines and a colour mask) and Family TV (curved, glowing screen), app-wide or per game.
- Sound is played by macOS directly. Sound Blaster, AdLib, Gravis Ultrasound and the PC speaker all come from DOSBox Staging. Roland MT-32 and CM-32L work once you add your own ROMs (any version; drop the archive.org collection ZIP straight onto the app).
- Games from 1993 on get 64 MB of memory; earlier ones get DOSBox's standard 16 MB.
- DOS uses the keyboard layout you're typing with on your Mac. Paste (⌘V) types the clipboard into DOS, handy for copy-protection answers. US characters only for now.
- Your own DOSBox Staging config files are ignored, so games behave the same for everyone.

**Importing**
- Folders, ZIP files and CD images (`.cue`, `.iso`, `.mdf`, `.ccd`; one file per disc, cue sheets preferred). Multi-disc games can swap discs with Game › Next Disc.
- DOS Boxer picks the program that starts the game: start scripts first, then programs named after the game (or its initials), never setup or install tools.
- Start scripts with menus ("Press 1 for Sound Blaster, 2 for MT-32") become separate, named ways to start the game.
- eXoDOS-style ZIPs are understood, including their folder layout and menus.
- Original Boxer gameboxes (`.boxer`) open as they are and can be converted.

**The library**
- Games are stored as `.dosgame` packages in `~/DOSBoxer` (or anywhere you like, including iCloud Drive, Dropbox and OneDrive). There's no database to corrupt: each game's details live in its own `Game.json`, and play stats are kept per Mac so shared libraries don't clash.
- Games never write to their own files. Saves, high scores and settings go to a separate folder, and Revert to Original undoes it all.
- If another Mac sharing the library is playing a game, DOS Boxer warns you first.
- Sidebar: All Games, Favorites, Recently Played, Never Played, your own Collections, Years and Genres. Sort by name, year, rating, developer, publisher, recently played, most played or recently added.

**Game details**
- Optional download of the LaunchBox Games Database (about 7,200 DOS games), kept on your Mac. Nothing is sent anywhere.
- Games are recognised by their program files (name and checksum), then by collection folder name (like eXoDOS's), then by name. Wikidata fills in what LaunchBox doesn't have.
- Each game gets its release year, developer, publisher, genres, players (and co-op), age rating, community rating and description, all editable.
- Box art comes from the libretro-thumbnails collection, or drop any image on a game.

**Controllers**
- Anything macOS supports: Xbox, PlayStation, Switch and more. Up to two players, each with their own joystick in DOS.
- Per-game controls: make any button or stick direction press a key, act as another button, or do nothing. Saved by player and button position, so they carry over to whatever controller you plug in.
- About 200 eXoDOS games also get DOSBox Staging's tailored controller layouts.

**Everything else**
- Pause, screenshots (saved to the library's Screenshots folder), full screen (⌘↩), faster and slower, and a DOS prompt with the game's drives.
- Updates are checked in the background at launch (Settings › Updates to turn off).

### How well does it work?

DOS Boxer's compatibility lab boots games unattended and checks whether they get going. Run over the 7,514 games in eXoDOS:

| | Games | Share |
|---|---|---|
| Reach graphics | 4,619 | 61.5% |
| Reach a text screen (usually a menu or "press a key") | 2,184 | 29.0% |
| Quit straight away | 542 | 7.2% |
| No program to start | 164 | 2.2% |

So about 90% get going on their own, with no settings. "Reach graphics" doesn't promise the game is fully playable, just that it starts.

### Not yet

- **PC booter games** (bootable floppy images, mostly 1981–85) and **IBM PCjr cartridges** don't start yet.
- **CD-only games** that need installing from the CD first don't have a program to start yet.
- **Interactive fiction** that needs a story file passed to its interpreter (Frotz, Scott Adams games) quits straight away.
- **Speed by era.** Older games run at DOSBox's default speed, which can be too fast. Use Game › Slower (⌘[) for now.
- **Joystick types.** Games always see a standard joystick, not a flight stick or racing wheel.
- **Save states**, **GOG/Steam importing**, **printing** and **multiplayer networking** aren't here yet.
- **Intel Macs** and macOS versions before 26 aren't supported.

### Known issues

- Some wired Xbox 360 controllers show up as just "Controller".
- Game details come from community data, so the odd game gets the wrong match. You can edit anything in the info panel.
