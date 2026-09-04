//
//  PortraitAdsListView.swift
//  NativeAdsPlayground
//
//  Renders the `PortraitAdsList` reducer's ads via `PortraitNativeView` in a
//  two-column `LazyVGrid` — the intended embedding context for the portrait
//  9:16 poster card (each cell self-sizes its height from the column width).
//

import ComposableArchitecture
import MobileAdsClientUI
import NativeAdClient
import SwiftUI

struct PortraitAdsListView: View {
    @Perception.Bindable var store: StoreOf<PortraitAdsList>

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        WithPerceptionTracking {
            NavigationStack {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .center, spacing: 12) {
                        ForEach(store.scope(state: \.ads, action: \.ads)) { adStore in
                            PortraitNativeView(store: adStore)
                                .onAppear {
                                    Task { adStore.send(.onAppear) }
                                }
                        }
                    }
                    .padding(12)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .task { store.send(.onTask) }
                .navigationTitle("Portrait Grid")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            store.send(.refreshAllTapped)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    PortraitAdsListView(
        store: Store(initialState: PortraitAdsList.State()) {
            PortraitAdsList()
        }
    )
}
