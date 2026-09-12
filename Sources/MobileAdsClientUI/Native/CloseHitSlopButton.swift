//
//  CloseHitSlopButton.swift
//  MobileAdsClient
//
//  A close button whose touch target can extend past its drawn bounds.
//

#if canImport(UIKit)
import UIKit

/// A `UIButton` that accepts touches up to `hitSlop` points outside its own
/// bounds on every side.
///
/// The close control on a full-screen ad is drawn small so it does not cover
/// the creative, which leaves a tap target below the 44pt Human Interface
/// Guidelines minimum. Growing the button instead would grow the chip it sits
/// in; growing only the touch area keeps the visual size and fixes the target.
public final class CloseHitSlopButton: UIButton {

    /// Upper bound on `hitSlop`. Past this the target starts swallowing taps
    /// meant for the creative underneath, which reads as an accidental click.
    public static let maximumHitSlop: CGFloat = 44

    private var clampedHitSlop: CGFloat = 0

    /// Points of extra touch area on every side, clamped to
    /// `0...maximumHitSlop`. Clamping happens here so no caller has to.
    public var hitSlop: CGFloat {
        get { clampedHitSlop }
        set { clampedHitSlop = min(max(0, newValue), Self.maximumHitSlop) }
    }

    public override func point(
        inside point: CGPoint,
        with event: UIEvent?
    ) -> Bool {
        bounds.insetBy(dx: -clampedHitSlop, dy: -clampedHitSlop).contains(point)
    }
}
#endif
