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

    /// Interstitial placements beyond the splash + preloaded-pool units.
    /// Cases correspond 1:1 to fields in `RemoteConfigClient.AdUnitsConfig`.
    public enum AdPlacement: Sendable, Equatable, CaseIterable, CustomStringConvertible {
        case interRecorder

        public var remoteConfigKey: String {
            switch self {
            case .interRecorder: return "interRecorder"
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
}
