import Foundation

/// A ZIP archive with every file stored as is (no compression), the format Office files use
/// (ADR-563). Deterministic: the same files in the same order always give the same bytes, with
/// every timestamp at 1 January 1980. Foundation has no ZIP writer on iOS, and the files Doddy
/// makes are small, so storing beats bringing in a compression library.
public enum StoredZip {
    public struct Entry: Equatable, Sendable {
        public let path: String
        public let data: Data

        public init(_ path: String, _ data: Data) {
            self.path = path
            self.data = data
        }
    }

    public enum Failure: Error, Equatable {
        /// A ZIP without the 64-bit extension holds at most 65,535 files of under 4 GB each.
        case tooLarge
    }

    public static func archive(_ entries: [Entry]) throws -> Data {
        guard entries.count < 0xFFFF else { throw Failure.tooLarge }
        var out = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.path.utf8)
            guard entry.data.count < 0xFFFF_FFFF, out.count < 0xFFFF_FFFF, name.count < 0xFFFF else { throw Failure.tooLarge }
            let crc = CRC32.checksum(entry.data)
            let offset = UInt32(out.count)
            let size = UInt32(entry.data.count)

            out.append(le32: 0x0403_4B50)      // local file header
            out.append(le16: 20)               // version needed: 2.0
            out.append(le16: 0x0800)           // names are UTF-8
            out.append(le16: 0)                // stored
            out.append(le16: 0)                // time 00:00
            out.append(le16: 0x0021)           // date 1980-01-01
            out.append(le32: crc)
            out.append(le32: size)             // compressed size
            out.append(le32: size)             // uncompressed size
            out.append(le16: UInt16(name.count))
            out.append(le16: 0)                // no extra field
            out.append(name)
            out.append(entry.data)

            central.append(le32: 0x0201_4B50)  // central directory header
            central.append(le16: 20)           // made by: 2.0, MS-DOS attributes
            central.append(le16: 20)
            central.append(le16: 0x0800)
            central.append(le16: 0)
            central.append(le16: 0)
            central.append(le16: 0x0021)
            central.append(le32: crc)
            central.append(le32: size)
            central.append(le32: size)
            central.append(le16: UInt16(name.count))
            central.append(le16: 0)            // extra
            central.append(le16: 0)            // comment
            central.append(le16: 0)            // disk
            central.append(le16: 0)            // internal attributes
            central.append(le32: 0)            // external attributes
            central.append(le32: offset)
            central.append(name)
        }
        guard out.count < 0xFFFF_FFFF, central.count < 0xFFFF_FFFF else { throw Failure.tooLarge }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(le32: 0x0605_4B50)          // end of central directory
        out.append(le16: 0)
        out.append(le16: 0)
        out.append(le16: UInt16(entries.count))
        out.append(le16: UInt16(entries.count))
        out.append(le32: UInt32(central.count))
        out.append(le32: centralOffset)
        out.append(le16: 0)                    // no comment
        return out
    }
}

/// CRC-32 as ZIP uses it (polynomial 0xEDB88320).
public enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    public static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Data {
    mutating func append(le16 value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func append(le32 value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) {
            append(UInt8((value >> UInt32(shift)) & 0xFF))
        }
    }
}
