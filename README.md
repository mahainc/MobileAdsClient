# MobileAdsClient

A TCA dependency client wrapping Google Mobile Ads for iOS. The package separates ad interfaces, live SDK orchestration, native loading, and reusable UI renderers.

## Products

- **`MobileAdsClient`** — dependency interface for app-open, interstitial, rewarded, and native full-screen ads.
- **`MobileAdsClientLive`** — live Google Mobile Ads orchestration and `FunnelClient.Ad.Providing` conformance.
- **`MobileAdsClientUI`** — SwiftUI/UIKit banner and native-ad renderers.
- **`NativeAdClient`** — native-ad loading contract and configuration models.
- **`NativeAdClientLive`** — live native-ad loading, batching, readiness, and revenue attribution.

## Installation

In your `Package.swift`:

```swift
.package(url: "https://github.com/mahainc/MobileAdsClient.git", from: "1.4.0")
```

Add interface products to feature targets, live products to the app target, and `MobileAdsClientUI` to targets that render banner or native-ad views.

## Configure Google Mobile Ads

```swift
import GoogleMobileAds

@main
struct MyApp: App {
    init() {
        MobileAds.shared.start(completionHandler: nil)
    }

    var body: some Scene {
        /* ... */
    }
}
```

Declare `GADApplicationIdentifier` and the required SKAdNetwork identifiers in `Info.plist`.

## Full-screen ads

```swift
import ComposableArchitecture
import MobileAdsClient

@Reducer
struct PaywallFeature {
    @ObservableState
    struct State: Equatable, Sendable {}

    enum Action: Equatable, Sendable {
        case showInterstitial
    }

    @Dependency(\.mobileAdsClient) var ads

    var body: some ReducerOf<Self> {
        Reduce { _, action in
            switch action {
                case .showInterstitial:
                    return .run { _ in
                        _ = try await ads.showFullScreenAd(.interstitial("unit-id"))
                    }
            }
        }
    }
}
```

`MobileAdsClient.AdType` supports `appOpen`, `interstitial`, `rewarded`, and `nativeFullScreen`. `showFullScreenAd` throws `AdError.adNotReady` when an ad cannot be presented. Rewarded outcomes distinguish `rewardEarned` from `rewardNotEarned`.

## Native UI

`MobileAdsClientUI` provides SwiftUI containers and UIKit renderers for custom, row, row-media, portrait, and full-screen native layouts:

```swift
import MobileAdsClientUI

NativeView(store: store.scope(state: \.nativeAd, action: \.nativeAd))
```

Use `NativeAdClient` for loader options/configuration and `NativeAdClientLive` for SDK-backed loading.

## FunnelClient integration

`MobileAdsClientLive` conforms to `FunnelClient.Ad.Providing`. The adapter maps:

| Funnel action/type | MobileAdsClient format |
| --- | --- |
| `showInterstitial` / `interstitial` | `interstitial` |
| `showRewarded` / `rewarded` | `rewarded` |
| `showNative` / `native` | `nativeFullScreen` |
| `showResume` / `resume` | `appOpen` |
| `showBanner` / `banner` | fail-open; banner is rendered through `MobileAdsClientUI` |

Funnel's protocol extension owns the process-wide presentation guard. Rewarded failures fail closed; non-rewarded failures fail open. Native invocations forward `featureID` for revenue attribution and apply `NativeStyle.closeDelayMs` to the full-screen close countdown. `slotRef`, `adFormat`, and `grantCredits` remain Funnel-side metadata because the underlying Google presentation API has no corresponding parameters.

## Testing

The package exposes TCA dependency test and preview values. Override `mobileAdsClient` endpoints in feature tests with the current `showFullScreenAd` and `warmFullScreenAd` APIs.

## Dependencies

- `swift-composable-architecture` from 1.25.5
- `swift-package-manager-google-mobile-ads` from 13.4.0
- `TCAInitializableReducer` from 0.1.0
- `AdRevenueClient` from 2.0.1
- `FunnelClient` 6.0.0

## Platform support

- iOS 17+

## License

MIT — see [LICENSE](./LICENSE).
