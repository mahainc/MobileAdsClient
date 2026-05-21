//
//  File.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 6/2/25.
//

#if canImport(UIKit)
@preconcurrency import GoogleMobileAds
import ComposableArchitecture
import TCAInitializableReducer
import NativeAdClient

@Reducer
public struct Native: TCAInitializableReducer, Sendable {
    @ObservableState
    public struct State: Identifiable, Sendable, Equatable {
        public let id : String = UUID().uuidString
        public let adUnitID: String
		public let adLoaderOptions: [NativeAdClient.AnyAdLoaderOption]
        public var nativeAd: NativeAd?
        public var adHeight: CGFloat = 300.0
        public var configuration: NativeAdClient.AnyConfiguration = .init(NativeAdClient.Configuration.Compact.default)

		public init(
            adUnitID: String,
            options: [NativeAdClient.AnyAdLoaderOption] = [],
            configuration: NativeAdClient.AnyConfiguration = .init(NativeAdClient.Configuration.Compact.default)
        ) {
            self.adUnitID = adUnitID
            self.adLoaderOptions = options
            self.configuration = configuration
        }
    }
    
    public enum Action: Equatable, BindableAction, @unchecked Sendable {
        case onAppear
        case binding(BindingAction<State>)
        case receivedNativeAd(NativeAd)
        case updateAdHeight(CGFloat)
        case refreshAd(String)
    }
    
    @Dependency(\.nativeAdClient) var nativeAdClient
    
    public var body: some ReducerOf<Self> {
        BindingReducer()
        
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run(priority: .background) {
                    [
                        adUnitID = state.adUnitID,
                        configuration = state.configuration,
                        adLoaderOptions = state.adLoaderOptions
                    ] send in
                    var rootViewController: UIViewController? = nil
                    if let scene = await UIApplication.shared.connectedScenes.first as? UIWindowScene, let rootVC = await scene.windows.first?.rootViewController {
                        rootViewController = rootVC
                    }
                    let options = Native.sanitizedOptions(for: configuration, options: adLoaderOptions)
                    let nativeAd = try await nativeAdClient.loadAd(adUnitID, rootViewController, options)
                    await send(.receivedNativeAd(nativeAd), animation: .default)
                } catch: { error, send in
					#if DEBUG
                    print("Error LOADING native ad: \(error.localizedDescription)")
					#endif
                }

            case let .receivedNativeAd(nativeAd):
                state.nativeAd = nativeAd
                return .none

            case let .updateAdHeight(height):
                state.adHeight = height
                return .none

            case let .refreshAd(adUnitID):
                return .run(priority: .background) {
                    [
                        configuration = state.configuration,
                        adLoaderOptions = state.adLoaderOptions
                    ] send in
                    var rootViewController: UIViewController? = nil
                    if let scene = await UIApplication.shared.connectedScenes.first as? UIWindowScene, let rootVC = await scene.windows.first?.rootViewController {
                        rootViewController = rootVC
                    }
                    let options = Native.sanitizedOptions(for: configuration, options: adLoaderOptions)
                    let nativeAd = try await nativeAdClient.loadAd(adUnitID, rootViewController, options)
                    await send(.receivedNativeAd(nativeAd), animation: .default)
                } catch: { error, send in
					#if DEBUG
                    print("Error REFRESH native ad: \(error.localizedDescription)")
					#endif
                }
                
                default:
                    return .none
            }
        }
    }

    public init() { }

    /// Strip media-related loader options when the consumer's `configuration`
    /// is a Row (icon-only template). Row has no `mediaView` slot — media
    /// options would steer the SDK toward unrenderable creatives and trip
    /// AdMob's debug validator with "unbound media view" warnings.
    private static func sanitizedOptions(
        for configuration: NativeAdClient.AnyConfiguration,
        options: [NativeAdClient.AnyAdLoaderOption]
    ) -> [NativeAdClient.AnyAdLoaderOption] {
        guard configuration.base is NativeAdClient.Configuration.Row else {
            return options
        }
        return options.filter { option in
            let underlying = option.unwrapped
            return !(underlying is NativeAdClient.MediaAspectRatioOption)
                && !(underlying is NativeAdClient.VideoPlaybackOption)
        }
    }
}
#endif
