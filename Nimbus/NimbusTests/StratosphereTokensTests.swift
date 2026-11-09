import Testing
import Foundation
@testable import Nimbus

private typealias S = DesignSystem.Stratosphere

@Suite("Stratosphere tokens")
struct StratosphereTokensTests {

    // MARK: - Colour maths

    @Test func contrastOfBlackOnWhiteIsTwentyOne() {
        let ratio = S.RGBA.contrast(S.RGBA(hex: 0x000000), S.RGBA(hex: 0xFFFFFF))
        #expect(abs(ratio - 21) < 0.01)
    }

    @Test func compositingHalfWhiteOverBlackIsMidGrey() {
        let mixed = S.RGBA(hex: 0xFFFFFF, alpha: 0.5).over(S.RGBA(hex: 0x000000))
        #expect(abs(mixed.r - 0.5) < 0.001)
        #expect(mixed.a == 1)
    }

    // MARK: - Contrast

    /// Every point of a window's backdrop, sampled on a grid. The glows make
    /// the backdrop uneven, so one sample is not enough: the worst case sits
    /// near a glow's centre.
    private func backdropSamples(_ palette: S.Palette) -> [S.RGBA] {
        var samples: [S.RGBA] = []
        for xi in 0...24 {
            for yi in 0...16 {
                samples.append(palette.backdrop.color(x: Double(xi) / 24, y: Double(yi) / 16))
            }
        }
        return samples
    }

    private func worstContrast(of text: S.RGBA, on surfaces: [S.RGBA]) -> Double {
        surfaces.map { S.RGBA.contrast(text.over($0), $0) }.min() ?? 0
    }

    @Test(arguments: ["dark", "light"])
    func textHoldsContrastDirectlyOnTheBackdrop(name: String) {
        let palette = name == "dark" ? S.Palette.dark : S.Palette.light
        let backdrop = backdropSamples(palette)
        for (label, text) in [("primary", palette.textPrimary), ("secondary", palette.textSecondary),
                              ("tertiary", palette.textTertiary)] {
            let worst = worstContrast(of: text, on: backdrop)
            #expect(worst >= 4.5, "\(name) \(label) text on backdrop: \(worst)")
        }
    }

    @Test(arguments: ["dark", "light"])
    func textHoldsContrastOnGlassAnywhereOverTheBackdrop(name: String) {
        let palette = name == "dark" ? S.Palette.dark : S.Palette.light
        // The top of a glass surface is its lightest stop in dark mode and
        // the only stop that matters for the worst case.
        let glass = backdropSamples(palette).flatMap {
            [palette.glassTop.over($0), palette.glassBottom.over($0)]
        }
        for (label, text) in [("primary", palette.textPrimary), ("secondary", palette.textSecondary),
                              ("tertiary", palette.textTertiary)] {
            let worst = worstContrast(of: text, on: glass)
            #expect(worst >= 4.5, "\(name) \(label) text on glass: \(worst)")
        }
    }

    @Test(arguments: ["dark", "light"])
    func textOnFilledControlsHoldsContrast(name: String) {
        let palette = name == "dark" ? S.Palette.dark : S.Palette.light
        #expect(S.RGBA.contrast(palette.onAction, palette.actionTop) >= 4.5)
        #expect(S.RGBA.contrast(palette.onAction, palette.actionBottom) >= 4.5)
        #expect(S.RGBA.contrast(palette.onAction, palette.rowSelection) >= 4.5)
    }

    @Test(arguments: ["dark", "light"])
    func opaqueFallbackSurfaceHoldsContrast(name: String) {
        // Reduce Transparency swaps glass for this fill.
        let palette = name == "dark" ? S.Palette.dark : S.Palette.light
        let surface = [palette.opaqueSurface]
        #expect(worstContrast(of: palette.textTertiary, on: surface) >= 4.5)
    }

    // MARK: - Cloud colours

    @Test func knownProviderGetsItsOwnColour() {
        let assigned = S.CloudColors.assign([(name: "Personal", provider: "drive")])
        #expect(assigned["Personal"] == S.CloudColors.color(forProvider: "drive"))
    }

    @Test func assignmentDoesNotDependOnInputOrder() {
        let remotes = [(name: "Personal", provider: "drive"), (name: "Work", provider: "onedrive"),
                       (name: "MCS", provider: "drive"), (name: "Archive", provider: "b2")]
        #expect(S.CloudColors.assign(remotes) == S.CloudColors.assign(remotes.reversed()))
    }

    @Test func twoRemotesOnOneProviderGetDifferentColours() {
        let assigned = S.CloudColors.assign([(name: "Google Drive", provider: "drive"),
                                             (name: "MCS", provider: "drive")])
        #expect(assigned["Google Drive"] != assigned["MCS"])
    }

    @Test func manyRemotesOnOneProviderStayDistinct() {
        let names = ["a", "b", "c", "d", "e"]
        let assigned = S.CloudColors.assign(names.map { (name: $0, provider: "drive") })
        #expect(Set(names.compactMap { assigned[$0] }).count == names.count)
    }

    @Test func unknownProviderGetsTheSameFallbackEveryTime() {
        let first = S.CloudColors.color(forProvider: "someNewBackend")
        let second = S.CloudColors.color(forProvider: "someNewBackend")
        #expect(first == second)
    }

    @Test func providerSpellingsShareAColour() {
        // `ProviderCatalog.canonicalKey` already folds these; colours must too.
        #expect(S.CloudColors.color(forProvider: "Google Cloud Storage") == S.CloudColors.color(forProvider: "gcs"))
    }
}
