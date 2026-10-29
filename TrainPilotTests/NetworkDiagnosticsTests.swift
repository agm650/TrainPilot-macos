import Foundation
import Testing
@testable import TrainPilot

struct NetworkDiagnosticsTests {
    @Test func removesCredentialsAndSensitiveQueryValues() throws {
        let url = try #require(URL(string:
            "https://user:password@example.test:8443/api/v1/layout/validate?mode=replace&token=secret#private"
        ))
        #expect(NetworkDiagnostics.origin(url) == "https://example.test:8443")
        #expect(NetworkDiagnostics.endpoint(url) == "/api/v1/layout/validate?mode=replace")
    }

    @Test func omitsUnrecognizedModeAndAllOtherQueries() throws {
        let url = try #require(URL(string:
            "https://example.test/api/v1/auth/login?mode=secret&password=hidden"
        ))
        #expect(NetworkDiagnostics.endpoint(url) == "/api/v1/auth/login")
        #expect(NetworkDiagnostics.endpoint(nil) == "<URL unavailable>")
        #expect(NetworkDiagnostics.origin(nil) == "<server unavailable>")
    }

    @Test func recognizesExpectedCancellationWithoutHidingOtherFailures() {
        #expect(NetworkDiagnostics.isCancellation(CancellationError()))
        #expect(NetworkDiagnostics.isCancellation(URLError(.cancelled)))
        #expect(NetworkDiagnostics.isCancellation(
            NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        ))
        #expect(!NetworkDiagnostics.isCancellation(URLError(.timedOut)))
        #expect(!NetworkDiagnostics.isCancellation(APIError.httpStatus(404)))
    }

    @Test func transferErrorsIdentifyStageAndRetainHTTPStatus() {
        let validation = LayoutTransferError(stage: .validation, underlying: APIError.httpStatus(404))
        let importing = LayoutTransferError(stage: .importing, underlying: APIError.httpStatus(404))
        let reloading = LayoutTransferError(stage: .reloading, underlying: APIError.httpStatus(404))
        #expect(validation.localizedDescription.contains("Aucun import"))
        #expect(importing.localizedDescription.contains("requête d’import"))
        #expect(reloading.localizedDescription.contains("confirmé l’import"))
        #expect(reloading.localizedDescription.contains("404"))
        #expect(validation.localizedDescription != importing.localizedDescription)
    }
}
