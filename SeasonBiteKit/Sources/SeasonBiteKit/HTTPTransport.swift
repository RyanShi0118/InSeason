import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends one HTTP request. Swapped for a fake in tests.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

/// A provider answered with a non-2xx status.
public struct ProviderHTTPError: LocalizedError, Equatable {
    public var provider: String
    public var status: Int
    public var body: String

    public var errorDescription: String? {
        "\(provider) returned HTTP \(status): \(body.prefix(300))"
    }
}

func checkStatus(_ data: Data, _ response: HTTPURLResponse, provider: String) throws {
    guard (200..<300).contains(response.statusCode) else {
        throw ProviderHTTPError(
            provider: provider,
            status: response.statusCode,
            body: String(decoding: data, as: UTF8.self)
        )
    }
}

func jsonRequest(url: URL, apiKey: String, body: some Encodable, timeout: TimeInterval) throws -> URLRequest {
    var request = URLRequest(url: url, timeoutInterval: timeout)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONEncoder().encode(body)
    return request
}
