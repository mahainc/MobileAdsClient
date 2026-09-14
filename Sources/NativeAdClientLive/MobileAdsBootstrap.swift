//
//  MobileAdsBootstrap.swift
//  MobileAdsClient
//
//  Single, idempotent entry point for `MobileAds.shared.start(...)`. Apps call
//  `await MobileAdsBootstrap.start()` from their `@main` init; subsequent
//  callers (live managers, tests) can `await` the same task and join the
//  in-flight initialization instead of triggering a redundant SDK start.
//
//  Some apps must keep the SDK start behind a consent gate (UMP/ATT) that they
//  own, so they call `MobileAds.shared.start` themselves and then signal
//  readiness here via `markStarted()`. Native-ad loads block on `awaitReady()`
//  so a load fired before the SDK is up suspends instead of racing ahead and
//  failing.
//

#if canImport(UIKit)
@preconcurrency import GoogleMobileAds

public actor MobileAdsBootstrap {

    private static let shared = MobileAdsBootstrap()

    private var startTask: Task<Void, Never>?
    private var isReady = false
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []
    private var timedReadyWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    /// Kicks off `MobileAds.shared.start(...)` exactly once for the process and
    /// returns when the SDK has finished initializing. Safe to call from any
    /// thread or actor; concurrent callers join the same underlying task.
    public static func start() async {
        await shared.start()
    }

    /// Marks the SDK as ready without triggering `MobileAds.shared.start` here —
    /// for apps that own the start call behind a consent gate. Idempotent;
    /// unblocks every current and future `awaitReady()` caller.
    public static func markStarted() async {
        await shared.markStarted()
    }

    /// Suspends until the SDK has been started (via `start()` or `markStarted()`).
    /// Does NOT trigger the SDK start itself — start stays owned by the app's
    /// consent gate. Returns immediately once readiness has been signalled.
    public static func awaitReady() async {
        await shared.awaitReady()
    }

    /// Like `awaitReady()`, but gives up after `timeout` so a caller that must
    /// finish — an ad presentation holding a user-facing flow — cannot hang on a
    /// host that never starts the SDK. Returns whether the SDK is ready.
    public static func awaitReady(timeout: Duration) async -> Bool {
        await shared.awaitReady(timeout: timeout)
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
        resolveReady()
    }

    private func markStarted() {
        resolveReady()
    }

    private func awaitReady() async {
        if isReady { return }
        await withCheckedContinuation { continuation in
            readyWaiters.append(continuation)
        }
    }

    private func awaitReady(timeout: Duration) async -> Bool {
        if isReady { return true }
        let waiterID = UUID()
        return await withCheckedContinuation { continuation in
            timedReadyWaiters[waiterID] = continuation
            Task {
                try? await Task.sleep(for: timeout)
                self.expireTimedWaiter(waiterID)
            }
        }
    }

    private func expireTimedWaiter(_ waiterID: UUID) {
        timedReadyWaiters.removeValue(forKey: waiterID)?.resume(returning: false)
    }

    private func resolveReady() {
        guard !isReady else { return }
        isReady = true
        let waiters = readyWaiters
        readyWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        let timedWaiters = timedReadyWaiters.values
        timedReadyWaiters.removeAll()
        for waiter in timedWaiters {
            waiter.resume(returning: true)
        }
    }
}
#endif
