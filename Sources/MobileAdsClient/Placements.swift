//
//  Placements.swift
//  MobileAdsClient
//
//  Placement-aware ad types. `remoteConfigKey` is the stable identifier used to
//  look the placement up in Remote Config — renaming a Swift case does not
//  silently change the key.
//

import Foundation

extension MobileAdsClient {

    /// Interstitial placements. Cases resolve to `v2.interstitials.<key>` in
    /// Remote Config.
    public enum AdPlacement: Sendable, Equatable, CaseIterable, CustomStringConvertible {
        case interRecorder
        case home

        public var remoteConfigKey: String {
            switch self {
            case .interRecorder: return "recorder"
            case .home:          return "home"
            }
        }

        public var description: String { remoteConfigKey }
    }

    /// Rewarded placements driven by `rewardAll.extraKeys` in Remote Config.
    /// Cases must match fields in `RemoteConfigClient.RewardAllConfig`.
    public enum RewardPlacement: Sendable, Equatable, CaseIterable, CustomStringConvertible {
        case watchAds

        public var remoteConfigKey: String {
            switch self {
            case .watchAds: return "watchAds"
            }
        }

        public var description: String { remoteConfigKey }
    }

    /// Native-ad placements driven by `nativeAll.extraKeys` in Remote Config.
    /// Cases must match fields in `RemoteConfigClient.NativeAllConfig`.
    public enum NativeAllPlacement: Sendable, Equatable, CaseIterable, CustomStringConvertible {
        case nativeAppearance
        case nativeLanguageSetting

        public var remoteConfigKey: String {
            switch self {
            case .nativeAppearance: return "nativeAppearance"
            case .nativeLanguageSetting: return "nativeLanguageSetting"
            }
        }

        public var description: String { remoteConfigKey }
    }

    /// v2 native-ad placements mapped 1:1 to slots under `ad_config_v2.natives.*`.
    /// Resolved by `MobileAdsClient.nativeAdUnitID(_:)` at call time; the closure
    /// returns `""` when any enclosing gate is off or the slot is missing.
    public enum NativeAdPlacement: Sendable, Equatable, Hashable, CustomStringConvertible {
        case language
        case languageSelected
        case introStep(Int)
        case fallback

        public var description: String {
            switch self {
            case .language:          return "language"
            case .languageSelected:  return "languageSelected"
            case let .introStep(n):  return "introStep(\(n))"
            case .fallback:          return "fallback"
            }
        }
    }
}
