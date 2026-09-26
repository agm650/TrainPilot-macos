import CryptoKit
import Foundation

struct LayoutDraft: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    let draftFormatVersion: Int
    let serverIdentity: String
    let baseTopologyRevision: String
    let basePresentationRevision: String
    let savedAt: Date
    let topology: TopologyDefinition
    let presentation: LayoutPresentationDefinition
}

enum LayoutDraftStoreError: Error, Equatable {
    case unsupportedFormat(Int)
    case corrupted
}

protocol LayoutDraftStoring: Sendable {
    func load(serverIdentity: String) async throws -> LayoutDraft?
    func save(_ draft: LayoutDraft) async throws
    func delete(serverIdentity: String) async throws
}

actor LayoutDraftStore: LayoutDraftStoring {
    private struct VersionEnvelope: Decodable {
        let draftFormatVersion: Int
    }

    private let directoryURL: URL
    private let fileManager: FileManager

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager

        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            self.directoryURL = applicationSupport
                .appendingPathComponent("TrainPilot", isDirectory: true)
                .appendingPathComponent("LayoutDrafts", isDirectory: true)
        }
    }

    func load(serverIdentity: String) throws -> LayoutDraft? {
        let fileURL = draftURL(serverIdentity: serverIdentity)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder.trainPilot
            let envelope = try decoder.decode(VersionEnvelope.self, from: data)

            guard envelope.draftFormatVersion == LayoutDraft.currentFormatVersion else {
                throw LayoutDraftStoreError.unsupportedFormat(
                    envelope.draftFormatVersion
                )
            }

            let draft = try decoder.decode(LayoutDraft.self, from: data)
            guard draft.serverIdentity == serverIdentity else {
                return nil
            }
            return draft
        } catch let error as LayoutDraftStoreError {
            throw error
        } catch {
            throw LayoutDraftStoreError.corrupted
        }
    }

    func save(_ draft: LayoutDraft) throws {
        guard draft.draftFormatVersion == LayoutDraft.currentFormatVersion else {
            throw LayoutDraftStoreError.unsupportedFormat(
                draft.draftFormatVersion
            )
        }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(draft)
        try data.write(
            to: draftURL(serverIdentity: draft.serverIdentity),
            options: .atomic
        )
    }

    func delete(serverIdentity: String) throws {
        let fileURL = draftURL(serverIdentity: serverIdentity)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private func draftURL(serverIdentity: String) -> URL {
        let digest = SHA256.hash(data: Data(serverIdentity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        return directoryURL.appendingPathComponent("\(digest).json")
    }
}
