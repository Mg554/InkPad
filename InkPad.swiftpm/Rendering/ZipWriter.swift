import Foundation

/// Builds a ZIP archive with its files stored uncompressed, which Office
/// documents such as .pptx accept.
struct ZipWriter {
    private var body = Data()
    private var directory = Data()
    private var count = 0

    mutating func add(_ path: String, _ contents: Data) {
        let name = Data(path.utf8)
        let crc = Self.crc32(contents)
        let size = UInt32(contents.count)
        let offset = UInt32(body.count)
        // Local file header. Flag 0x0800: the name is UTF-8. Date: 1 Jan 1980.
        body.append(Self.le32(0x0403_4b50))
        body.append(Self.le16(20))
        body.append(Self.le16(0x0800))
        body.append(Self.le16(0))
        body.append(Self.le16(0))
        body.append(Self.le16(0x21))
        body.append(Self.le32(crc))
        body.append(Self.le32(size))
        body.append(Self.le32(size))
        body.append(Self.le16(UInt16(name.count)))
        body.append(Self.le16(0))
        body.append(name)
        body.append(contents)
        // Its central directory entry.
        directory.append(Self.le32(0x0201_4b50))
        directory.append(Self.le16(20))
        directory.append(Self.le16(20))
        directory.append(Self.le16(0x0800))
        directory.append(Self.le16(0))
        directory.append(Self.le16(0))
        directory.append(Self.le16(0x21))
        directory.append(Self.le32(crc))
        directory.append(Self.le32(size))
        directory.append(Self.le32(size))
        directory.append(Self.le16(UInt16(name.count)))
        directory.append(Self.le16(0))
        directory.append(Self.le16(0))
        directory.append(Self.le16(0))
        directory.append(Self.le16(0))
        directory.append(Self.le32(0))
        directory.append(Self.le32(offset))
        directory.append(name)
        count += 1
    }

    mutating func add(_ path: String, text: String) {
        add(path, Data(text.utf8))
    }

    /// The finished archive.
    func data() -> Data {
        var archive = body
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.append(Self.le32(0x0605_4b50))
        archive.append(Self.le16(0))
        archive.append(Self.le16(0))
        archive.append(Self.le16(UInt16(count)))
        archive.append(Self.le16(UInt16(count)))
        archive.append(Self.le32(UInt32(directory.count)))
        archive.append(Self.le32(directoryOffset))
        archive.append(Self.le16(0))
        return archive
    }

    private static func le16(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func le32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 != 0 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    private static func crc32(_ data: Data) -> UInt32 {
        let table = crcTable
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
