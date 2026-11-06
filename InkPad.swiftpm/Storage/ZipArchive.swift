import Foundation
import zlib

enum ZipArchiveError: LocalizedError {
    case tooLarge
    case notAnArchive
    case unsupportedEntry(String)
    case unsafePath(String)
    case damaged(String)

    var errorDescription: String? {
        switch self {
        case .tooLarge:
            "The library is too large for one backup file (over 4 GB)."
        case .notAnArchive:
            "This file is not an InkPad backup."
        case let .unsupportedEntry(path):
            "This file was not made by InkPad (\(path) is compressed)."
        case let .unsafePath(path):
            "The backup contains an invalid file name (\(path))."
        case let .damaged(path):
            "The backup is damaged (\(path) does not match its checksum)."
        }
    }
}

private enum ZipFormat {
    static let localHeader: UInt32 = 0x0403_4B50
    static let centralHeader: UInt32 = 0x0201_4B50
    static let endOfDirectory: UInt32 = 0x0605_4B50
    static let chunkSize = 1 << 20
    /// ZIP without the Zip64 extension stores sizes and offsets in 32 bits.
    static let maxOffset = UInt64(UInt32.max)

    static func crc(_ crc: UInt32, _ data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer -> UInt32 in
            guard let base = buffer.bindMemory(to: Bytef.self).baseAddress else { return crc }
            return UInt32(zlib.crc32(uLong(crc), base, uInt(buffer.count)))
        }
    }
}

/// Writes a ZIP file straight to disk, one file at a time, so large PDFs and
/// recordings never have to fit in memory. Files are stored uncompressed:
/// ink, PDFs, photos and audio are already compressed, and any unzip tool
/// (Files, Finder) opens the result.
struct ZipFileWriter {
    private let handle: FileHandle
    private var offset: UInt64 = 0
    private var directory = Data()
    private var count = 0
    private let dosTime: UInt16
    private let dosDate: UInt16

    init(creating url: URL, date: Date = Date()) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        dosTime = UInt16((parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2)
        dosDate = UInt16(max(0, (parts.year ?? 1980) - 1980) << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1))
    }

    /// Adds a file from disk under `path` (forward slashes, no leading slash).
    mutating func addFile(at url: URL, as path: String) throws {
        let reader = try FileHandle(forReadingFrom: url)
        defer { try? reader.close() }
        // First pass: size and checksum, which the header needs up front.
        var crc: UInt32 = 0
        var size: UInt64 = 0
        while let chunk = try reader.read(upToCount: ZipFormat.chunkSize), !chunk.isEmpty {
            crc = ZipFormat.crc(crc, chunk)
            size += UInt64(chunk.count)
        }
        try writeHeader(path, crc: crc, size: size)
        try reader.seek(toOffset: 0)
        var copied: UInt64 = 0
        while copied < size, let chunk = try reader.read(upToCount: ZipFormat.chunkSize), !chunk.isEmpty {
            let part = chunk.prefix(Int(size - copied))
            try handle.write(contentsOf: part)
            copied += UInt64(part.count)
        }
        // The file shrank while it was being read.
        guard copied == size else { throw ZipArchiveError.damaged(path) }
        offset += size
    }

    mutating func add(_ path: String, data: Data) throws {
        try writeHeader(path, crc: ZipFormat.crc(0, data), size: UInt64(data.count))
        try handle.write(contentsOf: data)
        offset += UInt64(data.count)
    }

    /// Writes the central directory and closes the file.
    mutating func finish() throws {
        defer { try? handle.close() }
        guard offset <= ZipFormat.maxOffset, count < Int(UInt16.max) else { throw ZipArchiveError.tooLarge }
        try handle.write(contentsOf: directory)
        var end = Data()
        end.appendLE32(ZipFormat.endOfDirectory)
        end.appendLE16(0)
        end.appendLE16(0)
        end.appendLE16(UInt16(count))
        end.appendLE16(UInt16(count))
        end.appendLE32(UInt32(directory.count))
        end.appendLE32(UInt32(offset))
        end.appendLE16(0)
        try handle.write(contentsOf: end)
    }

    /// Gives up on the archive; the caller removes the file.
    func cancel() {
        try? handle.close()
    }

    private mutating func writeHeader(_ path: String, crc: UInt32, size: UInt64) throws {
        guard size <= ZipFormat.maxOffset, offset + size <= ZipFormat.maxOffset else { throw ZipArchiveError.tooLarge }
        let name = Data(path.utf8)
        // Flag 0x0800: the name is UTF-8. Method 0: stored.
        var header = Data()
        header.appendLE32(ZipFormat.localHeader)
        header.appendLE16(20)
        header.appendLE16(0x0800)
        header.appendLE16(0)
        header.appendLE16(dosTime)
        header.appendLE16(dosDate)
        header.appendLE32(crc)
        header.appendLE32(UInt32(size))
        header.appendLE32(UInt32(size))
        header.appendLE16(UInt16(name.count))
        header.appendLE16(0)
        header.append(name)

        directory.appendLE32(ZipFormat.centralHeader)
        directory.appendLE16(20)
        directory.appendLE16(20)
        directory.appendLE16(0x0800)
        directory.appendLE16(0)
        directory.appendLE16(dosTime)
        directory.appendLE16(dosDate)
        directory.appendLE32(crc)
        directory.appendLE32(UInt32(size))
        directory.appendLE32(UInt32(size))
        directory.appendLE16(UInt16(name.count))
        directory.appendLE16(0)
        directory.appendLE16(0)
        directory.appendLE16(0)
        directory.appendLE16(0)
        directory.appendLE32(0)
        directory.appendLE32(UInt32(offset))
        directory.append(name)

        try handle.write(contentsOf: header)
        offset += UInt64(header.count)
        count += 1
    }
}

/// Reads ZIP files written by `ZipFileWriter` (stored entries only).
struct ZipFileReader {
    struct Entry {
        let path: String
        let crc: UInt32
        let size: UInt64
        let method: UInt16
        let headerOffset: UInt64
    }

    let entries: [Entry]
    private let url: URL

    init(url: URL) throws {
        self.url = url
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        // The end record is 22 bytes plus a comment of up to 64 KB.
        let tailLength = min(fileSize, 22 + 65_535)
        try handle.seek(toOffset: fileSize - tailLength)
        let tail = try handle.read(upToCount: Int(tailLength)) ?? Data()
        guard tail.count >= 22,
              let endStart = stride(from: tail.count - 22, through: 0, by: -1)
                .first(where: { tail.le32(at: $0) == ZipFormat.endOfDirectory })
        else { throw ZipArchiveError.notAnArchive }
        let count = Int(tail.le16(at: endStart + 10))
        let directorySize = UInt64(tail.le32(at: endStart + 12))
        let directoryOffset = UInt64(tail.le32(at: endStart + 16))
        guard directoryOffset + directorySize <= fileSize else { throw ZipArchiveError.notAnArchive }
        try handle.seek(toOffset: directoryOffset)
        let directory = try handle.read(upToCount: Int(directorySize)) ?? Data()

        var entries: [Entry] = []
        var position = 0
        for _ in 0..<count {
            guard position + 46 <= directory.count,
                  directory.le32(at: position) == ZipFormat.centralHeader
            else { throw ZipArchiveError.notAnArchive }
            let nameLength = Int(directory.le16(at: position + 28))
            let extraLength = Int(directory.le16(at: position + 30))
            let commentLength = Int(directory.le16(at: position + 32))
            let nameStart = position + 46
            guard nameStart + nameLength <= directory.count else { throw ZipArchiveError.notAnArchive }
            let name = String(decoding: directory.subdata(in: nameStart..<nameStart + nameLength), as: UTF8.self)
            entries.append(Entry(
                path: name,
                crc: directory.le32(at: position + 16),
                size: UInt64(directory.le32(at: position + 24)),
                method: directory.le16(at: position + 10),
                headerOffset: UInt64(directory.le32(at: position + 42))
            ))
            position = nameStart + nameLength + extraLength + commentLength
        }
        self.entries = entries
    }

    /// A small entry, read into memory.
    func data(of entry: Entry) throws -> Data {
        var result = Data()
        try read(entry) { result.append($0) }
        return result
    }

    /// Copies the entry to `destination`, checking its checksum.
    func extract(_ entry: Entry, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        try read(entry) { try output.write(contentsOf: $0) }
    }

    private func read(_ entry: Entry, into consume: (Data) throws -> Void) throws {
        guard entry.method == 0 else { throw ZipArchiveError.unsupportedEntry(entry.path) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: entry.headerOffset)
        guard let header = try handle.read(upToCount: 30), header.count == 30,
              header.le32(at: 0) == ZipFormat.localHeader
        else { throw ZipArchiveError.notAnArchive }
        let skip = UInt64(header.le16(at: 26)) + UInt64(header.le16(at: 28))
        try handle.seek(toOffset: entry.headerOffset + 30 + skip)
        var remaining = entry.size
        var crc: UInt32 = 0
        while remaining > 0 {
            guard let chunk = try handle.read(upToCount: Int(min(remaining, UInt64(ZipFormat.chunkSize)))),
                  !chunk.isEmpty
            else { throw ZipArchiveError.damaged(entry.path) }
            crc = ZipFormat.crc(crc, chunk)
            try consume(chunk)
            remaining -= UInt64(chunk.count)
        }
        guard crc == entry.crc else { throw ZipArchiveError.damaged(entry.path) }
    }
}

private extension Data {
    mutating func appendLE16(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLE32(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    func le16(at offset: Int) -> UInt16 {
        let start = startIndex + offset
        return UInt16(self[start]) | UInt16(self[start + 1]) << 8
    }

    func le32(at offset: Int) -> UInt32 {
        let start = startIndex + offset
        return UInt32(self[start]) | UInt32(self[start + 1]) << 8
            | UInt32(self[start + 2]) << 16 | UInt32(self[start + 3]) << 24
    }
}
