//
//  UIView+Extensions.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 17/2/25.
//

#if canImport(UIKit)
    import UIKit
    import ObjectiveC

    @MainActor private var ResizeCallbackKey: UInt8 = 0
    @MainActor private var PreviousSizeKey: UInt8 = 1

    extension UIView {

        public func onResize(_ callback: @escaping (_ oldSize: CGSize, _ newSize: CGSize) -> Void) {
            UIView.swizzleLayoutSubviewsIfNeeded()
            objc_setAssociatedObject(self, &ResizeCallbackKey, callback, .OBJC_ASSOCIATION_COPY_NONATOMIC)
            objc_setAssociatedObject(self, &PreviousSizeKey, self.bounds.size, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }

        private static let swizzleLayoutSubviewsIfNeeded: () -> Void = {
            let original = class_getInstanceMethod(UIView.self, #selector(UIView.layoutSubviews))!
            let swizzled = class_getInstanceMethod(UIView.self, #selector(UIView.swizzled_layoutSubviews))!
            method_exchangeImplementations(original, swizzled)
        }

        @objc private func swizzled_layoutSubviews() {
            self.swizzled_layoutSubviews()  // This actually calls the original layoutSubviews

            guard let callback = objc_getAssociatedObject(self, &ResizeCallbackKey) as? ((CGSize, CGSize) -> Void)
            else {
                return
            }

            let previousSize = objc_getAssociatedObject(self, &PreviousSizeKey) as? CGSize ?? .zero
            let newSize = self.bounds.size

            if previousSize != newSize {
                callback(previousSize, newSize)
                objc_setAssociatedObject(self, &PreviousSizeKey, newSize, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
    }

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

        public func removeBlur() {
            subviews
                .filter { $0 is UIVisualEffectView }
                .forEach { $0.removeFromSuperview() }
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
#endif
