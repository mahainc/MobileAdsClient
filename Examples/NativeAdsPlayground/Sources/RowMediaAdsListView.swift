//
//  RowMediaAdsListView.swift
//  NativeAdsPlayground
//
//  Renders the `RowMediaAdsList` reducer's ads via `RowMediaNativeView`. Each
//  card pairs a 16:9 media block with the icon | headline / body | CTA row.
//

import ComposableArchitecture
import MobileAdsClientUI
import NativeAdClient
import SwiftUI

struct RowMediaAdsListView: View {
    @Perception.Bindable var store: StoreOf<RowMediaAdsList>

    var body: some View {
        WithPerceptionTracking {
            NavigationStack {
                List {
                    ForEach(store.scope(state: \.ads, action: \.ads)) { adStore in
                        Section(layoutTitle(for: adStore.configuration)) {
                            RowMediaNativeView(store: adStore)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowSeparator(.hidden)
                                .onAppear {
                                    Task { adStore.send(.onAppear) }
                                }
                        }
                    }
                }
                .listStyle(.plain)
                .task { store.send(.onTask) }
                .navigationTitle("Row + Media Layouts")
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

    private func layoutTitle(for configuration: NativeAdClient.AnyConfiguration) -> String {
        guard let row = configuration.base as? NativeAdClient.Configuration.RowMedia else {
            return ""
        }
        switch row.layout.mode {
        case .inline:         return "Media + Inline (CTA on the right)"
        case .stacked:        return "Media + Stacked (CTA below)"
        case .stackedFullCTA: return "Media + Stacked (full-width CTA)"
        }
    }
}

#Preview {
    RowMediaAdsListView(
        store: Store(initialState: RowMediaAdsList.State()) {
            RowMediaAdsList()
        }
    )
}
