import Foundation
import Testing

@testable import BinaMac

@Suite("Curated update sources")
struct PublishedApplicationUpdateTests {
    @Test func selectsTheHighestStableOpenCodeVersionInTheInstalledSeriesForThisMac() async throws {
        let checker = PublishedApplicationUpdateChecker(
            isAppleSilicon: true,
            fetch: { url in
                #expect(url.path() == "/repos/anomalyco/opencode/releases")
                #expect(url.query() == "per_page=20")
                return Data(
                    """
                    [
                      {"tag_name":"v3.0.0","draft":false,"prerelease":false,
                       "assets":[{"name":"opencode-desktop-mac-arm64.dmg","state":"uploaded"}]},
                      {"tag_name":"v2.8.0","draft":true,"prerelease":false,
                       "assets":[{"name":"opencode-desktop-mac-arm64.dmg","state":"uploaded"}]},
                      {"tag_name":"v2.7.0","draft":false,"prerelease":true,
                       "assets":[{"name":"opencode-desktop-mac-arm64.dmg","state":"uploaded"}]},
                      {"tag_name":"v2.6.0","draft":false,"prerelease":false,
                       "assets":[{"name":"opencode-desktop-mac-x64.dmg","state":"uploaded"}]},
                      {"tag_name":"v2.4.2","draft":false,"prerelease":false,
                       "assets":[{"name":"opencode-desktop-mac-arm64.dmg","state":"uploaded"}]},
                      {"tag_name":"v2.4.1","draft":false,"prerelease":false,
                       "assets":[{"name":"opencode-desktop-mac-arm64.dmg","state":"uploaded"}]}
                    ]
                    """.utf8)
            })

        let result = try #require(await checker.checkIfKnown(metadata("ai.opencode.desktop", version: "2.4.0")))
        #expect(result.outcome == .available(ApplicationVersion(shortVersion: "2.4.2", buildVersion: nil)))
        guard case .github(let repository, let releasesURL) = result.source else {
            Issue.record("Expected a GitHub release as the update source.")
            return
        }
        #expect(repository == "anomalyco/opencode")
        #expect(releasesURL.absoluteString == "https://github.com/anomalyco/opencode/releases")
    }

    @Test func doesNotReportAReleaseWithoutTheMappedMacPackage() async throws {
        let checker = PublishedApplicationUpdateChecker { url in
            #expect(url.path() == "/repos/ollama/ollama/releases/latest")
            return Data(
                """
                {"tag_name":"v0.40.18","draft":false,"prerelease":false,
                 "assets":[{"name":"ollama-darwin.tgz","state":"uploaded"},
                           {"name":"Ollama-darwin.zip","state":"new"}]}
                """.utf8)
        }
        let result = try #require(await checker.checkIfKnown(metadata("com.electron.ollama", version: "0.40.17")))
        #expect(result.outcome == .noMatchingRelease)
    }

    @Test func usesTheOfficialStableVSCodeVersionField() async throws {
        let checker = PublishedApplicationUpdateChecker { url in
            #expect(url.host() == "update.code.visualstudio.com")
            #expect(url.path() == "/api/update/darwin-universal/stable/latest")
            return Data(#"{"version":"abcdef1234","productVersion":"1.10.0","supportsFastUpdate":true}"#.utf8)
        }
        let result = try #require(await checker.checkIfKnown(metadata("com.microsoft.VSCode", version: "1.9.0")))
        #expect(result.outcome == .available(ApplicationVersion(shortVersion: "1.10.0", buildVersion: nil)))
    }

    @Test func usesTheDownloadPageForManualChecksAndIgnoresUnmappedVariants() async throws {
        let checker = PublishedApplicationUpdateChecker { _ in
            Issue.record("Manual and unrecognized sources should not send a request.")
            throw URLError(.unsupportedURL)
        }
        let result = try #require(await checker.checkIfKnown(metadata("com.anythingllm", version: "1.2")))
        #expect(result.outcome == .manualCheck)
        #expect(result.source == .website(downloadPage: try #require(URL(string: "https://anythingllm.com/download"))))
        #expect(await checker.checkIfKnown(metadata("com.microsoft.VSCodeInsiders", version: "1.10")) == nil)
    }

    private func metadata(_ id: String, version: String) -> ApplicationBundleMetadata {
        ApplicationBundleMetadata(info: ["CFBundleIdentifier": id, "CFBundleShortVersionString": version])
    }
}
