import Foundation

enum UpdateHTTPClient {
    static func isSecure(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host()?.isEmpty == false
            && url.user() == nil && url.password() == nil
    }

    @concurrent
    static func fetch(_ url: URL) async throws -> Data {
        guard isSecure(url) else { throw URLError(.unsupportedURL) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
            let responseURL = response.url, isSecure(responseURL)
        else { throw URLError(.badServerResponse) }

        let maximumResponseSize = 4 * 1024 * 1024
        guard response.expectedContentLength <= maximumResponseSize else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumResponseSize else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
}
