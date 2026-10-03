// DOS Boxer Engine — the helper process that runs one DOS session.
//
// Usage: DOS Boxer Engine <shared frame file> [dosbox arguments…]
// The app launches this; it isn't meant to be run by hand.

import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: DOS Boxer Engine <shared frame file> [dosbox arguments…]\n".utf8))
    exit(EX_USAGE)
}
Engine.run(sharedFilePath: arguments[1], dosboxArguments: Array(arguments.dropFirst(2)))
