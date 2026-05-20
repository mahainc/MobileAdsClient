//
//  ArticleView.swift
//  NativeAdsPlayground
//

import ComposableArchitecture
import SwiftUI

struct ArticleView: View {
    @Perception.Bindable var store: StoreOf<Article>

    var body: some View {
        Text("Article")
    }
}
