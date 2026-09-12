//
//  BannerAdView.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 6/2/25.
//

#if canImport(UIKit)
import ComposableArchitecture
import GoogleMobileAds
import SwiftUI

public struct BannerAdView: UIViewRepresentable {
    @Bindable private var store: StoreOf<Banner>

    public init(store: StoreOf<Banner>) {
        self.store = store
    }

    public func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.layer.cornerRadius = store.layer.cornerRadius
        view.layer.borderWidth = store.layer.borderWidth
        view.layer.borderColor = store.layer.borderColor.cgColor
        view.layer.backgroundColor = store.layer.backgroundColor.cgColor
        view.layer.masksToBounds = store.layer.cornerRadius != 0 ? true : false

        let bannerView = context.coordinator.bannerView
        bannerView.layer.cornerRadius = store.layer.cornerRadius
        bannerView.layer.borderWidth = store.layer.borderWidth
        bannerView.layer.borderColor = store.layer.borderColor.cgColor
        bannerView.layer.backgroundColor = store.layer.backgroundColor.cgColor
        bannerView.layer.masksToBounds = store.layer.cornerRadius != 0 ? true : false

        let blurEffect = UIBlurEffect(style: .prominent)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)
        blurEffectView.frame.size = bannerView.bounds.size

        view.addSubview(blurEffectView)
        view.insertSubview(context.coordinator.bannerView, aboveSubview: blurEffectView)

        return view
    }

    public func updateUIView(
        _ uiView: UIView,
        context: Context
    ) {
        uiView.frame.size = context.coordinator.bannerView.bounds.size
    }

    public func makeCoordinator() -> BannerCoordinator {
        return BannerCoordinator(parent: self)
    }

    public class BannerCoordinator: NSObject, BannerViewDelegate {

        @MainActor
        private(set) lazy var bannerView: BannerView = {
            let banner = BannerView(adSize: parent.store.adSize)
            banner.adUnitID = parent.store.adUnitID
            let request = Request()

            if case let .anchoredAdaptive(anchored, config?) = parent.store.type, config.isCollapsible {
                let extras = Extras()
                extras.additionalParameters = ["collapsible": "\(config.anchorPosition.rawValue)"]
                request.register(extras)
            }

            banner.load(request)
            banner.delegate = self

            return banner
        }()

        private let parent: BannerAdView

        public init(parent: BannerAdView) {
            self.parent = parent
        }

        public func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            Task {
                self.parent.store.send(.receivedActualSize(bannerView.bounds.size), animation: .default)
                self.parent.store.send(.isCollapsed(bannerView.isCollapsible))
            }
        }

        public func bannerView(
            _ bannerView: BannerView,
            didFailToReceiveAdWithError error: Error
        ) {
            Task {
                self.parent.store.send(.receivedActualSize(.zero), animation: .default)
                self.parent.store.send(.isCollapsed(bannerView.isCollapsible))
            }
        }
    }
}
#endif
