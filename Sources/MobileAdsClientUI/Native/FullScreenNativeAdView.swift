//
//  FullScreenNativeAdView.swift
//  MobileAdsClient
//
//  UIKit renderer for a native ad presented as a full-screen modal. Built from
//  `GoogleMobileAds` primitives only — no dependency on `ads_swift`. Intended
//  to back `MobileAdsClient.showNativeFullScreen(_:)` via `UIHostingController`.
//
//  Immersive full-bleed layout: the media view fills the ENTIRE screen and every
//  other element overlays on top of it. A bottom gradient scrim (clear → black)
//  sits behind the content cluster so light text stays legible over arbitrary
//  creative imagery.
//
//    ┌────────────────────────────────────┐
//    │  [×] [Ad]            (AdChoices)   │   close + ad chip top-left (over media)
//    │                                    │
//    │         FULL-BLEED MEDIA           │   edge-to-edge, scaleAspectFill
//    │         (under notch +             │
//    │          home indicator)           │
//    │░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│ ← scrim (clear → black) starts here
//    │  [Icon] Headline                   │
//    │         Sponsor                    │
//    │  Body (3 lines max)                │
//    │  [    Install Now CTA    ]         │   pill, above safe-bottom
//    └────────────────────────────────────┘
//
//  Per Google's full-screen native guidance, each interactive ad asset (CTA,
//  headline, body) is wrapped in its own plain `UIView` container that is a
//  subview of this `NativeAdView`. The SDK disables `isUserInteractionEnabled`
//  on registered asset views (but not their containers) while video plays, so
//  wrapping keeps taps attributable instead of falling through to the media view
//  — which matters even more here, since assets now sit directly over the media.
//

#if canImport(UIKit)
    import GoogleMobileAds
    import NativeAdClient
    import UIKit

    public class FullScreenNativeAdView: NativeAdView {

        public typealias Style = NativeAdClient.Configuration.Style
        public typealias Configuration = NativeAdClient.Configuration.FullScreen

        public var style: Style {
            didSet { applyStyle() }
        }

        private let metrics: NativeAdClient.Configuration.Metrics
        private let bodyDisplay: NativeAdClient.Configuration.BodyDisplay
        private let mediaIgnoresSafeArea: Bool
        private let mediaContentMode: UIView.ContentMode

        // MARK: - Close countdown

        /// Seconds the ad stays locked before the close button appears (`0` = no gate).
        private let closeCountdown: Int
        private var secondsRemaining: Int
        private var countdownTimer: Timer?
        /// Guards `didMoveToWindow` so the countdown starts exactly once.
        private var countdownStarted = false

        /// Exposed so the SwiftUI wrapper / hosting controller can hook its
        /// `addTarget` to an `onClose` callback. The button fills
        /// `closeButtonBlurView` (its 34×34 contentView), so the whole circular
        /// chip is the tappable element with the `xmark` glyph centered inside.
        public let closeButton: UIButton = {
            let button = UIButton(type: .system)
            button.accessibilityIdentifier = "Full Screen Native Close Button"
            button.translatesAutoresizingMaskIntoConstraints = false
            // ~20×20 glyph (the SF `xmark` renders narrower than its point size).
            let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
            button.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
            button.imageView?.contentMode = .scaleAspectFit
            button.layer.borderWidth = 1
            button.layer.masksToBounds = true
            return button
        }()

        /// Blur backing that hosts `closeButton` inside its `contentView`. Stays
        /// interactive so the embedded button receives the tap. Hidden while the
        /// close countdown is running and revealed (with the button) at 0.
        private let closeButtonBlurView: UIVisualEffectView = {
            let view = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
            view.translatesAutoresizingMaskIntoConstraints = false
            view.clipsToBounds = true
            return view
        }()

        // MARK: - Subviews

        private lazy var adMediaView: MediaView = {
            let view = MediaView()
            view.translatesAutoresizingMaskIntoConstraints = false
            // `contentMode` is driven by config — set in `setupViews()` and
            // re-asserted in `updateUI` (the SDK resets it on `mediaContent`).
            view.contentMode = mediaContentMode
            // Full-bleed: no corner radius — the media reaches every screen edge.
            view.layer.masksToBounds = true
            view.clipsToBounds = true
            return view
        }()

        /// Bottom gradient scrim (clear → black) that sits between the full-bleed
        /// media and the overlaid content cluster so light text stays legible. The
        /// gradient is a managed `CAGradientLayer` applied via `applyBackgroundFill`
        /// and re-framed in `layoutSubviews()`. Non-interactive so taps pass through
        /// to the media view (video controls) and the registered asset containers.
        private lazy var scrimView: UIView = {
            let view = UIView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            return view
        }()

        private lazy var adIconImageView: UIImageView = {
            let imageView = UIImageView()
            imageView.accessibilityIdentifier = "Full Screen Native Icon"
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFill
            // Corner radius is driven by `metrics.iconCornerRadius` and applied in `setupViews()`.
            imageView.layer.masksToBounds = true
            return imageView
        }()

        private lazy var adHeadlineLabel: UILabel = {
            let label = UILabel()
            label.accessibilityIdentifier = "Full Screen Native Headline"
            label.translatesAutoresizingMaskIntoConstraints = false
            // Title must never be truncated (Google native policy: ≤25 chars, no
            // truncation). Allow it to wrap rather than clip with an ellipsis.
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            return label
        }()

        private lazy var adSponsorLabel: UILabel = {
            let label = UILabel()
            label.accessibilityIdentifier = "Full Screen Native Sponsor"
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 1
            return label
        }()

        private lazy var adBodyLabel: UILabel = {
            let label = UILabel()
            label.accessibilityIdentifier = "Full Screen Native Body"
            label.translatesAutoresizingMaskIntoConstraints = false
            // `numberOfLines` is driven by `bodyDisplay` in `setupViews()`. Default
            // here is a safe cap so a long creative never eats into the media area
            // above the scrim; headline stays uncapped (≤25-char policy → ≤2 lines).
            label.numberOfLines = 3
            label.lineBreakMode = .byWordWrapping
            return label
        }()

        private lazy var adAttributionLabel: PaddedLabel = {
            let label = PaddedLabel(padding: UIEdgeInsets(top: 3, left: 6, bottom: 3, right: 6))
            label.accessibilityIdentifier = "Full Screen Native Attribution"
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = "Ad"
            label.textAlignment = .center
            label.layer.cornerRadius = 4
            label.layer.masksToBounds = true
            return label
        }()

        /// Shown in the close button's slot while the countdown is running ("closes
        /// in Ns"); hidden once it reaches 0 and replaced by `closeButton`. Styled
        /// from `style.closeButton` so it matches the `×` chip.
        private lazy var countdownLabel: PaddedLabel = {
            let label = PaddedLabel(padding: UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12))
            label.accessibilityIdentifier = "Full Screen Native Countdown"
            label.translatesAutoresizingMaskIntoConstraints = false
            label.textAlignment = .center
            label.font = .preferredFont(forTextStyle: .footnote)
            label.layer.masksToBounds = true
            return label
        }()

        private lazy var actionButton: UIButton = {
            let button = UIButton(type: .system)
            // Use `UIButton.Configuration` (iOS 15+) so `contentInsets` — the
            // modern replacement for the deprecated `contentEdgeInsets` — takes
            // effect. Background, foreground, font, and corner radius are all
            // driven via the same configuration in `applyStyle()` / `applyButtonShape()`.
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
            button.configuration = config
            button.accessibilityIdentifier = "Full Screen Native CTA"
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setTitle("Install Now", for: .normal)
            // CTA is not user-interactive at the UIKit level — GoogleMobileAds'
            // NativeAdView proxies taps through `callToActionView` binding.
            button.isUserInteractionEnabled = false
            return button
        }()

        // MARK: - Asset containers

        // Each interactive asset lives inside a plain container `UIView` (see the
        // file header). Held as properties so `updateVisibility(for:)` can collapse
        // the header / body rows inside `midStack` when their assets are absent.
        private let headerContainer = FullScreenNativeAdView.makeContainer()
        private let bodyContainer = FullScreenNativeAdView.makeContainer()
        private let ctaContainer = FullScreenNativeAdView.makeContainer()
        private let mediaContainer = FullScreenNativeAdView.makeContainer()

        private static func makeContainer() -> UIView {
            let view = UIView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.backgroundColor = .clear
            return view
        }

        // MARK: - Init

        public init(
            frame: CGRect = .zero,
            configuration: Configuration = .default
        ) {
            self.style = configuration.style
            self.metrics = configuration.metrics
            self.bodyDisplay = configuration.bodyDisplay
            self.mediaIgnoresSafeArea = configuration.mediaIgnoresSafeArea
            switch configuration.mediaContentMode {
                case .fill:
                    self.mediaContentMode = .scaleAspectFill
                case .fit:
                    self.mediaContentMode = .scaleAspectFit
            }
            self.closeCountdown = max(0, configuration.closeCountdown)
            self.secondsRemaining = max(0, configuration.closeCountdown)
            super.init(frame: frame)
            setupViews()
            applyStyle()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        isolated deinit {
            countdownTimer?.invalidate()
        }

        public override func layoutSubviews() {
            super.layoutSubviews()
            layoutNativeAdGradient()
            // Keep the scrim's managed gradient layer sized to the scrim's bounds.
            scrimView.layoutNativeAdGradient()
            applyButtonShape()
            closeButton.layer.cornerRadius = closeButton.bounds.height / 2
            // Clip the blur backing to the same circle as the button.
            closeButtonBlurView.layer.cornerRadius = closeButtonBlurView.bounds.height / 2
            countdownLabel.layer.cornerRadius = countdownLabel.bounds.height / 2
        }

        public override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                // Dismissed / detached mid-countdown — stop the timer.
                countdownTimer?.invalidate()
                countdownTimer = nil
            } else {
                // Now on screen — start the countdown once.
                startCloseCountdownIfNeeded()
            }
        }
    }

    // MARK: - Setup

    extension FullScreenNativeAdView {
        private func setupViews() {
            // No card corner radius — the media is full-bleed to every screen edge.
            layer.masksToBounds = true

            adIconImageView.layer.cornerRadius = metrics.iconCornerRadius

            // Body line count from config. `.hidden` is handled in `updateVisibility`.
            switch bodyDisplay.mode {
                case .hidden, .full:
                    adBodyLabel.numberOfLines = 0
                case let .truncated(lines):
                    adBodyLabel.numberOfLines = max(1, lines)
            }

            // Sponsor + "Ad" chip share a line below the headline. The chip hugs
            // its content so it sits right after the sponsor (or leads the row when
            // the sponsor is absent).
            adAttributionLabel.setContentHuggingPriority(.required, for: .horizontal)
            adAttributionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            let sponsorRow = UIStackView(arrangedSubviews: [adSponsorLabel, adAttributionLabel])
            sponsorRow.axis = .horizontal
            sponsorRow.spacing = 6
            sponsorRow.alignment = .center
            sponsorRow.translatesAutoresizingMaskIntoConstraints = false

            // Header: icon | (headline / sponsor + Ad chip). Wrapped in `headerContainer`.
            let textStack = UIStackView(arrangedSubviews: [adHeadlineLabel, sponsorRow])
            textStack.axis = .vertical
            textStack.spacing = 2
            textStack.alignment = .leading
            textStack.translatesAutoresizingMaskIntoConstraints = false
            textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let headerStack = UIStackView(arrangedSubviews: [adIconImageView, textStack])
            headerStack.axis = .horizontal
            headerStack.spacing = metrics.horizontalSpacing
            headerStack.alignment = .center
            headerStack.translatesAutoresizingMaskIntoConstraints = false
            headerContainer.addSubview(headerStack)

            // Body + CTA each wrapped in their own container.
            bodyContainer.addSubview(adBodyLabel)
            ctaContainer.addSubview(actionButton)

            // Bottom content cluster: header → body → CTA, collapsing rows hidden.
            let bottomCluster = AutoHidingStackView()
            bottomCluster.axis = .vertical
            bottomCluster.spacing = 10
            bottomCluster.alignment = .fill
            bottomCluster.distribution = .fill
            bottomCluster.translatesAutoresizingMaskIntoConstraints = false
            bottomCluster.addArrangedSubview(headerContainer)
            bottomCluster.addArrangedSubview(bodyContainer)
            bottomCluster.addArrangedSubview(ctaContainer)

            // Media in its own container (kept for click-attribution consistency).
            mediaContainer.addSubview(adMediaView)

            // Top bar holds the close button and the countdown label (only one is
            // visible at a time), top-left, so the top-right corner stays clear for
            // the SDK's AdChoices overlay. The "Ad" chip lives in the header row.
            let topBar = UIView()
            topBar.translatesAutoresizingMaskIntoConstraints = false
            topBar.addSubview(closeButtonBlurView)
            topBar.addSubview(countdownLabel)

            closeButtonBlurView.contentView.addSubview(closeButton)

            // Back → front: media (full-bleed) → scrim → controls.
            addSubview(mediaContainer)
            addSubview(scrimView)
            addSubview(topBar)
            addSubview(bottomCluster)

            let guide = safeAreaLayoutGuide

            // Media edges: the view's own edges (full-bleed, under notch + home
            // indicator) when `mediaIgnoresSafeArea`, else inset to the safe area.
            // `pinMediaContainer` reads `mediaIgnoresSafeArea` to pick the source.
            NSLayoutConstraint.activate(mediaContainerEdgeConstraints())

            NSLayoutConstraint.activate([
                adMediaView.topAnchor.constraint(equalTo: mediaContainer.topAnchor),
                adMediaView.leadingAnchor.constraint(equalTo: mediaContainer.leadingAnchor),
                adMediaView.trailingAnchor.constraint(equalTo: mediaContainer.trailingAnchor),
                adMediaView.bottomAnchor.constraint(equalTo: mediaContainer.bottomAnchor),

                // Scrim: bottom 55% of the screen, behind the controls.
                scrimView.leadingAnchor.constraint(equalTo: leadingAnchor),
                scrimView.trailingAnchor.constraint(equalTo: trailingAnchor),
                scrimView.bottomAnchor.constraint(equalTo: bottomAnchor),
                scrimView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.55),

                // Top bar — close button, over the media (safe-area top-left).
                topBar.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
                topBar.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
                topBar.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
                topBar.heightAnchor.constraint(equalToConstant: 34),

                closeButtonBlurView.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
                closeButtonBlurView.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
                closeButtonBlurView.widthAnchor.constraint(equalToConstant: 34),
                closeButtonBlurView.heightAnchor.constraint(equalToConstant: 34),

                // Close button fills the blur chip so the full circle is tappable.
                closeButton.centerXAnchor.constraint(equalTo: closeButtonBlurView.contentView.centerXAnchor),
                closeButton.centerYAnchor.constraint(equalTo: closeButtonBlurView.contentView.centerYAnchor),
                closeButton.widthAnchor.constraint(equalToConstant: 18),
                closeButton.heightAnchor.constraint(equalToConstant: 18),

                // Countdown label occupies the same top-left slot as the close
                // button (hugs its text); only one of the two is ever visible.
                countdownLabel.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
                countdownLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
                countdownLabel.topAnchor.constraint(greaterThanOrEqualTo: topBar.topAnchor),
                countdownLabel.bottomAnchor.constraint(lessThanOrEqualTo: topBar.bottomAnchor),

                // Bottom cluster overlays the scrim: 20pt horizontal padding, flush
                // to the safe-area bottom (0pt) so it clears the home indicator
                // without an extra gap.
                bottomCluster.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
                bottomCluster.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
                bottomCluster.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: 0),
                // Never let the cluster grow past the top bar into the media.
                bottomCluster.topAnchor.constraint(greaterThanOrEqualTo: topBar.bottomAnchor, constant: 12),

                headerStack.topAnchor.constraint(equalTo: headerContainer.topAnchor),
                headerStack.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
                headerStack.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
                headerStack.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor),

                adIconImageView.widthAnchor.constraint(equalToConstant: metrics.iconSize.width)
                    .priority(UILayoutPriority(999)),
                adIconImageView.heightAnchor.constraint(equalToConstant: metrics.iconSize.height)
                    .priority(UILayoutPriority(999)),

                adBodyLabel.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
                adBodyLabel.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
                adBodyLabel.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
                adBodyLabel.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),

                actionButton.topAnchor.constraint(equalTo: ctaContainer.topAnchor),
                actionButton.leadingAnchor.constraint(equalTo: ctaContainer.leadingAnchor),
                actionButton.trailingAnchor.constraint(equalTo: ctaContainer.trailingAnchor),
                actionButton.bottomAnchor.constraint(equalTo: ctaContainer.bottomAnchor),
                actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: metrics.ctaMinHeight),
            ])

            // Initial close-gate state: while a countdown is configured, show the
            // label and hide the close-button chip; the timer (started in
            // `didMoveToWindow`) swaps them at 0. No gate → close chip shown.
            let gated = closeCountdown > 0
            countdownLabel.isHidden = !gated
            closeButtonBlurView.isHidden = gated
            if gated {
                countdownLabel.text = countdownText(for: secondsRemaining)
            }
        }

        /// Pins `mediaContainer`'s four edges to either the view's own edges
        /// (full-bleed, when `mediaIgnoresSafeArea`) or the safe-area guide.
        private func mediaContainerEdgeConstraints() -> [NSLayoutConstraint] {
            if mediaIgnoresSafeArea {
                return [
                    mediaContainer.topAnchor.constraint(equalTo: topAnchor),
                    mediaContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
                    mediaContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
                    mediaContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
                ]
            } else {
                let guide = safeAreaLayoutGuide
                return [
                    mediaContainer.topAnchor.constraint(equalTo: guide.topAnchor),
                    mediaContainer.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
                    mediaContainer.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
                    mediaContainer.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
                ]
            }
        }

        // MARK: - Close countdown

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
                // The timer is added to `RunLoop.main` below, so the block always
                // fires on the main actor — assert that to reach this view's
                // main-actor-isolated state.
                MainActor.assumeIsolated {
                    self.secondsRemaining -= 1
                    if self.secondsRemaining > 0 {
                        self.countdownLabel.text = self.countdownText(for: self.secondsRemaining)
                    } else {
                        self.countdownTimer?.invalidate()
                        self.countdownTimer = nil
                        self.revealCloseButton()
                    }
                }
            }
            // `.common` so the countdown keeps ticking during scroll/tracking runloop
            // modes (the media view may drive its own interactions).
            RunLoop.main.add(timer, forMode: .common)
            countdownTimer = timer
        }

        /// Swaps the countdown label for the tappable close button, with a quick
        /// cross-dissolve so the transition isn't abrupt.
        private func revealCloseButton() {
            UIView.transition(
                with: self,
                duration: 0.2,
                options: [.transitionCrossDissolve, .beginFromCurrentState]
            ) {
                self.countdownLabel.isHidden = true
                self.closeButtonBlurView.isHidden = false
            }
        }

        private func applyStyle() {
            applyBackgroundFill(style.backgrounds.card)
            // Bottom scrim: transparent at the top, fading to near-opaque black at
            // the bottom so the overlaid light text reads over any creative.
            scrimView.applyBackgroundFill(
                .gradient(
                    colors: [
                        .clear,
                        UIColor.black.withAlphaComponent(0.85),
                    ],
                    locations: [0.0, 1.0],
                    direction: .vertical
                )
            )
            adHeadlineLabel.textColor = style.text.headline
            adHeadlineLabel.font = style.text.headlineFont.resolved
            adBodyLabel.textColor = style.text.body
            adBodyLabel.font = style.text.bodyFont.resolved
            adSponsorLabel.textColor = style.text.sponsor
            adSponsorLabel.font = style.text.sponsorFont.resolved
            adAttributionLabel.backgroundColor = style.attribution.background
            adAttributionLabel.textColor = style.attribution.text
            adAttributionLabel.font = style.attribution.font.resolved
            var buttonConfig = actionButton.configuration ?? UIButton.Configuration.plain()
            buttonConfig.contentInsets = NSDirectionalEdgeInsets(style.actionButton.contentInsets)
            buttonConfig.background.backgroundColor = style.actionButton.background
            buttonConfig.baseForegroundColor = style.actionButton.title
            let titleFont = style.actionButton.font.resolved
            buttonConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { container in
                var updated = container
                updated.font = titleFont
                return updated
            }
            actionButton.configuration = buttonConfig
            // `closeButton.text` doubles as the icon tint color for the close button.
            closeButton.tintColor = style.closeButton.text
            // Background is the blur effect view, not a solid fill — keep the button
            // itself clear so the blur shows through. A thin border outlines the chip.
            closeButton.backgroundColor = .clear
            closeButtonBlurView.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
            // Countdown label shares the close button's chip colors so the swap at 0
            // is visually seamless.
            countdownLabel.backgroundColor = style.closeButton.background
            countdownLabel.textColor = style.closeButton.text
            applyButtonShape()
        }

        private func applyButtonShape() {
            var config = actionButton.configuration ?? UIButton.Configuration.plain()
            switch style.actionButton.shape.mode {
                case let .rect(cornerRadius):
                    config.cornerStyle = .fixed
                    config.background.cornerRadius = cornerRadius
                case .capsule:
                    config.cornerStyle = .capsule
            }
            actionButton.configuration = config
        }
    }

    // MARK: - Public API

    extension FullScreenNativeAdView {
        public func configure(with nativeAd: NativeAd) {
            // Re-bind cross-dissolves; first bind applies instantly.
            let animated = self.nativeAd != nil
            applyNativeContentUpdate(animated: animated) { [self] in
                updateUI(with: nativeAd)
                updateViewBindings()
                updateVisibility(for: nativeAd)

                self.nativeAd = nativeAd

                // The Google SDK rebinds the registered `iconView` when `nativeAd`
                // is assigned and may reset its image-rendering knobs. Re-assert
                // them here so the icon stays cropped-and-filled inside its slot
                // instead of being letterboxed at the asset's native aspect ratio.
                adIconImageView.contentMode = .scaleAspectFill
                adIconImageView.clipsToBounds = true
                adIconImageView.layer.masksToBounds = true
            }
        }
    }

    // MARK: - Private Helpers

    extension FullScreenNativeAdView {
        private func updateUI(with nativeAd: NativeAd) {
            adMediaView.mediaContent = nativeAd.mediaContent
            // Re-assert AFTER assigning `mediaContent` — the SDK resets the media
            // view's `contentMode` on assignment, which would otherwise override the
            // configured fill/fit behavior.
            adMediaView.contentMode = mediaContentMode
            adIconImageView.image = nativeAd.icon?.image
            adHeadlineLabel.text = nativeAd.headline?.capitalizingFirstLetter()
            adSponsorLabel.text = nativeAd.advertiser?.capitalizingFirstLetter()
            adBodyLabel.text = nativeAd.body?.capitalizingFirstLetter()
            actionButton.setTitle(nativeAd.callToAction?.uppercased(), for: .normal)
        }

        private func updateViewBindings() {
            self.mediaView = adMediaView
            self.iconView = adIconImageView
            self.headlineView = adHeadlineLabel
            self.advertiserView = adSponsorLabel
            self.bodyView = adBodyLabel
            self.callToActionView = actionButton
        }

        private func updateVisibility(for nativeAd: NativeAd) {
            // Media is full-bleed and always visible — if a creative has no media
            // (rare for full-screen), the solid card background fills behind the
            // scrim, keeping the overlaid text legible. No collapse here.

            adIconImageView.isHidden = nativeAd.icon?.image == nil
            adHeadlineLabel.isHidden = nativeAd.headline == nil
            adSponsorLabel.isHidden = nativeAd.advertiser == nil
            // Collapse the whole header row when none of its assets are present so
            // `midStack` reclaims the spacing.
            headerContainer.isHidden =
                nativeAd.icon?.image == nil && nativeAd.headline == nil && nativeAd.advertiser == nil

            // Hide the body when the creative has none OR config says `.hidden`.
            let bodyHidden = nativeAd.body == nil || bodyDisplay.mode == .hidden
            adBodyLabel.isHidden = bodyHidden
            // Drive the container too — the bottom cluster is an `AutoHidingStackView`,
            // so a hidden `bodyContainer` collapses and removes its inter-row spacing.
            bodyContainer.isHidden = bodyHidden

            actionButton.isHidden = nativeAd.callToAction == nil
        }
    }

#endif
