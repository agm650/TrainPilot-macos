import Foundation
import OSLog

enum NetworkDiagnostics {
    static let http = Logger(subsystem: "TrainPilot", category: "HTTP")
    static let layout = Logger(subsystem: "TrainPilot", category: "Layout")

    // Never log credentials, fragments, arbitrary query values or request/response bodies.
    static func endpoint(_ url: URL?) -> String {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return "<URL unavailable>"
        }
        var result = components.path
        if let mode = components.queryItems?.first(where: { $0.name == "mode" })?.value,
           ["replace", "merge"].contains(mode) {
            result += "?mode=" + mode
        }
        return result
    }

    static func origin(_ url: URL?) -> String {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return "<server unavailable>"
        }
        components.user = nil
        components.password = nil
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.string ?? "<server unavailable>"
    }

    static func isCancellation(_ error: Error) -> Bool {
        let value = error as NSError
        return error is CancellationError ||
            (value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled) ||
            (value.domain == NSCocoaErrorDomain && value.code == NSUserCancelledError)
    }
}

struct LayoutTransferError: LocalizedError {
    enum Stage {
        case validation, importing, reloading
    }

    let stage: Stage
    let underlying: Error

    var errorDescription: String? {
        let explanation: String
        switch stage {
        case .validation: explanation = "Échec de validation du layout. Aucun import n’a été envoyé."
        case .importing: explanation = "Échec de la requête d’import du layout."
        case .reloading: explanation = "Le serveur a confirmé l’import, mais le rechargement du plan a échoué."
        }
        return explanation + "\n" + underlying.localizedDescription
    }
}
