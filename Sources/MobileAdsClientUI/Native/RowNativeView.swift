//
//  RowNativeView.swift
//  MobileAdsClient
//
//  SwiftUI wrapper around `RowNativeAdView`. Extracts a `Configuration.Row`
//  from the store's type-erased `AnyConfiguration` and uses `.id` to recreate
//  the UIKit view when any layout-affecting field flips (constraints are
//  built once in `setupViews()` and are not re-flowable at runtime).
//

#if canImport(UIKit)
import ComposableArchitecture
import NativeAdClient
import SwiftUI

public struct RowNativeView: View {

    private let store: StoreOf<Native>

    public init(store: StoreOf<Native>) {
        self.store = store
    }

    private var rowConfig: NativeAdClient.Configuration.Row {
        if let c = store.configuration.base as? NativeAdClient.Configuration.Row {
            return c
        }
        assertionFailure("RowNativeView requires Configuration.Row, got \(type(of: store.configuration.base))")
        return .default
    }

    public var body: some View {
        _RowNativeRepresentable(store: store, configuration: rowConfig)
            .id(rowConfig)
            // Bind the row's height to the measured `store.adHeight`. Without
            // this, SwiftUI containers (`List`, `LazyVStack`, …) fall back to
            // the representable's intrinsic size — which is small/zero for a
            // free-floating UIStackView and clips the content.
            .frame(height: store.adHeight)
    }
}

private struct _RowNativeRepresentable: UIViewRepresentable {
    let store: StoreOf<Native>
    let configuration: NativeAdClient.Configuration.Row

    func makeUIView(context: Context) -> RowNativeAdView {
        RowNativeAdView(configuration: configuration)
    }

    func updateUIView(_ uiView: RowNativeAdView, context: Context) {
        if uiView.style != configuration.style {
            uiView.style = configuration.style
        }
        guard let nativeAd = store.nativeAd else { return }
        uiView.configure(with: nativeAd)

        DispatchQueue.main.async {
            uiView.layoutIfNeeded()
            let width = uiView.bounds.width
            guard width > 0 else { return }
            let height = uiView.calculateTotalHeight(fittingWidth: width)
            // Epsilon guards against an infinite update loop caused by tiny float
            // drift between the measured value and the value already in state.
            if abs(height - store.adHeight) > 0.5 {
                store.send(.updateAdHeight(height))
            }
        }
    }
}
#endif
