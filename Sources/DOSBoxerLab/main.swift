// DOS Boxer Lab — runs a collection of DOS games through DOS Boxer
// unattended and records which ones start.
//
//   DOSBoxerLab --games /Volumes/Games/DOS/ALL --out build/lab [--jobs 6]
//               [--seconds 20] [--limit 100] [--every 25] [--filter keen]
//               [--year 1991]
//
// For each game: import a copy, start it with sound off, watch for a
// graphics screen, keep a thumbnail, fingerprint its programs, then delete
// the copy. Results go to <out>/results.jsonl after every game, so a run can
// be stopped and resumed.

import Foundation

let options = LabOptions(CommandLine.arguments.dropFirst())
await Lab(options: options).run()
