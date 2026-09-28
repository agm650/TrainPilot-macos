import Foundation

public struct TransferArchive: Equatable, Sendable {
    public let data: Data
    public let suggestedFilename: String

    public init(data: Data, suggestedFilename: String) {
        self.data = data
        self.suggestedFilename = suggestedFilename
    }
}

public protocol RollingStockArchiveTransferring: Sendable {
    func importRollingStockArchive(_ data: Data) async throws
    func exportRollingStockArchive() async throws -> TransferArchive
}
