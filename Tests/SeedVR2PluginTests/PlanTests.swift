import Foundation
import GaeaProtocol
import MLXSeedVR2
import SeedVR2Plugin
import Testing

@Suite struct PlanTests {
    @Test func theRequestCarriesTheVideoAndScale() {
        let r = request(video: Data([1, 2, 3]), scale: 4)
        #expect(r.scale == 4 && r.video.data == Data([1, 2, 3]) && r.video.format == .mp4)
    }

    @Test func eachTierHasOneLaneAtItsQuant() {
        #expect(lane(.int8).id == "int8" && (lane(.int8).configuration as? SeedVR2Configuration)?.quant == .int8)
        #expect(lane(.fp16).id == "fp16" && (lane(.fp16).configuration as? SeedVR2Configuration)?.quant == .fp16)
        #expect((lane(.int8).configuration as? SeedVR2Configuration)?.temporalWindow == 9)
    }

    @Test func theOffersStateTheirLimitsAndTiers() throws {
        #expect(scales == [2, 4] && maxWidth == 1920 && maxHeight == 1080 && maxSourceSeconds == 60)
        let offers = seedvr2Plugin.offers
        #expect(offers.map { $0.model["id"]?.stringValue } == [int8ID, fp16ID])
        #expect(offers[0].model["quality_tiers"] == ["draft", "standard"] && offers[1].model["quality_tiers"] == ["best"])
        #expect(offers.allSatisfy { $0.model["supports"]?["content"] == ["live_action", "drawn"] && $0.defaults == ["scale": 2] })
    }
}
