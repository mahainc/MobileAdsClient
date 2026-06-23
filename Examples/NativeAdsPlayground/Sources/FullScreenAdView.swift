//
//  FullScreenAdView.swift
//  NativeAdsPlayground
//
//  Drives the `FullScreenAd` reducer: a button loads a test native ad, then
//  presents the real `FullScreenNativeView` over a full-screen cover.
//

import ComposableArchitecture
import MobileAdsClientUI
import NativeAdClient
import SwiftUI

struct FullScreenAdView: View {
    @Perception.Bindable var store: StoreOf<FullScreenAd>
    @State private var mediaIgnoresSafeArea = true
    @State private var mediaFills = true
    @State private var gateClose = true

    var body: some View {
        WithPerceptionTracking {
            NavigationStack {
                VStack(spacing: 16) {
                    Spacer()

                    Image(systemName: "rectangle.inset.filled")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)

                    Text("Full-Screen Native Ad")
                        .font(.title2.weight(.semibold))

                    Text(
                        "Loads a video-capable test native ad and presents it full screen. "
                            + "Tap the CTA, headline, or body during video playback to confirm "
                            + "the tap registers as an ad click."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                    Toggle("Media ignores safe area", isOn: $mediaIgnoresSafeArea)
                        .padding(.horizontal, 32)

                    Toggle("Media fills (off = fit)", isOn: $mediaFills)
                        .padding(.horizontal, 32)

                    Toggle("Gate close (5s countdown)", isOn: $gateClose)
                        .padding(.horizontal, 32)

                    Button {
                        store.send(.showTapped)
                    } label: {
                        if store.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Show Full-Screen Native Ad")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.isLoading)
                    .padding(.horizontal, 32)

                    if let errorText = store.errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    Spacer()
                }
                .navigationTitle("Full Screen")
                .navigationBarTitleDisplayMode(.inline)
                .task { store.send(.autoPresentIfNeeded) }
            }
            .fullScreenCover(isPresented: $store.isPresented.sending(\.setPresented)) {
                if let nativeAd = store.nativeAd {
                    FullScreenNativeView(
                        nativeAd: nativeAd,
                        configuration: .init(
                            mediaIgnoresSafeArea: mediaIgnoresSafeArea,
                            mediaContentMode: mediaFills ? .fill : .fit,
                            closeCountdown: gateClose ? 5 : 0
                        ),
                        onClose: { store.send(.dismissTapped) }
                    )
                    .ignoresSafeArea()
                }
            }
        }
    }
}

#Preview {
    FullScreenAdView(
        store: Store(initialState: FullScreenAd.State()) {
            FullScreenAd()
        }
    )
}
