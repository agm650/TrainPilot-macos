import Foundation

/// Serializes ON/OFF per lease and function, including overlapping mouse/key presses.
@MainActor
final class MomentaryFunctionController {
    struct Key: Hashable {
        let locomotiveID: String
        let leaseID: String
        let function: Int
    }

    private final class Hold {
        var tokens: Set<UUID> = []
        var attempted = false
    }

    private var holds: [Key: Hold] = [:]
    private var tokens: [UUID: Key] = [:]
    private var pending: [Key: (id: UUID, task: Task<Void, Never>)] = [:]
    var canSend: (Key, Bool) -> Bool = { _, _ in false }
    var send: (Key, Bool) async throws -> Void = { _, _ in }
    var onFailure: (Error) -> Void = { _ in }

    func press(_ key: Key) -> UUID? {
        guard canSend(key, true) else { return nil }
        let token = UUID()
        tokens[token] = key
        if let hold = holds[key] {
            hold.tokens.insert(token)
            return token
        }
        let hold = Hold()
        hold.tokens.insert(token)
        holds[key] = hold
        enqueue(key) { [weak self] in
            guard let self, !hold.tokens.isEmpty, self.canSend(key, true) else { return }
            // Even a failed response can mean ON reached the station; OFF must follow.
            hold.attempted = true
            do {
                try await self.send(key, true)
            } catch {
                self.releaseAll()
                self.onFailure(error)
            }
        }
        return token
    }

    func release(_ token: UUID) {
        guard let key = tokens.removeValue(forKey: token), let hold = holds[key] else { return }
        hold.tokens.remove(token)
        guard hold.tokens.isEmpty else { return }
        holds.removeValue(forKey: key)
        enqueue(key) { [weak self] in
            guard let self, hold.attempted, self.canSend(key, false) else { return }
            do {
                try await self.send(key, false)
            } catch {
                self.onFailure(error)
            }
        }
    }

    func releaseAll() {
        for token in Array(tokens.keys) { release(token) }
    }

    private func enqueue(_ key: Key, operation: @escaping @MainActor () async -> Void) {
        let previous = pending[key]?.task
        let id = UUID()
        let task = Task { [weak self] in
            await previous?.value
            await operation()
            if self?.pending[key]?.id == id { self?.pending.removeValue(forKey: key) }
        }
        pending[key] = (id, task)
    }

    func waitForPendingCommands() async {
        while let task = pending.values.first?.task { await task.value }
    }
}
