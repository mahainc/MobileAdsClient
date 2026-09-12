//
//  FullScreenNativeAdContainerView.swift
//  MobileAdsClient
//
//  Hosts `FullScreenNativeAdView` and overlays the close chrome — countdown pill,
//  blur chip, close button — as a sibling rather than a subview of the ad view.
//

#if canImport(UIKit)
@preconcurrency import GoogleMobileAds
import NativeAdClient
import UIKit

/// Geometry of the close chrome. `FullScreenNativeAdContainerView` lays the
/// chrome out from these; `FullScreenNativeAdView` reserves the same space so
/// its content cluster never slides underneath. Both read the one definition
/// instead of each assuming the other's numbers.
enum FullScreenCloseChromeLayout {
    static let topInset: CGFloat = 8
    static let horizontalInset: CGFloat = 20
    static let height: CGFloat = 34
    /// Minimum gap between the chrome and the content cluster below it.
    static let contentGap: CGFloat = 12
    /// Inset of the countdown pill's text inside its own rounded background.
    static let countdownPadding = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)

    /// Space the ad view keeps clear at its top for the overlaid chrome.
    static var reservedTopSpace: CGFloat {
        topInset + height + contentGap
    }
}

/// A full-screen native ad plus its close chrome.
///
/// The close control is deliberately **not** a subview of the `NativeAdView`.
/// GoogleMobileAds attributes clicks through the asset views registered on that
/// view, and keeping an unregistered control out of its hierarchy altogether is
/// what makes a close tap structurally unable to read as an ad tap — rather than
/// relying on the SDK to tell them apart.
public final class FullScreenNativeAdContainerView: UIView {

    public typealias Configuration = NativeAdClient.Configuration.FullScreen

    /// Exposed so a SwiftUI wrapper or hosting controller can hook its
    /// `addTarget` to a dismiss callback.
    ///
    /// Built through the designated initialiser, never `init(type:)`: that one is
    /// documented not to return an instance of a `UIButton` subclass, which would
    /// leave `hitSlop` and the `point(inside:)` override silently inert. The glyph
    /// is an SF Symbol, so it tints from `tintColor` without a system button.
    public let closeButton = CloseHitSlopButton(frame: .zero)

    /// Forwarded to the hosted ad view, which restyles itself on assignment.
    /// The close chrome takes its colors from the same style.
    public var style: NativeAdClient.Configuration.Style {
        get { adView.style }
        set {
            adView.style = newValue
            applyCloseChromeStyle()
        }
    }

    /// The bound ad, or `nil` before the first `configure(with:)`.
    public var nativeAd: NativeAd? { adView.nativeAd }

    private let adView: FullScreenNativeAdView

    private let closeButtonBlurView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        return view
    }()

    /// Occupies the close button's slot while the gate is counting down; the two
    /// swap at zero and are never both visible.
    private let countdownLabel: PaddedLabel = {
        let label = PaddedLabel(padding: FullScreenCloseChromeLayout.countdownPadding)
        label.accessibilityIdentifier = "Full Screen Native Countdown"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .footnote)
        label.layer.masksToBounds = true
        return label
    }()

    private let closeOverlay: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Point size of the `xmark` glyph. The SF symbol renders narrower than its
    /// point size, so this yields a roughly 20pt mark inside the 34pt chip.
    private static let closeGlyphPointSize: CGFloat = 11
    /// Cross-dissolve when the countdown pill gives way to the close chip.
    private static let revealDuration: TimeInterval = 0.2

    /// Seconds the ad stays locked before the close button appears (`0` = no gate).
    private let closeCountdown: Int
    private var secondsRemaining: Int
    private var countdownTimer: Timer?
    /// Guards `didMoveToWindow` so the countdown starts exactly once.
    private var countdownStarted = false

    public init(
        frame: CGRect = .zero,
        configuration: Configuration = .default
    ) {
        self.adView = FullScreenNativeAdView(configuration: configuration)
        self.closeCountdown = max(0, configuration.closeCountdown)
        self.secondsRemaining = max(0, configuration.closeCountdown)
        super.init(frame: frame)
        closeButton.hitSlop = configuration.closeHitSlop
        setupViews()
        applyCloseChromeStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        countdownTimer?.invalidate()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        closeButton.layer.cornerRadius = closeButton.bounds.height / 2
        closeButtonBlurView.layer.cornerRadius = closeButtonBlurView.bounds.height / 2
        countdownLabel.layer.cornerRadius = countdownLabel.bounds.height / 2
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            countdownTimer?.invalidate()
            countdownTimer = nil
        } else {
            startCloseCountdownIfNeeded()
        }
    }

    public func configure(with nativeAd: NativeAd) {
        adView.configure(with: nativeAd)
    }
}

// MARK: - Setup

extension FullScreenNativeAdContainerView {
    private func setupViews() {
        buildHierarchy()
        NSLayoutConstraint.activate(layoutConstraints())
        applyInitialGateState()
    }

    private func buildHierarchy() {
        adView.translatesAutoresizingMaskIntoConstraints = false
        configureCloseButton()

        closeButtonBlurView.contentView.addSubview(closeButton)
        closeOverlay.addSubview(closeButtonBlurView)
        closeOverlay.addSubview(countdownLabel)

        // Ad view first, chrome on top of it — as siblings, so nothing in the
        // chrome belongs to the `NativeAdView` hierarchy.
        addSubview(adView)
        addSubview(closeOverlay)
    }

    private func layoutConstraints() -> [NSLayoutConstraint] {
        let guide = safeAreaLayoutGuide
        let layout = FullScreenCloseChromeLayout.self
        let chip = closeButtonBlurView.contentView

        return [
            adView.topAnchor.constraint(equalTo: topAnchor),
            adView.leadingAnchor.constraint(equalTo: leadingAnchor),
            adView.trailingAnchor.constraint(equalTo: trailingAnchor),
            adView.bottomAnchor.constraint(equalTo: bottomAnchor),

            closeOverlay.topAnchor.constraint(equalTo: guide.topAnchor, constant: layout.topInset),
            closeOverlay.leadingAnchor.constraint(
                equalTo: guide.leadingAnchor,
                constant: layout.horizontalInset
            ),
            closeOverlay.trailingAnchor.constraint(
                equalTo: guide.trailingAnchor,
                constant: -layout.horizontalInset
            ),
            closeOverlay.heightAnchor.constraint(equalToConstant: layout.height),

            closeButtonBlurView.leadingAnchor.constraint(equalTo: closeOverlay.leadingAnchor),
            closeButtonBlurView.centerYAnchor.constraint(equalTo: closeOverlay.centerYAnchor),
            closeButtonBlurView.widthAnchor.constraint(equalToConstant: layout.height),
            closeButtonBlurView.heightAnchor.constraint(equalToConstant: layout.height),

            // The button fills the chip, so the whole circle is tappable before
            // `hitSlop` widens the target any further.
            closeButton.topAnchor.constraint(equalTo: chip.topAnchor),
            closeButton.leadingAnchor.constraint(equalTo: chip.leadingAnchor),
            closeButton.trailingAnchor.constraint(equalTo: chip.trailingAnchor),
            closeButton.bottomAnchor.constraint(equalTo: chip.bottomAnchor),

            countdownLabel.leadingAnchor.constraint(equalTo: closeOverlay.leadingAnchor),
            countdownLabel.centerYAnchor.constraint(equalTo: closeOverlay.centerYAnchor),
            countdownLabel.topAnchor.constraint(greaterThanOrEqualTo: closeOverlay.topAnchor),
            countdownLabel.bottomAnchor.constraint(lessThanOrEqualTo: closeOverlay.bottomAnchor),
        ]
    }

    /// While a gate is configured the pill shows and the close chip hides; the
    /// timer swaps them at zero. No gate means the chip is tappable immediately.
    private func applyInitialGateState() {
        let isGated = closeCountdown > 0
        countdownLabel.isHidden = !isGated
        closeButtonBlurView.isHidden = isGated
        if isGated {
            countdownLabel.text = countdownText(for: secondsRemaining)
        }
    }

    private func configureCloseButton() {
        closeButton.accessibilityIdentifier = "Full Screen Native Close Button"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        let symbol = UIImage.SymbolConfiguration(pointSize: Self.closeGlyphPointSize, weight: .bold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: symbol), for: .normal)
        closeButton.imageView?.contentMode = .scaleAspectFit
        closeButton.layer.masksToBounds = true
    }

    private func applyCloseChromeStyle() {
        // `closeButton.text` doubles as the glyph tint. The background is the
        // blur effect, so the button itself stays clear and lets it through.
        closeButton.tintColor = style.closeButton.text
        closeButton.backgroundColor = .clear
        // The countdown pill borrows the chip's colors so the swap at zero is
        // visually seamless.
        countdownLabel.backgroundColor = style.closeButton.background
        countdownLabel.textColor = style.closeButton.text
    }
}

// MARK: - Close countdown

extension FullScreenNativeAdContainerView {
    private func countdownText(for seconds: Int) -> String {
        "Ad · closes in \(seconds)s"
    }

    /// Starts the 1s countdown once the view is on screen. No-op when the gate
    /// is off (`closeCountdown == 0`) or already started.
    private func startCloseCountdownIfNeeded() {
        guard closeCountdown > 0, !countdownStarted else {
            return
        }
        countdownStarted = true
        countdownLabel.text = countdownText(for: secondsRemaining)

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            // Added to `RunLoop.main` below, so the block always fires on the
            // main actor — assert that to reach this view's isolated state.
            MainActor.assumeIsolated {
                self.tickCountdown()
            }
        }
        // `.common` so the countdown keeps ticking during scroll/tracking runloop
        // modes (the media view may drive its own interactions).
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func tickCountdown() {
        secondsRemaining -= 1
        guard secondsRemaining <= 0 else {
            countdownLabel.text = countdownText(for: secondsRemaining)
            return
        }
        countdownTimer?.invalidate()
        countdownTimer = nil
        revealCloseButton()
    }

    /// Swaps the countdown pill for the tappable close chip, with a quick
    /// cross-dissolve so the transition isn't abrupt.
    private func revealCloseButton() {
        UIView.transition(
            with: closeOverlay,
            duration: Self.revealDuration,
            options: [.transitionCrossDissolve, .beginFromCurrentState]
        ) {
            self.countdownLabel.isHidden = true
            self.closeButtonBlurView.isHidden = false
        }
    }
}
#endif
