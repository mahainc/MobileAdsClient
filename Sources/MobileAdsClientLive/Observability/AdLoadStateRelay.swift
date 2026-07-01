//
//  AdLoadStateRelay.swift
//  MobileAdsClient
//
//  Multicast broadcaster for show-time ad load states. `AsyncStream` is
//  single-consumer, so this fans a single emit out to every registered
//  subscriber's continuation. Backs `MobileAdsClient.loadStates()`.
//

#if canImport(UIKit)
    import Foundation
    import MobileAdsClient

    /// Phase of a show-time cold load, threaded down through the acquire chain so
    /// only the fresh-load branch reports progress (cache hits / preloaded serves
    /// stay silent). Mapped to `MobileAdsClient.AdLoadState` at the `AdsManager`
    /// layer, where the concrete `AdType` is known.
    internal enum AdLoadPhase: Sendable {
        case started
        case ready
        case failed
    }

    /// Process-wide fan-out of `MobileAdsClient.AdLoadState`. Each `stream()` call
    /// registers its own continuation; `emit` yields to all live subscribers.
    /// `@unchecked Sendable`: the continuations dictionary is guarded by `lock`.
    internal final class AdLoadStateRelay: @unchecked Sendable {
        internal static let shared = AdLoadStateRelay()

        private let lock = NSLock()
        private var continuations: [UUID: AsyncStream<MobileAdsClient.AdLoadState>.Continuation] = [:]

        private init() {}

        /// A fresh stream for one subscriber. Its continuation is dropped when the
        /// consumer's task terminates (cancellation or completion).
        internal func stream() -> AsyncStream<MobileAdsClient.AdLoadState> {
            let id = UUID()
            return AsyncStream { continuation in
                lock.withLock { continuations[id] = continuation }
                continuation.onTermination = { [weak self] _ in
                    guard let self else { return }
                    self.lock.withLock { _ = self.continuations.removeValue(forKey: id) }
                }
            }
        }

        /// Broadcasts `state` to every live subscriber.
        internal func emit(_ state: MobileAdsClient.AdLoadState) {
            let live = lock.withLock { Array(continuations.values) }
            for continuation in live {
                continuation.yield(state)
            }
        }
    }
#endif
