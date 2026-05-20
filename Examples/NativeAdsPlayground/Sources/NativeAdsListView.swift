//
//  NativeAdsListView.swift
//  NativeAdsPlayground
//

import ComposableArchitecture
import MobileAdsClientUI
import SwiftUI

struct NativeAdsListView: View {
    @Perception.Bindable var store: StoreOf<NativeAdsList>

    var body: some View {
        WithPerceptionTracking {
            NavigationStack {
                GeometryReader { proxy in
                    List {
                        ForEach(store.scope(state: \.ads, action: \.ads)) { adStore in
                            NativeView(store: adStore)
                                .frame(width: proxy.size.width - 40, height: adStore.adHeight)
                                .padding(.horizontal, 20)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .onAppear {
                                    Task {
                                        adStore.send(.onAppear)
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .task {
                        store.send(.onTask)
                    }
                }
                .navigationTitle("Natives")
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
    NativeAdsListView(
        store: Store(initialState: NativeAdsList.State()) {
            NativeAdsList()
        }
    )
}
