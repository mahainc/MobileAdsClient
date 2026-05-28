# MobileAdsClient

A multi-family TCA dependency client wrapping Google Mobile Ads SDK for iOS. One Swift package shipping two sibling client families plus a SwiftUI presentation sublayer:

**Ads family**
- **`MobileAdsClient`** — interface for app-open / interstitial / rewarded / banner formats, presentation lifecycle hooks, revenue events.
- **`MobileAdsClientLive`** — `GoogleMobileAds` wrapper, registers the live `DependencyKey`.
- **`MobileAdsClientUI`** — SwiftUI views for native ad layouts plus bundled resource assets (`.process("Resources")`).

**Native ads family**
- **`NativeAdClient`** — interface for `GADNativeAd` lifecycle: load / present / dismiss.
- **`NativeAdClientLive`** — `GoogleMobileAds` wrapper, registers the live `DependencyKey`.

## Installation

In your `Package.swift`:

```swift
.package(url: "https://github.com/mahainc/MobileAdsClient.git", from: "1.0.3"),
```

Add the products you need to your targets — interfaces (`MobileAdsClient`, `NativeAdClient`) on feature targets, Live products on app targets, `MobileAdsClientUI` on any feature that renders native ad views.

## Configure Google Mobile Ads

In your app's entry point:

```swift
import GoogleMobileAds

@main
struct MyApp: App {
    init() {
        MobileAds.shared.start(completionHandler: nil)
    }
    var body: some Scene { /* … */ }
}
```

Make sure your `Info.plist` declares `GADApplicationIdentifier` and any SKAdNetwork identifiers Google's docs require for your placements.

## Usage

```swift
import MobileAdsClient
import ComposableArchitecture

@Reducer
struct PaywallFeature {
    @ObservableState
    struct State { /* … */ }

    enum Action {
        case onAppear
        case showInterstitial
        case revenueRecorded(MobileAdsClient.AdRevenue)
    }

    @Dependency(\.mobileAdsClient) var ads

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { _ in await ads.preloadInterstitial() }

            case .showInterstitial:
                return .run { send in
                    if let revenue = try await ads.presentInterstitial() {
                        await send(.revenueRecorded(revenue))
                    }
                }

            case .revenueRecorded:
                return .none
            }
        }
    }
}
```

## Native ads

`MobileAdsClientUI` ships SwiftUI containers that pair `NativeAdClient` data with Google's required impression / click tracking views:

```swift
import MobileAdsClientUI

NativeAdView(store: store.scope(state: \.nativeAd, action: \.nativeAd))
```

## Testing

The interface modules expose unimplemented `testValue` defaults via `@DependencyClient`:

```swift
let store = TestStore(initialState: PaywallFeature.State()) {
    PaywallFeature()
} withDependencies: {
    $0.mobileAdsClient.preloadInterstitial = { /* no-op */ }
    $0.mobileAdsClient.presentInterstitial = { .init(value: 0.01, currency: "USD") }
}
```

## Dependencies

- `swift-composable-architecture` from 1.25.5
- `swift-package-manager-google-mobile-ads` (GoogleMobileAds) from 13.4.0
- `TCAInitializableReducer` from 0.1.0
- `AdRevenueClient` from 2.0.0

## Platform support

- iOS 16+
- macOS 13+ (compiles, but Google Mobile Ads is iOS-only — Live calls are no-ops)

## License

MIT — see [LICENSE](./LICENSE).
