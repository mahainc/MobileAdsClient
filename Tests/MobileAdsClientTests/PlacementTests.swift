import Foundation
import Testing
@testable import MobileAdsClient

@Suite("MobileAdsClient placements")
struct PlacementTests {

    @Test("AdPlacement descriptions match remote config field names")
    func adPlacementDescriptions() {
        #expect(MobileAdsClient.AdPlacement.interRecorder.description == "interRecorder")
    }

    @Test("AdPlacement remoteConfigKey is stable per case")
    func adPlacementRemoteConfigKey() {
        #expect(MobileAdsClient.AdPlacement.interRecorder.remoteConfigKey == "interRecorder")
    }

    @Test("RewardPlacement descriptions match remote config field names")
    func rewardPlacementDescriptions() {
        #expect(MobileAdsClient.RewardPlacement.watchAds.description == "watchAds")
    }

    @Test("NativeAllPlacement descriptions match remote config field names")
    func nativeAllPlacementDescriptions() {
        #expect(MobileAdsClient.NativeAllPlacement.nativeAppearance.description == "nativeAppearance")
        #expect(MobileAdsClient.NativeAllPlacement.nativeLanguageSetting.description == "nativeLanguageSetting")
    }

    @Test("CaseIterable.allCases enumerates every placement")
    func allCasesCoverage() {
        #expect(MobileAdsClient.AdPlacement.allCases.count == 1)
        #expect(MobileAdsClient.RewardPlacement.allCases.count == 1)
        #expect(MobileAdsClient.NativeAllPlacement.allCases.count == 2)
    }

    @Test("testValue has non-throwing stubs for all closures")
    func testValueStubs() async throws {
        let client = MobileAdsClient.testValue
        try await client.showPlacement(.interRecorder, [])
        await client.preloadPlacement(.interRecorder)
        #expect(await client.showRewardPlacement(.watchAds) == true)
        #expect(await client.isNativeAllPlacementEnabled(.nativeAppearance) == true)
        #expect(await client.nativeAllAdUnitID() == "test-native-unit")
        await client.installRevenueBridge()
    }

    @Test("adsDisabled mock grants reward but disables native")
    func adsDisabledMock() async {
        let client = MobileAdsClient.adsDisabled
        #expect(await client.shouldShowAd(.interstitial("x"), []) == false)
        #expect(await client.showRewardPlacement(.watchAds) == true)
        #expect(await client.isNativeAllPlacementEnabled(.nativeAppearance) == false)
        #expect(await client.nativeAllAdUnitID() == "")
    }

    @Test("AdRule priority engine early-exits on failure")
    func ruleEngineEarlyExit() async {
        let failing = MobileAdsClient.AdRule(name: "failing", priority: 10) { false }
        let passing = MobileAdsClient.AdRule(name: "passing", priority: 1) { true }
        let satisfied = await [passing, failing].allRulesSatisfied()
        #expect(satisfied == false)
    }
}
