//
//  Models.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 9/6/25.
//

import Foundation

extension MobileAdsClient {
    public struct AdRule: Sendable, Identifiable, Equatable, CustomStringConvertible {
        public let id: String
        public let name: String
        public let priority: Int
        public let evaluate: @Sendable () async -> Bool

        public init(
            name: String,
            priority: Int = 0,
            evaluate: @escaping @Sendable () async -> Bool
        ) {
            self.id = UUID().uuidString
            self.name = name
            self.priority = priority
            self.evaluate = evaluate
        }

        public static func == (
            lhs: AdRule,
            rhs: AdRule
        ) -> Bool {
            lhs.id == rhs.id
        }

        public var description: String {
            """
            AdRule {
            	id: \(id)
            	name: "\(name)"
            	priority: \(priority)
            }
            """
        }

        public func detailedDescription() async -> String {
            let result = await evaluate()
            return """
                AdRule {
                	id: \(id)
                	name: "\(name)"
                	priority: \(priority)
                	evaluate result: \(result ? "✅ Passed" : "❌ Failed")
                }
                """
        }
    }

    public enum AdType: Sendable, Equatable, CustomStringConvertible {
        case appOpen(AdUnitID)
        case interstitial(AdUnitID)
        case rewarded(AdUnitID)
        case nativeFullScreen(AdUnitID)

        public typealias AdUnitID = String

        public var description: String {
            switch self {
                case .appOpen: return "APP OPEN"
                case .interstitial: return "INTERSTITIAL"
                case .rewarded: return "REWARDED"
                case .nativeFullScreen: return "NATIVE FULLSCREEN"
            }
        }
    }

    /// Emitted by `loadStates()` while a **show-time** ad load is in flight, so a
    /// host can drive a spinner. Only fires when `showFullScreenAd` must load
    /// before it can present (pool empty → fresh network fetch, or native's
    /// on-demand load). Background `warmFullScreenAd` and Google preload refills
    /// stay silent.
    public enum AdLoadState: Sendable, Equatable {
        case loading(AdType)
        case ready(AdType)
        case failed(AdType)
    }

    /// Snapshot of currently-available preloaded ads at the moment `preloadStatus()`
    /// is called, from both acquisition sources. Only units with ≥1 available ad
    /// appear in each map. Buffers refill asynchronously, so treat this as a reading.
    public struct PreloadStatus: Sendable, Equatable {
        /// Google Preloader buckets: ad unit id → available count. Count-only — the
        /// SDK exposes `numberOfAdsAvailable(with:)` but no way to enumerate the ads,
        /// and the bucket is keyword-less.
        public let googleByUnit: [String: Int]

        /// AdPool cache: ad unit id → the variants currently held for it. Each
        /// variant is one cached ad's keywords + load time.
        public let poolByUnit: [String: [Variant]]

        /// One cached pool ad's metadata (not the ad object — that stays internal and
        /// consumable). `keywords` are the original request keywords; `loadedAt` is
        /// when it was fetched.
        public struct Variant: Sendable, Equatable {
            public let keywords: [String]
            public let loadedAt: Date

            public init(
                keywords: [String],
                loadedAt: Date
            ) {
                self.keywords = keywords
                self.loadedAt = loadedAt
            }
        }

        public init(
            googleByUnit: [String: Int] = [:],
            poolByUnit: [String: [Variant]] = [:]
        ) {
            self.googleByUnit = googleByUnit
            self.poolByUnit = poolByUnit
        }
    }

    public enum AdError: Error, Sendable, Equatable, CustomStringConvertible {
        case adNotReady

        public var description: String {
            switch self {
                case .adNotReady: return "The ad is not ready to be shown."
            }
        }
    }
}

extension Array where Element == MobileAdsClient.AdRule {
    public func allRulesSatisfied() async -> Bool {
        // Sort by priority (higher priority first) for better performance
        // Higher priority rules are more likely to fail fast
        let sortedRules = self.sorted { $0.priority > $1.priority }

        return await withTaskGroup(of: (index: Int, result: Bool).self) { group in
            var nextIndex = 0
            let batchSize = Swift.min(3, sortedRules.count)  // Process rules in small batches

            // Add initial batch
            for i in 0..<batchSize {
                group.addTask {
                    (index: i, result: await sortedRules[i].evaluate())
                }
            }
            nextIndex = batchSize

            for await (_, result) in group {
                if !result {
                    // Rule failed - cancel all and return false
                    group.cancelAll()
                    return false
                }

                // Rule passed - add next rule if available
                if nextIndex < sortedRules.count {
                    let currentIndex = nextIndex
                    group.addTask {
                        (index: currentIndex, result: await sortedRules[currentIndex].evaluate())
                    }
                    nextIndex += 1
                }
            }

            return true
        }
    }
}
