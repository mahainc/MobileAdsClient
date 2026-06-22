//
//  GoogleAdsView.swift
//  NativeAdsPlayground
//

import ComposableArchitecture
import MobileAdsClientUI
import GoogleMobileAds
import Foundation
import SwiftUI

struct GoogleAdsView: View {

    @Perception.Bindable var store: StoreOf<GoogleAds>

    var body: some View {
        WithPerceptionTracking {
            NavigationStack {
                GeometryReader { proxy in
                    List {
                        ForEach(store.scope(state: \.banners, action: \.banners)) { store in
                            BannerAdView(store: store)
                                .frame(width: store.actualSize.width, height: store.actualSize.height)
                        }
                        .onDelete { indexSet in

                        }

                        ForEach(store.scope(state: \.items, action: \.items)) { itemStore in
                            switch(itemStore.state) {
                            case .content:
                                if let store = itemStore.scope(state: \.content, action: \.content) {
                                    ArticleView(store: store)
                                }

                            case .ad:
                                if let store = itemStore.scope(state: \.ad, action: \.ad) {
                                    BannerAdView(store: store)
                                        .frame(width: store.actualSize.width, height: store.actualSize.height)
                                }
                            }
                        }


                        if let store = store.scope(state: \.native, action: \.native) {
                            NativeView(store: store)
                                .frame(width: proxy.size.width - 40)
                                .padding(.horizontal, 20)
                                .onAppear {
                                    Task {
                                        store.send(.onAppear)
                                    }
                                }
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        if let store = store.scope(state: \.anchoredBanner, action: \.anchoredBanner) {
                            BannerAdView(store: store)
                                .frame(width: store.actualSize.width, height: store.actualSize.height)
                        }
                    }
                    .task {
                        store.send(.onTask)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            if let store = store.scope(state: \.native, action: \.native) {
                                store.send(.refreshAd("ca-app-pub-3940256099942544/3986624511"))
                            }
                        } label: {
                            Text("Refresh Ad")
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    let store = Store(initialState: GoogleAds.State()) {
        GoogleAds()
    }

    GoogleAdsView(store: store)
}
