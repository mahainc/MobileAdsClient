//
//  NativeAdsPlaygroundApp.swift
//  NativeAdsPlayground
//
//  Demo app for the 5 native ad templates in MobileAdsClientUI.
//

import ComposableArchitecture
import NativeAdClient
import NativeAdClientLive
import SwiftUI

@main
struct NativeAdsPlaygroundApp: App {
    init() {
        Task { await MobileAdsBootstrap.start() }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}

private struct RootTabView: View {
    // Default to the "Row+Media" tab so the new row-with-media template is
    // visible on first launch — useful while iterating on `RowMediaNativeAdView`.
    @State private var selection: Int = 3

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

            RowMediaAdsListView(
                store: Store(initialState: RowMediaAdsList.State()) {
                    RowMediaAdsList()
                }
            )
            .tabItem {
                Label("Row+Media", systemImage: "play.rectangle")
            }
            .tag(3)
        }
    }
}
