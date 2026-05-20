//
//  NativeAdsPlaygroundApp.swift
//  NativeAdsPlayground
//
//  Demo app for the 5 native ad templates in MobileAdsClientUI.
//

import ComposableArchitecture
import GoogleMobileAds
import NativeAdClient
import NativeAdClientLive
import SwiftUI

@main
struct NativeAdsPlaygroundApp: App {
    init() {
        // Start the Google Mobile Ads SDK once at launch — required before
        // any ad load. Test ad units don't require an AdMob account.
        MobileAds.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                GoogleAdsView(
                    store: Store(initialState: GoogleAds.State()) {
                        GoogleAds()
                    }
                )
                .tabItem {
                    Label("Mixed", systemImage: "rectangle.stack")
                }

                NativeAdsListView(
                    store: Store(initialState: NativeAdsList.State()) {
                        NativeAdsList()
                    }
                )
                .tabItem {
                    Label("Natives", systemImage: "square.text.square")
                }
            }
        }
    }
}
