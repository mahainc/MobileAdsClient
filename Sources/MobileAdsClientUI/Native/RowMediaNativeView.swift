//
//  RowMediaNativeView.swift
//  MobileAdsClient
//
//  SwiftUI wrapper around `RowMediaNativeAdView`. Extracts a
//  `Configuration.RowMedia` from the store's type-erased `AnyConfiguration`
//  and uses `.id` to recreate the UIKit view when any layout-affecting field
//  flips (constraints are built once in `setupViews()` and are not
//  re-flowable at runtime).
//

#if canImport(UIKit)
import ComposableArchitecture
import NativeAdClient
import SwiftUI

public struct RowMediaNativeView: View {

    private let store: StoreOf<Native>

    public init(store: StoreOf<Native>) {
        self.store = store
    }

    private var rowMediaConfig: NativeAdClient.Configuration.RowMedia {
        if let c = store.configuration.base as? NativeAdClient.Configuration.RowMedia {
            return c
        }
        assertionFailure("RowMediaNativeView requires Configuration.RowMedia, got \(type(of: store.configuration.base))")
        return .default
    }

    public var body: some View {
        _RowMediaNativeRepresentable(store: store, configuration: rowMediaConfig)
            .id(rowMediaConfig)
            // Bind the row's height to the measured `store.adHeight`. Without
            // this, SwiftUI containers (`List`, `LazyVStack`, …) fall back to
            // the representable's intrinsic size — which is small/zero for a
            // free-floating UIStackView and clips the content.
            .frame(height: store.adHeight)
    }
}

private struct _RowMediaNativeRepresentable: UIViewRepresentable {
    let store: StoreOf<Native>
    let configuration: NativeAdClient.Configuration.RowMedia

    func makeUIView(context: Context) -> RowMediaNativeAdView {
        RowMediaNativeAdView(configuration: configuration)
    }

    func updateUIView(_ uiView: RowMediaNativeAdView, context: Context) {
        #if DEBUG
        print("🖼️ ROWMEDIA updateUIView storeId=\(store.id) hasAd=\(store.nativeAd != nil) adHeight=\(store.adHeight)")
        #endif
        if uiView.style != configuration.style {
            uiView.style = configuration.style
        }
        guard let nativeAd = store.nativeAd else { return }
        #if DEBUG
        print("🖼️ ROWMEDIA bind-attempt storeId=\(store.id) sameAsCurrent=\(uiView.nativeAd === nativeAd)")
        #endif
        // Skip re-bind when the same creative is already attached. SwiftUI
        // re-invokes updateUIView on every store change (including the
        // adHeight update we send from this very block), and an unguarded
        // `configure` re-triggers layout/measure in a feedback loop.
        guard uiView.nativeAd !== nativeAd else { return }
        uiView.configure(with: nativeAd)

        DispatchQueue.main.async {
            uiView.layoutIfNeeded()
            let width = uiView.bounds.width
            guard width > 0 else { return }
            let height = uiView.calculateTotalHeight(fittingWidth: width)
            #if DEBUG
            let willUpdate = abs(height - store.adHeight) > 0.5
            print("📐 ROWMEDIA measured storeId=\(store.id) width=\(width) height=\(height) prev=\(store.adHeight) update=\(willUpdate)")
            #endif
            // Epsilon guards against an infinite update loop caused by tiny float
            // drift between the measured value and the value already in state.
            if abs(height - store.adHeight) > 0.5 {
                store.send(.updateAdHeight(height))
            }
        }
    }
}
#endif
