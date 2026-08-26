import Foundation
import Testing

@testable import Zyncloud

/// The error ladder in ``APIClient/validate(data:response:error:)``.
///
/// Every single endpoint in the app funnels its `URLSession` callback through this one static
/// function, so a wrong rung here is a wrong error message — or a swallowed failure — on all of
/// them at once. It is pure, which makes it cheap to pin down completely.
struct APIValidationTests {
    // MARK: - Helpers

    private func http(_ status: Int, url: String = "https://example.test/api/albums") -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: url)!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }

    private func validate(
        data: Data? = Data("{}".utf8),
        response: URLResponse? = nil,
        error: Error? = nil,
        status: Int? = nil,
    ) -> Result<(body: Data, statusCode: Int), Error> {
        let resolved = response ?? status.map { http($0) }
        return APIClient.validate(data: data, response: resolved, error: error)
    }

    /// The failure as an ``AppError``, or `nil` if it succeeded or failed as something else.
    private func appError(_ result: Result<(body: Data, statusCode: Int), Error>) -> AppError? {
        guard case let .failure(error) = result else { return nil }
        return error as? AppError
    }

    private struct Transport: Error {}

    // MARK: - Rung 1: the transport failed

    @Test func aTransportErrorIsReportedAsANetworkError() throws {
        let result = validate(error: Transport(), status: 200)

        guard case .network = try #require(appError(result)) else {
            Issue.record("expected .network")
            return
        }
    }

    /// The transport error is checked before anything else, so it wins even when the response
    /// looks perfectly serviceable. A `URLSession` that reports both is reporting a failure.
    @Test func theTransportErrorOutranksAnOtherwiseFineResponse() throws {
        let result = validate(data: Data("{\"success\":true}".utf8), error: Transport(), status: 200)

        guard case .network = try #require(appError(result)) else {
            Issue.record("expected .network to win over the 200")
            return
        }
    }

    // MARK: - Rung 2: no body

    @Test func aMissingBodyIsAnApiErrorWithNoStatusCode() throws {
        let result = validate(data: nil, status: 200)

        guard case let .api(message, statusCode) = try #require(appError(result)) else {
            Issue.record("expected .api")
            return
        }
        #expect(message == "No data received")
        #expect(statusCode == nil)
    }

    /// Zero bytes is not the same as no bytes: a `204 No Content` hands back an empty `Data`,
    /// and `performRequestIgnoringBody` relies on that reaching the success rung.
    @Test func anEmptyBodyIsNotAMissingBody() throws {
        let result = validate(data: Data(), status: 204)

        let ok = try #require(try? result.get())
        #expect(ok.body.isEmpty)
        #expect(ok.statusCode == 204)
    }

    // MARK: - Rung 3: not an HTTP response

    @Test func aNonHttpResponseIsAnApiErrorWithNoStatusCode() throws {
        let response = URLResponse(
            url: URL(string: "https://example.test/api/albums")!,
            mimeType: "application/json",
            expectedContentLength: 2,
            textEncodingName: nil,
        )
        let result = validate(response: response)

        guard case let .api(message, statusCode) = try #require(appError(result)) else {
            Issue.record("expected .api")
            return
        }
        #expect(message == "Invalid response")
        #expect(statusCode == nil)
    }

    @Test func aNilResponseIsAlsoAnInvalidResponse() throws {
        let result = validate(response: nil)

        guard case let .api(message, statusCode) = try #require(appError(result)) else {
            Issue.record("expected .api")
            return
        }
        #expect(message == "Invalid response")
        #expect(statusCode == nil)
    }

    // MARK: - Rung 4: the status code

    @Test(arguments: [200, 201, 202, 204, 299])
    func everyTwoHundredIsSuccessAndCarriesItsOwnCodeBack(status: Int) throws {
        let body = Data("{\"success\":true}".utf8)
        let ok = try #require(try? validate(data: body, status: status).get())

        #expect(ok.statusCode == status)
        #expect(ok.body == body)
    }

    /// The success window is exactly 200...299. 199 and 300 are the two that a `<` / `<=` slip
    /// would move, so they are the two worth naming.
    @Test(arguments: [100, 199, 300, 301, 304, 400, 401, 403, 404, 413, 429, 500, 503])
    func everythingOutsideTwoHundredIsAFailure(status: Int) throws {
        let result = validate(data: Data("not json".utf8), status: status)

        guard case let .api(message, statusCode) = try #require(appError(result)) else {
            Issue.record("expected .api for HTTP \(status)")
            return
        }
        #expect(message == APIClient.plainMeaning(of: status))
        #expect(message.contains("HTTP \(status)"))
        #expect(statusCode == status)
    }

    /// The fallback message is for a person, so it is a sentence — but it still ends with the
    /// code, because that is the half a bug report needs. Both halves are pinned: a rewrite that
    /// drops the number would leave "The server had a problem." with nothing to chase.
    @Test(arguments: [401, 403, 404, 409, 413, 429, 500, 503, 418])
    func theFallbackMessageReadsAsASentenceAndKeepsTheCode(status: Int) {
        let message = APIClient.plainMeaning(of: status)

        #expect(message.hasSuffix("(HTTP \(status))"))
        #expect(message.first?.isUppercase == true)
        #expect(message != "(HTTP \(status))", "the sentence itself must not be empty")
    }

    /// When the server bothered to explain itself, the user should read the server's words and
    /// not a generic sentence.
    @Test func aServerErrorBodyReplacesTheGenericMessage() throws {
        let body = Data("{\"success\":false,\"message\":\"Album name already taken\"}".utf8)
        let result = validate(data: body, status: 409)

        guard case let .api(message, statusCode) = try #require(appError(result)) else {
            Issue.record("expected .api")
            return
        }
        #expect(message == "Album name already taken")
        #expect(statusCode == 409)
    }

    /// ``ErrorResponse`` needs both `success` and `message`; JSON carrying only one of them is
    /// not an error envelope, and must fall back rather than decode to something half-empty.
    @Test(arguments: [
        "{\"success\":false}",
        "{\"message\":\"Nope\"}",
        "{}",
        "[]",
        "null",
        "",
        "<html>502 Bad Gateway</html>",
    ])
    func aBodyThatIsNotAnErrorEnvelopeFallsBackToTheStatusLine(json: String) throws {
        let result = validate(data: Data(json.utf8), status: 502)

        guard case let .api(message, statusCode) = try #require(appError(result)) else {
            Issue.record("expected .api for body \(json)")
            return
        }
        #expect(message == APIClient.plainMeaning(of: 502))
        #expect(statusCode == 502)
    }

    /// A 2xx is never inspected for an error envelope — a body that happens to say
    /// `success: false` still succeeds here, because deciding that is the caller's job.
    @Test func anErrorEnvelopeUnderATwoHundredIsStillASuccess() throws {
        let body = Data("{\"success\":false,\"message\":\"soft failure\"}".utf8)
        let ok = try #require(try? validate(data: body, status: 200).get())

        #expect(ok.statusCode == 200)
        #expect(ok.body == body)
    }

    /// The body comes back untouched, bytes and all — the decode downstream is handed exactly
    /// what the server sent.
    @Test func theBodyIsHandedBackUnmodified() throws {
        let body = Data([0x00, 0xFF, 0x10, 0x7F])
        let ok = try #require(try? validate(data: body, status: 200).get())

        #expect(ok.body == body)
    }
}
