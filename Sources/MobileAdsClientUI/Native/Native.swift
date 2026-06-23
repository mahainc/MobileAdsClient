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
            public let id: String = UUID().uuidString
            public let adUnitID: String
            public let adLoaderOptions: [NativeAdClient.AnyAdLoaderOption]
            public var nativeAd: NativeAd?
            /// Measured card height, applied by the wrappers via
            /// `.frame(height: store.adHeight)`. Driving height from state (rather
            /// than the representable's `sizeThatFits`) is what lets a content
            /// refresh EASE the height — `.frame` animates inside the
            /// `.updateAdHeight(_, animation:)` transaction, whereas a
            /// `sizeThatFits` height is applied in a non-animated layout pass and
            /// snaps. Starts at 0 so an unmeasured slot reserves no band; the real
            /// height is set on first bind (instantly) and eased on refresh.
            public var adHeight: CGFloat = 0
            public var configuration: NativeAdClient.AnyConfiguration = .init(
                NativeAdClient.Configuration.Compact.default
            )

            public init(
                adUnitID: String,
                options: [NativeAdClient.AnyAdLoaderOption] = [],
                configuration: NativeAdClient.AnyConfiguration = .init(NativeAdClient.Configuration.Compact.default)
            ) {
                self.adUnitID = adUnitID
                self.adLoaderOptions = options
                self.configuration = configuration
            }

            /// Pool-friendly initializer. Constructs state already bound to a
            /// pre-loaded `NativeAd` (e.g. popped from `NativeAdInventory`), so
            /// the reducer's `.onAppear` short-circuits and the view renders the
            /// creative immediately. `adUnitID` and `adLoaderOptions` are left
            /// empty because no further load will be issued for this slot.
            public init(
                preloaded ad: NativeAd,
                configuration: NativeAdClient.AnyConfiguration = .init(NativeAdClient.Configuration.Compact.default)
            ) {
                self.adUnitID = ""
                self.adLoaderOptions = []
                self.nativeAd = ad
                self.configuration = configuration
            }
        }

        public enum Action: Equatable, BindableAction, @unchecked Sendable {
            case onAppear
            case binding(BindingAction<State>)
            case receivedNativeAd(NativeAd)
            case updateAdHeight(CGFloat)
            case refreshAd(String)
            case delegate(Delegate)

            @CasePathable
            public enum Delegate: Equatable, Sendable {
                /// The initial `.onAppear` load attempt failed. Parents typically
                /// react by removing this slot from their interleaved list state
                /// so the layout collapses instead of holding a reserved-empty row.
                case loadFailed
            }
        }

        @Dependency(\.nativeAdClient) var nativeAdClient

        public var body: some ReducerOf<Self> {
            BindingReducer()

            Reduce { state, action in
                switch action {
                    case .onAppear:
                        // LazyVStack re-fires .onAppear every time a row scrolls back
                        // into view. Skip the load when a creative is already bound —
                        // re-loading would waste a `GADAdLoader.load()` call (which
                        // counts toward AdMob's per-unitID concurrency throttle and
                        // can starve sibling rows that haven't filled yet).
                        guard state.nativeAd == nil else { return .none }
                        #if DEBUG
                            print("➡️ NATIVE onAppear reduced unit=\(state.adUnitID) stateId=\(state.id)")
                        #endif
                        return .run(priority: .background) {
                            [
                                adUnitID = state.adUnitID,
                                configuration = state.configuration,
                                adLoaderOptions = state.adLoaderOptions,
                                stateId = state.id
                            ] send in
                            var rootViewController: UIViewController?
                            if let scene = await UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                let rootVC = await scene.windows.first?.rootViewController
                            {
                                rootViewController = rootVC
                            }
                            let options = Native.sanitizedOptions(for: configuration, options: adLoaderOptions)
                            let nativeAd = try await nativeAdClient.loadAd(adUnitID, rootViewController, options)
                            #if DEBUG
                                print("✅ NATIVE awaited ad unit=\(adUnitID) stateId=\(stateId)")
                            #endif
                            // First bind happens during scroll/feed render. Animating
                            // .frame(height:) here forces extra layout passes on
                            // neighbouring LazyVStack cells. `refreshAd` keeps its
                            // animation because that's a deliberate user action.
                            await send(.receivedNativeAd(nativeAd))
                        } catch: { error, send in
                            #if DEBUG
                                print("❌ NATIVE Error LOADING: \(error.localizedDescription)")
                            #endif
                            await send(.delegate(.loadFailed))
                        }

                    case let .receivedNativeAd(nativeAd):
                        #if DEBUG
                            print("🎯 NATIVE receivedNativeAd reduced unit=\(state.adUnitID) stateId=\(state.id)")
                        #endif
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
                            var rootViewController: UIViewController?
                            if let scene = await UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                let rootVC = await scene.windows.first?.rootViewController
                            {
                                rootViewController = rootVC
                            }
                            let options = Native.sanitizedOptions(for: configuration, options: adLoaderOptions)
                            let nativeAd = try await nativeAdClient.loadAd(adUnitID, rootViewController, options)
                            await send(.receivedNativeAd(nativeAd), animation: .default)
                        } catch: { error, _ in
                            #if DEBUG
                                print("Error REFRESH native ad: \(error.localizedDescription)")
                            #endif
                        }

                    default:
                        return .none
                }
            }
        }

        public init() {}

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
