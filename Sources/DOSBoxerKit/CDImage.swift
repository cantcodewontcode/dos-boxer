import Foundation

/// Lists the files on a CD image (ISO 9660), without mounting it: for games
/// whose programs are only on their CD (The Dig).
enum CDImage {
    /// Paths on the disc, like "DIG/DIG.EXE", down to `depth` folders. Nil if
    /// the image can't be read (an unsupported format, or not a data disc).
    static func files(in image: URL, depth: Int = 3) -> [String]? {
        guard let disc = Disc(image: image), let descriptor = disc.sector(16),
              descriptor.count >= 190, descriptor[1...5].elementsEqual("CD001".utf8) else { return nil }
        // The root folder's record sits in the volume descriptor
        let root = descriptor.subdata(in: 156..<190)
        var files: [String] = []
        disc.walk(extent: root.uint32(at: 2), length: root.uint32(at: 10), path: "", depth: depth, into: &files)
        return files
    }

    /// A data track: where its 2048-byte sectors are in the file.
    private struct Disc {
        let handle: FileHandle
        /// Bytes per sector in the file, and where the data starts in each.
        let sectorSize: UInt64
        let dataOffset: UInt64

        init?(image: URL) {
            var file = image
            var sectorSize: UInt64 = 2048, dataOffset: UInt64 = 0
            switch image.pathExtension.lowercased() {
            case "iso":
                break
            case "cue":
                // FILE "game.bin" BINARY / TRACK 01 MODE1/2352
                guard let cue = try? String(contentsOf: image, encoding: .isoLatin1),
                      let name = cue.firstMatch(of: /(?i)FILE\s+"([^"]+)"/)?.1 else { return nil }
                file = image.deletingLastPathComponent().appending(path: String(name))
                if let mode = cue.firstMatch(of: /(?i)TRACK\s+\d+\s+(MODE[12])\/(\d+)/) {
                    sectorSize = UInt64(mode.2) ?? 2048
                    if sectorSize == 2352 { dataOffset = mode.1.uppercased() == "MODE2" ? 24 : 16 }
                }
            case "ccd":
                // CloneCD: raw sectors in the .img beside it
                file = image.deletingPathExtension().appendingPathExtension("img")
                sectorSize = 2352
                dataOffset = 16
            default:
                return nil
            }
            guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
            self.handle = handle
            self.sectorSize = sectorSize
            self.dataOffset = dataOffset
        }

        func sector(_ number: UInt32) -> Data? {
            try? handle.seek(toOffset: UInt64(number) * sectorSize + dataOffset)
            guard let data = try? handle.read(upToCount: 2048), data.count == 2048 else { return nil }
            return data
        }

        /// Adds the files in the folder at `extent` (and its folders) to `files`.
        func walk(extent: UInt32, length: UInt32, path: String, depth: Int, into files: inout [String]) {
            guard depth >= 0, length > 0, length < 16 * 1024 * 1024 else { return }
            let sectors = (length + 2047) / 2048
            for index in 0..<sectors {
                guard let data = sector(extent + index) else { return }
                var offset = 0
                while offset < data.count {
                    let recordLength = Int(data[offset])
                    // Records don't cross sectors; a zero length pads to the end
                    guard recordLength >= 34, offset + recordLength <= data.count else { break }
                    let record = data.subdata(in: offset..<(offset + recordLength))
                    offset += recordLength
                    let nameLength = Int(record[32])
                    guard 33 + nameLength <= record.count else { continue }
                    let rawName = record.subdata(in: 33..<(33 + nameLength))
                    // "\0" and "\1" are the folder itself and its parent
                    if nameLength == 1, rawName[0] <= 1 { continue }
                    var name = String(decoding: rawName, as: UTF8.self)
                    if let version = name.firstIndex(of: ";") { name = String(name[..<version]) }
                    if name.hasSuffix(".") { name.removeLast() }
                    let full = path.isEmpty ? name : "\(path)/\(name)"
                    if record[25] & 0x02 != 0 {
                        walk(extent: record.uint32(at: 2), length: record.uint32(at: 10), path: full,
                             depth: depth - 1, into: &files)
                    } else {
                        files.append(full)
                    }
                }
            }
        }
    }
}

private extension Data {
    /// A little-endian 32-bit number (ISO 9660 stores both byte orders).
    func uint32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return self[startIndex + offset..<startIndex + offset + 4].enumerated()
            .reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
    }
}
