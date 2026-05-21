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
            RootTabView()
        }
    }
}

private struct RootTabView: View {
    // Default to the "Rows" tab so the in-feed row template is visible on
    // first launch — useful while iterating on `RowNativeAdView`.
    @State private var selection: Int = 2

    var body: some View {
        TabView(selection: $selection) {
            GoogleAdsView(
                store: Store(initialState: GoogleAds.State()) {
                    GoogleAds()
                }
            )
            .tabItem {
                Label("Mixed", systemImage: "rectangle.stack")
            }
            .tag(0)

            NativeAdsListView(
                store: Store(initialState: NativeAdsList.State()) {
                    NativeAdsList()
                }
            )
            .tabItem {
                Label("Natives", systemImage: "square.text.square")
            }
            .tag(1)

            RowAdsListView(
                store: Store(initialState: RowAdsList.State()) {
                    RowAdsList()
                }
            )
            .tabItem {
                Label("Rows", systemImage: "list.bullet.rectangle")
            }
            .tag(2)
        }
    }
}
