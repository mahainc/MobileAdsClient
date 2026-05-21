//
//  RowAdsListView.swift
//  NativeAdsPlayground
//
//  Renders the `RowAdsList` reducer's ads via `RowNativeView`. The two row
//  layouts (`.inline` and `.stacked`) alternate so you can compare them on
//  the same screen.
//

import ComposableArchitecture
import MobileAdsClientUI
import NativeAdClient
import SwiftUI

struct RowAdsListView: View {
    @Perception.Bindable var store: StoreOf<RowAdsList>

    var body: some View {
        WithPerceptionTracking {
            NavigationStack {
                List {
                    ForEach(store.scope(state: \.ads, action: \.ads)) { adStore in
                        Section(layoutTitle(for: adStore.configuration)) {
                            RowNativeView(store: adStore)
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
                .navigationTitle("Row Layouts")
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
        guard let row = configuration.base as? NativeAdClient.Configuration.Row else {
            return ""
        }
        switch row.layout.mode {
        case .inline:         return "Inline (CTA on the right)"
        case .stacked:        return "Stacked (CTA below)"
        case .stackedFullCTA: return "Stacked (full-width CTA)"
        }
    }
}

#Preview {
    RowAdsListView(
        store: Store(initialState: RowAdsList.State()) {
            RowAdsList()
        }
    )
}
