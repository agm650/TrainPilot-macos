import Foundation

enum SequenceDecision: Equatable {
    case accept
    case duplicate
    case gap(expected: UInt64, received: UInt64)
}

struct SequenceTracker {
    private(set) var lastSequence: UInt64?

    mutating func reset(to sequence: UInt64) {
        lastSequence = sequence
    }

    mutating func evaluate(_ sequence: UInt64) -> SequenceDecision {
        guard let lastSequence else {
            return .gap(expected: 0, received: sequence)
        }

        if sequence <= lastSequence {
            return .duplicate
        }

        let expected = lastSequence + 1
        guard sequence == expected else {
            return .gap(expected: expected, received: sequence)
        }

        self.lastSequence = sequence
        return .accept
    }
}
