import ComposableArchitecture

@DependencyClient
public struct MobileAdsClient: Sendable {
    public var shouldShowFullScreenAd:
        @Sendable (_ adType: AdType, _ rules: [AdRule], _ keywords: [String]) async -> Bool = { _, _, _ in false }
    public var showFullScreenAd:
        @Sendable (
            _ adType: AdType, _ keywords: [String], _ requester: AdRequester,
            _ onComplete: CompletionHandler?
        ) async throws -> AdOutcome
    public var warmFullScreenAd: @Sendable (_ adType: AdType, _ keywords: [String]) async -> Void
    public var loadStates: @Sendable () -> AsyncStream<AdLoadState> = { AsyncStream { $0.finish() } }
    public var preloadStatus: @Sendable () async -> PreloadStatus = { PreloadStatus() }
}
