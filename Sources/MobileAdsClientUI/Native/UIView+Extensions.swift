//
//  UIView+Extensions.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 17/2/25.
//

#if canImport(UIKit)
import UIKit

extension UIView {

    public func addBlur(
        style: UIBlurEffect.Style = .light,
        cornerRadius: CGFloat = 0
    ) {
        if subviews.contains(where: { $0 is UIVisualEffectView }) {
            return
        }

        let blurEffect = UIBlurEffect(style: style)
        let blurView = UIVisualEffectView(effect: blurEffect)

        blurView.frame = bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        if cornerRadius > 0 {
            blurView.layer.cornerRadius = cornerRadius
            blurView.clipsToBounds = true
        }

        addSubview(blurView)
        sendSubviewToBack(blurView)
    }

}

extension NSLayoutConstraint {

    /// Returns the constraint with its `priority` set, for inline use inside
    /// `NSLayoutConstraint.activate([...])` arrays.
    ///
    /// Set an arranged subview's fixed width/height just below required (999)
    /// so the enclosing `UIStackView` can collapse it to zero — reclaiming its
    /// size and the adjacent spacing — when it is hidden, without an "unable to
    /// simultaneously satisfy constraints" conflict against the stack's own
    /// collapse constraint.
    public func priority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

extension NSDirectionalEdgeInsets {

    /// Bridges a `UIEdgeInsets` (the form the ad config exposes) into the
    /// directional insets `UIButton.Configuration.contentInsets` expects,
    /// mapping `left` → `leading` and `right` → `trailing` — consistent with
    /// how the rest of the layout treats `UIEdgeInsets.left` as leading.
    public init(_ insets: UIEdgeInsets) {
        self.init(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
    }
}

extension UIView {

    /// Applies native-ad content/visibility updates as ONE coordinated pass:
    /// a single cross-dissolve of the whole card plus a layout pass, so text,
    /// images, stack collapse, and the resulting height settle together
    /// instead of via N independent per-element flips and a deferred reflow.
    ///
    /// Pass `animated: false` for the first bind (the slot is appearing for
    /// the first time — no prior content to dissolve from), `true` for a
    /// re-bind/refresh.
    public func applyNativeContentUpdate(
        animated: Bool,
        _ updates: @escaping () -> Void
    ) {
        guard animated else {
            updates()
            setNeedsLayout()
            layoutIfNeeded()
            return
        }
        UIView.transition(
            with: self,
            duration: 0.25,
            options: [.transitionCrossDissolve, .allowAnimatedContent, .beginFromCurrentState]
        ) {
            updates()
            self.layoutIfNeeded()
        }
    }
}

extension String {

    /// Returns the string with only its first character uppercased; the
    /// rest is left unchanged. Unlike `capitalized` (which title-cases
    /// every word), this yields sentence-style capitalization — applied to
    /// native-ad headline / advertiser / body text so each begins with a
    /// capital letter without altering the publisher's original casing.
    public func capitalizingFirstLetter() -> String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
#endif
