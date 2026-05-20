//
//  Article.swift
//  NativeAdsPlayground
//

import ComposableArchitecture
import TCAInitializableReducer
import SwiftUI

@Reducer
public struct Article: TCAInitializableReducer, Sendable {
    @ObservableState
    public struct State: Identifiable, Sendable, Equatable {
        public var id: String = UUID().uuidString
        public init() { }
    }

    public enum Action: BindableAction, Sendable, Equatable {
        case binding(BindingAction<State>)
    }

    public var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            return .none
        }
    }

    public init() { }
}
