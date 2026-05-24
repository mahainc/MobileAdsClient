//
//  MobileAdsBootstrap.swift
//  MobileAdsClient
//
//  Single, idempotent entry point for `MobileAds.shared.start(...)`. Apps call
//  `await MobileAdsBootstrap.start()` from their `@main` init; subsequent
//  callers (live managers, tests) can `await` the same task and join the
//  in-flight initialization instead of triggering a redundant SDK start.
//

#if canImport(UIKit)
@preconcurrency import GoogleMobileAds

public actor MobileAdsBootstrap {

    private static let shared = MobileAdsBootstrap()

    private var startTask: Task<Void, Never>?

    /// Kicks off `MobileAds.shared.start(...)` exactly once for the process and
    /// returns when the SDK has finished initializing. Safe to call from any
    /// thread or actor; concurrent callers join the same underlying task.
    public static func start() async {
        await shared.start()
    }

    private func start() async {
        if let startTask {
            await startTask.value
            return
        }
        let task = Task { @MainActor in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                MobileAds.shared.start { _ in
                    continuation.resume()
                }
            }
        }
        startTask = task
        await task.value
    }
}
#endif
