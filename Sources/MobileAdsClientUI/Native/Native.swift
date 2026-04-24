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
        
		public init(adUnitID: String, options: [NativeAdClient.AnyAdLoaderOption] = []) {
            self.adUnitID = adUnitID
            self.adLoaderOptions = options
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
                return .run(priority: .background) { [adUnitID = state.adUnitID, adLoaderOptions = state.adLoaderOptions] send in
                    var rootViewController: UIViewController? = nil
                    if let scene = await UIApplication.shared.connectedScenes.first as? UIWindowScene, let rootVC = await scene.windows.first?.rootViewController {
                        rootViewController = rootVC
                    }
                    let nativeAd = try await nativeAdClient.loadAd(adUnitID, rootViewController, adLoaderOptions)
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
                return .run(priority: .background) { [adLoaderOptions = state.adLoaderOptions] send in
                    var rootViewController: UIViewController? = nil
                    if let scene = await UIApplication.shared.connectedScenes.first as? UIWindowScene, let rootVC = await scene.windows.first?.rootViewController {
                        rootViewController = rootVC
                    }
                    let nativeAd = try await nativeAdClient.loadAd(adUnitID, rootViewController, adLoaderOptions)
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
}
#endif
