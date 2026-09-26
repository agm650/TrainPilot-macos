import Compression
import Foundation

enum LayoutArchiveError: LocalizedError, Equatable {
    case invalidArchive
    case missingEntry(String)
    case unsupportedCompression(UInt16)
    case invalidLayoutDocument

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "L’archive de layout est invalide."
        case .missingEntry(let name):
            return "L’archive ne contient pas \(name)."
        case .unsupportedCompression(let method):
            return "La méthode de compression ZIP \(method) n’est pas prise en charge."
        case .invalidLayoutDocument:
            return "Le document layout.json est invalide."
        }
    }
}

struct LayoutArchiveBuilder {
    @MainActor
    func build(
        from serverArchive: LayoutArchive,
        document: LayoutEditorDocument
    ) throws -> LayoutArchive {
        var entries = try ZIPContainer.read(serverArchive.data)
        guard entries["manifest.json"] != nil else {
            throw LayoutArchiveError.missingEntry("manifest.json")
        }
        guard let existingLayout = entries["layout.json"] else {
            throw LayoutArchiveError.missingEntry("layout.json")
        }

        guard var root = try JSONSerialization.jsonObject(with: existingLayout) as? [String: Any],
              var layout = root["layout"] as? [String: Any] else {
            throw LayoutArchiveError.invalidLayoutDocument
        }

        let topology = try dictionary(for: document.topology)
        layout["nodes"] = topology["nodes"]
        layout["trackSections"] = topology["trackSections"]
        layout["turnoutTopologies"] = topology["turnoutTopologies"]
        layout["blocks"] = topology["blocks"]
        layout["turnouts"] = try array(for: document.turnoutDefinitions)
        root["layout"] = layout

        var presentation = try dictionary(for: document.presentation)
        presentation.removeValue(forKey: "revision")
        root["presentation"] = presentation

        entries["layout.json"] = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )

        return LayoutArchive(
            data: ZIPContainer.write(entries),
            suggestedFilename: Self.draftFilename(from: serverArchive.suggestedFilename)
        )
    }

    static func draftFilename(from publishedFilename: String) -> String {
        let source = publishedFilename.isEmpty ? "TrainPilot-layout.dcclayout" : publishedFilename
        let url = URL(fileURLWithPath: source)
        let base = url.deletingPathExtension().lastPathComponent
        return "\(base)-draft.dcclayout"
    }

    private func dictionary<T: Encodable>(for value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LayoutArchiveError.invalidLayoutDocument
        }
        return result
    }

    private func array<T: Encodable>(for value: T) throws -> [Any] {
        let data = try JSONEncoder().encode(value)
        guard let result = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw LayoutArchiveError.invalidLayoutDocument
        }
        return result
    }
}

enum ZIPContainer {
    private static let localSignature: UInt32 = 0x04034b50
    private static let centralSignature: UInt32 = 0x02014b50
    private static let endSignature: UInt32 = 0x06054b50

    static func read(_ archive: Data) throws -> [String: Data] {
        guard let endOffset = findEndRecord(in: archive),
              let centralOffset = archive.uint32(at: endOffset + 16).map(Int.init),
              let entryCount = archive.uint16(at: endOffset + 10).map(Int.init) else {
            throw LayoutArchiveError.invalidArchive
        }

        var result: [String: Data] = [:]
        var cursor = centralOffset

        for _ in 0..<entryCount {
            guard archive.uint32(at: cursor) == centralSignature,
                  let method = archive.uint16(at: cursor + 10),
                  let compressedSize = archive.uint32(at: cursor + 20).map(Int.init),
                  let uncompressedSize = archive.uint32(at: cursor + 24).map(Int.init),
                  let nameLength = archive.uint16(at: cursor + 28).map(Int.init),
                  let extraLength = archive.uint16(at: cursor + 30).map(Int.init),
                  let commentLength = archive.uint16(at: cursor + 32).map(Int.init),
                  let localOffset = archive.uint32(at: cursor + 42).map(Int.init) else {
                throw LayoutArchiveError.invalidArchive
            }

            let nameStart = cursor + 46
            guard let name = String(data: archive.safeSubdata(nameStart, nameLength), encoding: .utf8),
                  archive.uint32(at: localOffset) == localSignature,
                  let localNameLength = archive.uint16(at: localOffset + 26).map(Int.init),
                  let localExtraLength = archive.uint16(at: localOffset + 28).map(Int.init) else {
                throw LayoutArchiveError.invalidArchive
            }

            let dataStart = localOffset + 30 + localNameLength + localExtraLength
            let compressed = archive.safeSubdata(dataStart, compressedSize)
            guard compressed.count == compressedSize else {
                throw LayoutArchiveError.invalidArchive
            }

            switch method {
            case 0:
                result[name] = compressed
            case 8:
                result[name] = try inflate(compressed, expectedSize: uncompressedSize)
            default:
                throw LayoutArchiveError.unsupportedCompression(method)
            }

            cursor = nameStart + nameLength + extraLength + commentLength
        }

        return result
    }

    static func write(_ entries: [String: Data]) -> Data {
        var archive = Data()
        var central = Data()
        let sortedEntries = entries.sorted { $0.key < $1.key }

        for (name, contents) in sortedEntries {
            let nameData = Data(name.utf8)
            let offset = UInt32(archive.count)
            let checksum = crc32(contents)

            archive.appendLE(localSignature)
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(0x0800))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(checksum)
            archive.appendLE(UInt32(contents.count))
            archive.appendLE(UInt32(contents.count))
            archive.appendLE(UInt16(nameData.count))
            archive.appendLE(UInt16(0))
            archive.append(nameData)
            archive.append(contents)

            central.appendLE(centralSignature)
            central.appendLE(UInt16(20))
            central.appendLE(UInt16(20))
            central.appendLE(UInt16(0x0800))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(checksum)
            central.appendLE(UInt32(contents.count))
            central.appendLE(UInt32(contents.count))
            central.appendLE(UInt16(nameData.count))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt32(0))
            central.appendLE(offset)
            central.append(nameData)
        }

        let centralOffset = UInt32(archive.count)
        archive.append(central)
        archive.appendLE(endSignature)
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(sortedEntries.count))
        archive.appendLE(UInt16(sortedEntries.count))
        archive.appendLE(UInt32(central.count))
        archive.appendLE(centralOffset)
        archive.appendLE(UInt16(0))
        return archive
    }

    private static func findEndRecord(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let lowerBound = max(0, data.count - 65_557)
        for offset in stride(from: data.count - 22, through: lowerBound, by: -1) {
            if data.uint32(at: offset) == endSignature {
                return offset
            }
        }
        return nil
    }

    private static func inflate(_ data: Data, expectedSize: Int) throws -> Data {
        guard expectedSize >= 0 else { throw LayoutArchiveError.invalidArchive }
        var output = Data(count: expectedSize)
        let decodedSize = output.withUnsafeMutableBytes { outputBuffer in
            data.withUnsafeBytes { inputBuffer in
                compression_decode_buffer(
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    expectedSize,
                    inputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decodedSize == expectedSize else {
            throw LayoutArchiveError.invalidArchive
        }
        return output
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (0xedb8_8320 & (0 &- (crc & 1)))
            }
        }
        return crc ^ 0xffff_ffff
    }
}

private extension Data {
    func safeSubdata(_ offset: Int, _ length: Int) -> Data {
        guard offset >= 0, length >= 0, offset <= count, length <= count - offset else {
            return Data()
        }
        return subdata(in: offset..<(offset + length))
    }

    func uint16(at offset: Int) -> UInt16? {
        let bytes = safeSubdata(offset, 2)
        guard bytes.count == 2 else { return nil }
        return UInt16(bytes[bytes.startIndex]) |
            UInt16(bytes[bytes.startIndex + 1]) << 8
    }

    func uint32(at offset: Int) -> UInt32? {
        let bytes = safeSubdata(offset, 4)
        guard bytes.count == 4 else { return nil }
        return UInt32(bytes[bytes.startIndex]) |
            UInt32(bytes[bytes.startIndex + 1]) << 8 |
            UInt32(bytes[bytes.startIndex + 2]) << 16 |
            UInt32(bytes[bytes.startIndex + 3]) << 24
    }

    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
