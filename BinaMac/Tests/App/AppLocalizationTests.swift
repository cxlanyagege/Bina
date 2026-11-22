import Foundation
import Testing

@Test func appAndControlExtensionResolveTheSimplifiedChineseName() throws {
    let app = Bundle.main
    let plugins = try #require(app.builtInPlugInsURL)
    let controlsURL = plugins.appending(path: "BinaMacControls.appex", directoryHint: .isDirectory)
    let controls = try #require(Bundle(url: controlsURL))
    let mainIdentifier = try #require(app.bundleIdentifier)
    #expect(controls.bundleIdentifier == "\(mainIdentifier).Controls")

    for bundle in [app, controls] {
        #expect(bundle.developmentLocalization == "zh-Hans")
        #expect(
            bundle.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: "zh-Hans")
                != nil)
        #expect(bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Bina")
        #expect(bundle.object(forInfoDictionaryKey: "CFBundleName") as? String == "Bina")
    }
}
